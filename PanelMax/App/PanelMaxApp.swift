import SwiftUI
import SwiftData

/// Punto de entrada de la app.
///
/// La 1.0 es una app 100% local: sin catálogo remoto, sin cuenta y sin
/// compras. Lo único que se monta al arrancar es el contenedor de SwiftData
/// (la colección del usuario).
@main
struct PanelMaxApp: App {

    /// Contenedor de SwiftData. Se crea una sola vez y se comparte con todas las vistas.
    /// OJO con CloudKit: si activas la sincronización, los modelos NO pueden tener
    /// `@Attribute(.unique)` ni propiedades sin valor por defecto.
    let modelContainer: ModelContainer

    /// Si el almacén persistente no puede abrirse conservamos sus archivos intactos,
    /// arrancamos en modo temporal y explicamos el problema al usuario.
    private let persistenceWarning: String?

    /// Claves que activan comportamiento especial para los tests de UI
    /// (`PanelMaxUITests`), pasadas como `launchArguments` desde `XCUIApplication`.
    /// Nunca se activan en una build normal: solo existen para que los tests
    /// arranquen en un estado conocido sin depender de lo que quedara de una
    /// ejecución anterior.
    private enum UITestLaunchArgument {
        /// Almacén de SwiftData en memoria: cada test arranca con la
        /// colección vacía y no toca ni contamina los datos reales del
        /// simulador.
        static let inMemoryStore = "-uiTestsInMemoryStore"
        /// Da por vista la introducción antes de que `RootView` la consulte,
        /// para los tests que no van sobre el propio onboarding.
        static let skipOnboarding = "-uiTestsSkipOnboarding"
        /// Fuerza a que la introducción se muestre, aunque el simulador ya
        /// la tuviera marcada como vista de una ejecución anterior: sin esto,
        /// el test del propio onboarding depende de qué quedara en
        /// `UserDefaults` de la vez anterior que se instaló la app.
        static let showOnboarding = "-uiTestsShowOnboarding"
    }

    init() {
        var warning: String?
        // Un único sitio para los modelos: `Schema.panelMax` (ver PanelMaxSchema.swift).
        let schema = Schema.panelMax
        let arguments = ProcessInfo.processInfo.arguments

        // Mismo valor y misma clave que `RootView.onboardingSeenKey`.
        if arguments.contains(UITestLaunchArgument.skipOnboarding) {
            UserDefaults.standard.set(true, forKey: "panelmax.onboardingSeen")
        } else if arguments.contains(UITestLaunchArgument.showOnboarding) {
            UserDefaults.standard.set(false, forKey: "panelmax.onboardingSeen")
        }

        do {
            // `cloudKitDatabase: .none` de momento.
            // Cuando actives el capability de CloudKit, cámbialo por `.automatic`
            // (ver README, apartado "Sincronización").
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: arguments.contains(UITestLaunchArgument.inMemoryStore),
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
                .task {
                    // La carpeta de cómics se prepara y se excluye de la copia de
                    // seguridad ANTES de que exista ningún archivo dentro: excluir
                    // después no retira del respaldo lo ya copiado.
                    _ = try? LocalComicFile.prepareComicsDirectory()
                }
        }
        .modelContainer(modelContainer)
    }
}
