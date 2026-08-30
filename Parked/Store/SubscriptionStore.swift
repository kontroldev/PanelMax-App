import Foundation
import StoreKit

/// Las suscripciones autorrenovables permanecen desactivadas mientras Premium
/// solo aporte ventajas locales. Actívalas en una configuración de build con
/// `ENABLE_RECURRING_SUBSCRIPTIONS = YES` cuando exista un servicio
/// continuado que justifique la renovación.
enum StoreConfiguration {
    static var recurringSubscriptionsEnabled: Bool {
        let configuredValue = Bundle.main.object(
            forInfoDictionaryKey: "ENABLE_RECURRING_SUBSCRIPTIONS"
        )

        if let enabled = configuredValue as? Bool { return enabled }
        if let enabled = configuredValue as? String {
            return (enabled as NSString).boolValue
        }
        return false
    }
}

/// Identificadores de producto. Deben coincidir EXACTAMENTE con App Store Connect
/// y con el fichero `PanelMax.storekit` que se usa para probar en local.
enum ProductID {
    static let monthly  = "com.raulgallego.panelmax.premium.monthly"
    static let yearly   = "com.raulgallego.panelmax.premium.yearly"
    static let lifetime = "com.raulgallego.panelmax.premium.lifetime"

    static let all: [String] = [monthly, yearly, lifetime]
    static let premiumIDs = Set(all)
    static let subscriptionIDs: Set<String> = [monthly, yearly]

    static var availableForPurchase: [String] {
        StoreConfiguration.recurringSubscriptionsEnabled ? all : [lifetime]
    }
}

/// Estado de la suscripción, en un solo sitio.
///
/// Regla de oro: ninguna vista consulta StoreKit por su cuenta.
/// Todo el mundo pregunta a `isPremium`.
@MainActor
@Observable
final class SubscriptionStore {

    /// Productos cargados desde la App Store, con precio ya localizado.
    private(set) var products: [Product] = []

    /// Identificadores de producto con derecho activo.
    private(set) var purchasedIDs: Set<String> = []

    /// ¿Hay premium? Es lo único que el resto de la app necesita saber.
    var isPremium: Bool { !purchasedIDs.isEmpty }

    /// Distinguir ambos tipos evita ofrecer "Gestionar suscripción" a quien
    /// compró el acceso para siempre (un producto no consumible no se cancela).
    var hasActiveSubscription: Bool {
        !purchasedIDs.isDisjoint(with: ProductID.subscriptionIDs)
    }

    var hasLifetimeAccess: Bool {
        purchasedIDs.contains(ProductID.lifetime)
    }

    /// True mientras se carga o se compra, para deshabilitar botones.
    private(set) var isWorking = false

    /// Último error, para mostrarlo en el muro de pago.
    private(set) var lastError: String?

    /// Tarea que escucha transacciones que llegan por fuera de la app
    /// (compartir en familia, canje de código promocional, compra en otro dispositivo).
    ///
    /// Se asigna una sola vez desde el MainActor en `start()`
    /// y `deinit` solo llama a `cancel()`, que es seguro desde cualquier hilo.
    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?

    @ObservationIgnored
    private var hasStarted = false

    deinit { updatesTask?.cancel() }

    // MARK: - Ciclo de vida

    /// Se llama una vez al arrancar la app.
    func start() async {
        // Las tareas de SwiftUI pueden volver a arrancar. Sin esta guarda se crearía
        // un consumidor adicional de `Transaction.updates` en cada ocasión.
        guard !hasStarted else { return }
        hasStarted = true

        // El escuchador se monta ANTES de nada: si hay una transacción pendiente
        // y no la atiendes, la App Store la reintenta indefinidamente.
        updatesTask = listenForTransactions()
        await loadProducts()
        await refreshEntitlements()
    }

    /// Carga los productos con sus precios localizados.
    func loadProducts() async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            let availableIDs = ProductID.availableForPurchase
            let loaded = try await Product.products(for: availableIDs)
            // Orden fijo: anual, mensual, para siempre. Como en el boceto.
            products = loaded
                .filter { availableIDs.contains($0.id) }
                .sorted { lhs, rhs in
                    order(of: lhs.id) < order(of: rhs.id)
                }

            if products.isEmpty {
                lastError = String(localized: "No hay planes disponibles en este momento. Inténtalo de nuevo más tarde.")
            }
        } catch {
            lastError = String(localized: "No se han podido cargar los planes. Comprueba tu conexión e inténtalo de nuevo.")
        }
    }

    private func order(of id: String) -> Int {
        switch id {
        case ProductID.yearly:   return 0
        case ProductID.monthly:  return 1
        case ProductID.lifetime: return 2
        default:                 return 3
        }
    }

    // MARK: - Compra

    /// Compra un producto. Devuelve true si el usuario acaba con premium activo.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard ProductID.availableForPurchase.contains(product.id) else {
            lastError = String(localized: "Este producto no está disponible para PanelMax+.")
            return false
        }

        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // Verificación criptográfica de la transacción.
                let transaction = try checkVerified(verification)
                // Obligatorio: sin `finish()` la transacción vuelve una y otra vez.
                await transaction.finish()
                // Los productos Premium son no consumibles o suscripciones: tras
                // finalizar, el derecho continúa en `currentEntitlements`.
                await refreshEntitlements()
                return isPremium

            case .userCancelled:
                // No es un error. Ni mensaje ni registro: el usuario ha dicho que no.
                return false

            case .pending:
                // "Solicitar la compra" o un pago pendiente de aprobación.
                lastError = String(localized: "La compra está pendiente de aprobación.")
                return false

            @unknown default:
                lastError = String(localized: "La App Store ha devuelto un resultado de compra no reconocido.")
                return false
            }
        } catch {
            lastError = String(localized: "No se ha podido completar la compra. Inténtalo de nuevo.")
            return false
        }
    }

    /// Restaurar compras. Apple EXIGE este botón en el muro de pago (guideline 3.1.2).
    func restore() async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            // Sincroniza con la App Store. Puede pedir la contraseña de la cuenta.
            try await AppStore.sync()
            await refreshEntitlements()

            if !isPremium {
                lastError = String(localized: "No hemos encontrado compras anteriores con esta cuenta.")
            }
        } catch {
            lastError = String(localized: "No se han podido restaurar las compras. Inténtalo de nuevo.")
        }
    }

    // MARK: - Derechos

    /// Recalcula qué está activo ahora mismo.
    func refreshEntitlements() async {
        var active: Set<String> = []

        // `currentEntitlements` ya excluye lo caducado y lo reembolsado.
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard ProductID.premiumIDs.contains(transaction.productID) else { continue }

            // Si Apple ha reembolsado o revocado, no cuenta.
            if transaction.revocationDate != nil { continue }

            // Suscripción caducada por fecha.
            if let expiration = transaction.expirationDate, expiration < .now { continue }

            active.insert(transaction.productID)
        }

        // Defensa adicional: una compra futura de otro tipo nunca debe activar Premium.
        purchasedIDs = active.intersection(ProductID.premiumIDs)
    }

    /// Escucha transacciones que llegan mientras la app está abierta.
    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.checkVerified(result) else { continue }
                // Este componente no debe consumir ni finalizar compras futuras
                // que tengan su propio flujo de entrega.
                guard ProductID.premiumIDs.contains(transaction.productID) else { continue }
                await self.refreshEntitlements()
                await transaction.finish()
            }
        }
    }

    /// Comprueba la firma de una transacción. Si no está verificada, no vale.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case failedVerification
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Ayudas para la interfaz

    /// Precio equivalente mensual de un plan anual: "1,67 €/mes".
    /// Nunca escribas los precios a mano en la interfaz: se leen de StoreKit,
    /// que los devuelve en la moneda y el formato del país del usuario.
    func monthlyEquivalent(for product: Product) -> String? {
        guard let subscription = product.subscription else { return nil }
        let unit = subscription.subscriptionPeriod

        let months: Int
        switch unit.unit {
        case .year:  months = 12 * unit.value
        case .month: months = unit.value
        case .week:  return nil
        case .day:   return nil
        @unknown default: return nil
        }

        guard months > 1 else { return nil }
        let perMonth = product.price / Decimal(months)
        return perMonth.formatted(.currency(code: product.priceFormatStyle.currencyCode)
            .precision(.fractionLength(2)))
    }

    /// ¿Tiene periodo de prueba disponible y no consumido?
    func hasIntroOffer(_ product: Product) async -> Bool {
        guard let subscription = product.subscription,
              subscription.introductoryOffer != nil else { return false }
        // `isEligibleForIntroOffer` evita prometer una prueba que el usuario ya gastó.
        return await subscription.isEligibleForIntroOffer
    }
}
