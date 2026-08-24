import SwiftUI
import SwiftData

/// Punto de entrada de la app.
///
/// Aquí se montan las tres piezas que viven durante toda la sesión:
/// 1. El contenedor de SwiftData (la colección del usuario).
/// 2. El `SubscriptionStore` (StoreKit 2), que sabe si hay premium activo.
/// 3. La fuente de catálogo, inyectada por protocolo para poder cambiarla sin tocar las vistas.
@main
struct PanelMaxApp: App {

    /// Contenedor de SwiftData. Se crea una sola vez y se comparte con todas las vistas.
    /// OJO con CloudKit: si activas la sincronización, los modelos NO pueden tener
    /// `@Attribute(.unique)` ni propiedades sin valor por defecto.
    let modelContainer: ModelContainer

    /// Si el almacén persistente no puede abrirse conservamos sus archivos intactos,
    /// arrancamos en modo temporal y explicamos el problema al usuario.
    private let persistenceWarning: String?

    /// Estado de la suscripción. `@State` porque `SubscriptionStore` es `@Observable`.
    @State private var subscriptions = SubscriptionStore()

    /// Fuente de datos del catálogo. En Debug usa datos ficticios salvo que el
    /// Scheme solicite el catálogo real; en Release exige un backend configurado.
    @State private var catalog: any CatalogSource = CatalogSourceFactory.make()

    init() {
        var warning: String?
        // Un único sitio para los modelos: `Schema.panelMax` (ver PanelMaxSchema.swift).
        let schema = Schema.panelMax

        do {
            // `cloudKitDatabase: .none` de momento.
            // Cuando actives el capability de CloudKit, cámbialo por `.automatic`
            // (ver README, apartado "Sincronización").
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )

            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: PanelMaxMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            warning = error.localizedDescription

            // No borramos ni sobrescribimos la colección real. Un contenedor temporal
            // permite abrir la app, consultar ayuda y volver a intentarlo tras actualizar.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("No se pudo crear ni siquiera el contenedor temporal: \(error)")
            }
        }
        persistenceWarning = warning
    }

    var body: some Scene {
        WindowGroup {
            RootView(persistenceWarning: persistenceWarning)
                .environment(subscriptions)       // disponible en toda la jerarquía
                .environment(\.catalog, catalog)  // fuente de catálogo vía EnvironmentValues
                .task {
                    // La carpeta de cómics se prepara y se excluye de la copia de
                    // seguridad ANTES de que exista ningún archivo dentro: excluir
                    // después no retira del respaldo lo ya copiado.
                    try? LocalComicFile.prepareComicsDirectory()

                    // Apple exige atender transacciones pendientes nada más abrir la app.
                    await subscriptions.start()
                }
        }
        .modelContainer(modelContainer)
    }
}
