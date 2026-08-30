import SwiftUI
import StoreKit

/// Enlaces legales obligatorios.
///
/// Guideline 3.1.2: en la pantalla de compra tienen que estar accesibles
/// las condiciones de uso y la política de privacidad. Y los mismos enlaces
/// hay que repetirlos en la ficha de App Store Connect.
enum LegalLinks {
    /// EULA estándar de Apple. Vale si no tienes contrato propio.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Documentos públicos del repositorio.
    ///
    /// Antes de distribuir conviene sustituirlos por URLs de un dominio propio
    /// (o GitHub Pages): App Store Connect exige que estos enlaces sigan vivos
    /// durante toda la vida de la app, y un repositorio puede pasar a privado.
    static let privacy = URL(string: "https://github.com/kontroldev/PanelMax-App/blob/main/docs/PRIVACY.md")!

    static let support = URL(string: "https://github.com/kontroldev/PanelMax-App/blob/main/docs/SUPPORT.md")!
}

/// El muro de pago.
///
/// Todo lo que Apple exige está aquí y está marcado con el comentario `// 3.1.2`.
/// Si tocas esta vista, no borres ninguno de esos elementos: son motivo de rechazo.
struct PaywallView: View {

    /// Por qué se está enseñando. Cambia el titular para que hable de lo que
    /// el usuario acaba de intentar hacer, que es lo que hace que convierta.
    let reason: PaywallReason

    @Environment(SubscriptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String = StoreConfiguration.recurringSubscriptionsEnabled
        ? ProductID.yearly
        : ProductID.lifetime
    @State private var eligibleIntroProductID: String?

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedID }
    }

    private var eligibleIntroOffer: Product.SubscriptionOffer? {
        guard eligibleIntroProductID == selectedProduct?.id else { return nil }
        return selectedProduct?.subscription?.introductoryOffer
    }

    private var yearlyOffersSavings: Bool {
        guard let yearly = store.products.first(where: { $0.id == ProductID.yearly }),
              let monthly = store.products.first(where: { $0.id == ProductID.monthly }),
              let yearlyMonths = monthCount(for: yearly),
              let monthlyMonths = monthCount(for: monthly) else { return false }

        return yearly.price / Decimal(yearlyMonths)
            < monthly.price / Decimal(monthlyMonths)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    plans
                    features
                    buyButton
                    legalFootnote      // 3.1.2 · renovación automática y precio
                    legalLinks         // 3.1.2 · condiciones y privacidad
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Theme.groupedBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 3.1.2 · el muro SIEMPRE se puede cerrar. La app sigue siendo usable gratis.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Cerrar")
                    .buttonStyle(.plain)
                }

                // 3.1.2 · restaurar compras, obligatorio y visible sin hacer scroll.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restaurar") {
                        Task { await store.restore() }
                    }
                    .font(.subheadline)
                    .disabled(store.isWorking)
                }
            }
            .task {
                if store.isPremium {
                    dismiss()
                    return
                }
                await prepareProducts()
            }
            .onChange(of: selectedID) { _, _ in
                Task { await refreshIntroOffer() }
            }
            // Si la compra sale bien, el muro se cierra solo.
            .onChange(of: store.isPremium) { _, isPremium in
                if isPremium {
                    dismiss()
                }
            }
            // Binding calculado, no `.constant`: con `.constant` el sistema no puede
            // cerrar la alerta (tocar fuera, VoiceOver) y esta se vuelve a presentar en bucle.
            .alert("No se ha podido completar", isPresented: Binding(
                get: { store.lastError != nil },
                set: { visible in if !visible { store.clearError() } }
            )) {
                Button("De acuerdo", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }

    // MARK: - Cabecera

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(Theme.premium, lineWidth: 2)
                Text("PREMIUM")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.premium)
            }
            .frame(width: 78, height: 78)
            .padding(.top, 8)

            Text(reason.headline)
                .font(.title2.weight(.heavy))
                .multilineTextAlignment(.center)

            Text(reason.detail)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Planes

    private var plans: some View {
        VStack(spacing: 10) {
            if store.products.isEmpty {
                if store.isWorking {
                    ProgressView("Cargando planes…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    VStack(spacing: 8) {
                        Text("No hay planes disponibles")
                            .font(.subheadline.weight(.semibold))
                        Button("Intentar de nuevo") {
                            Task { await prepareProducts() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                }
            } else {
                ForEach(store.products, id: \.id) { product in
                    Button {
                        selectedID = product.id
                    } label: {
                        PlanRow(product: product,
                                isSelected: product.id == selectedID,
                                monthlyEquivalent: store.monthlyEquivalent(for: product),
                                isBestValue: product.id == ProductID.yearly && yearlyOffersSavings)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Selecciona este plan")
                }
            }
        }
    }

    // MARK: - Lo que incluye

    private var features: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Self.benefits, id: \.self) { benefit in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                    Text(benefit).font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Solo capacidades que ya existen en la aplicación.
    static let benefits = [
        "Números ilimitados en tu colección",
        "Importaciones de CBZ y PDF ilimitadas",
        "Series seguidas sin límites"
    ]

    // MARK: - Botón de compra

    private var buyButton: some View {
        Button {
            Task {
                guard let product = selectedProduct else { return }
                await store.purchase(product)
            }
        } label: {
            Group {
                if store.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(purchaseButtonTitle)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .foregroundStyle(Color(.systemBackground))
        .panelGlass(cornerRadius: 12,
                    tint: Color.primary,
                    isInteractive: true,
                    fallbackFill: Color.primary,
                    strokeColor: .clear)
        .disabled(store.isWorking || selectedProduct == nil)
    }

    // MARK: - Letra pequeña obligatoria

    /// 3.1.2 · Duración, precio y renovación automática, con el precio leído de StoreKit.
    /// Escribir "19,99 €" a mano aquí es rechazo directo en cuanto la app se venda en otro país.
    private var legalFootnote: some View {
        Group {
            if let product = selectedProduct {
                if product.subscription != nil {
                    Text(renewalText(for: product))
                } else {
                    Text("Pago único de \(product.displayPrice). Sin renovación.")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(Theme.secondaryText)
        .multilineTextAlignment(.center)
    }

    private func renewalText(for product: Product) -> String {
        let period = periodDescription(product)
        let base = "\(product.displayPrice) \(period). Se renueva automáticamente salvo que la canceles al menos 24 horas antes del final del periodo. Puedes gestionarla o cancelarla en los ajustes de tu cuenta."

        guard let offer = eligibleIntroOffer else { return base }

        if offer.paymentMode == .freeTrial {
            return "\(offerDuration(offer)) gratis y después \(base)"
        }

        if offer.paymentMode == .payUpFront {
            return "Oferta inicial de \(offer.displayPrice) por \(offerDuration(offer)). Después, \(base)"
        }

        let periods = offer.periodCount == 1 ? "1 periodo" : "\(offer.periodCount) periodos"
        return "Oferta inicial de \(offer.displayPrice) \(periodDescription(offer.period)) durante \(periods). Después, \(base)"
    }

    private func periodDescription(_ product: Product) -> String {
        guard let unit = product.subscription?.subscriptionPeriod else { return "" }
        switch unit.unit {
        case .year:  return unit.value == 1 ? "al año" : "cada \(unit.value) años"
        case .month: return unit.value == 1 ? "al mes" : "cada \(unit.value) meses"
        case .week:  return unit.value == 1 ? "a la semana" : "cada \(unit.value) semanas"
        case .day:   return unit.value == 1 ? "al día" : "cada \(unit.value) días"
        @unknown default: return ""
        }
    }

    private func periodDescription(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .year:  return period.value == 1 ? "al año" : "cada \(period.value) años"
        case .month: return period.value == 1 ? "al mes" : "cada \(period.value) meses"
        case .week:  return period.value == 1 ? "a la semana" : "cada \(period.value) semanas"
        case .day:   return period.value == 1 ? "al día" : "cada \(period.value) días"
        @unknown default: return ""
        }
    }

    private func offerDuration(_ offer: Product.SubscriptionOffer) -> String {
        let value = offer.period.value * max(offer.periodCount, 1)
        switch offer.period.unit {
        case .year:  return value == 1 ? "1 año" : "\(value) años"
        case .month: return value == 1 ? "1 mes" : "\(value) meses"
        case .week:  return value == 1 ? "1 semana" : "\(value) semanas"
        case .day:   return value == 1 ? "1 día" : "\(value) días"
        @unknown default: return "el periodo promocional"
        }
    }

    private func monthCount(for product: Product) -> Int? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        switch period.unit {
        case .year:  return period.value * 12
        case .month: return period.value
        case .week, .day: return nil
        @unknown default: return nil
        }
    }

    private var purchaseButtonTitle: String {
        guard let product = selectedProduct else { return "Continuar" }

        if let offer = eligibleIntroOffer, offer.paymentMode == .freeTrial {
            return "Probar gratis durante \(offerDuration(offer))"
        }

        return product.subscription == nil
            ? "Comprar por \(product.displayPrice)"
            : "Suscribirse por \(product.displayPrice)"
    }

    private func prepareProducts() async {
        if store.products.isEmpty {
            await store.loadProducts()
        }

        if selectedProduct == nil, let first = store.products.first {
            selectedID = first.id
        }

        await refreshIntroOffer()
    }

    private func refreshIntroOffer() async {
        guard let product = selectedProduct else {
            eligibleIntroProductID = nil
            return
        }

        let productID = product.id
        eligibleIntroProductID = nil
        let isEligible = await store.hasIntroOffer(product)

        // La consulta es asíncrona: no apliques el resultado a otro plan si el
        // usuario cambió la selección mientras StoreKit respondía.
        guard selectedID == productID else { return }
        eligibleIntroProductID = isEligible ? productID : nil
    }

    /// 3.1.2 · Los dos enlaces legales, dentro de la app.
    private var legalLinks: some View {
        HStack(spacing: 18) {
            Link("Condiciones de uso", destination: LegalLinks.terms)
            Link("Privacidad", destination: LegalLinks.privacy)
        }
        .font(.caption2)
        .foregroundStyle(Theme.secondaryText)
    }
}

// MARK: - Fila de plan

private struct PlanRow: View {
    let product: Product
    let isSelected: Bool
    let monthlyEquivalent: String?
    let isBestValue: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName.isEmpty ? fallbackName : product.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                // Siempre `displayPrice`: viene localizado desde la App Store.
                Text(monthlyEquivalent ?? product.displayPrice)
                    .font(.headline)
                if monthlyEquivalent != nil {
                    Text("/mes").font(.caption2).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(14)
        .panelGlass(cornerRadius: 12,
                    tint: isSelected ? Theme.premium : nil,
                    isInteractive: true,
                    fallbackFill: isSelected ? Theme.premiumSoft : Color(.secondarySystemGroupedBackground),
                    strokeColor: isSelected ? Theme.premium : Theme.hairline,
                    strokeWidth: isSelected ? 2 : 1)
        .overlay(alignment: .topLeading) {
            if isBestValue {
                Text("MEJOR PRECIO")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.premium, in: Capsule())
                    .foregroundStyle(.white)
                    .offset(x: 12, y: -8)
            }
        }
        .padding(.top, isBestValue ? 8 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Seleccionado" : "No seleccionado")
    }

    private var fallbackName: String {
        switch product.id {
        case ProductID.yearly:   return "Anual"
        case ProductID.monthly:  return "Mensual"
        case ProductID.lifetime: return "Para siempre"
        default:                 return product.id
        }
    }

    private var subtitle: String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return "Pago único · \(product.displayPrice)"
        }

        switch period.unit {
        case .year:
            return period.value == 1
                ? "\(product.displayPrice) al año"
                : "\(product.displayPrice) cada \(period.value) años"
        case .month:
            return period.value == 1
                ? "\(product.displayPrice) al mes"
                : "\(product.displayPrice) cada \(period.value) meses"
        case .week:
            return period.value == 1
                ? "\(product.displayPrice) a la semana"
                : "\(product.displayPrice) cada \(period.value) semanas"
        case .day:
            return period.value == 1
                ? "\(product.displayPrice) al día"
                : "\(product.displayPrice) cada \(period.value) días"
        @unknown default:
            return product.displayPrice
        }
    }
}

// MARK: - Presentación cómoda

extension View {
    /// Presenta el muro de pago cuando `reason` deja de ser nil.
    ///
    /// Uso:
    /// ```
    /// @State private var paywall: PaywallReason?
    /// ...
    /// .paywall($paywall)
    /// ```
    func paywall(_ reason: Binding<PaywallReason?>) -> some View {
        sheet(isPresented: Binding(
            get: { reason.wrappedValue != nil },
            set: { if !$0 { reason.wrappedValue = nil } }
        )) {
            if let unwrappedReason = reason.wrappedValue {
                PaywallView(reason: unwrappedReason)
            }
        }
    }
}

#Preview {
    PaywallView(reason: .collectionFull)
        .environment(SubscriptionStore())
}
