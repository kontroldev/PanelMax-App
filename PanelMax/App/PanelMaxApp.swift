import SwiftUI
import SwiftData

/// Punto de entrada de la app.
///
/// La 1.0 es una app 100% local: sin catálogo remoto, sin cuenta y sin
/// compras. Lo único que se monta al arrancar es el contenedor de SwiftData
/// (la colección del usuario) y, la primera vez, el cómic de ejemplo.
@main
struct PanelMaxApp: App {

    /// Contenedor de SwiftData. Se crea una sola vez y se comparte con todas las vistas.
    /// OJO con CloudKit: si activas la sincronización, los modelos NO pueden tener
    /// `@Attribute(.unique)` ni propiedades sin valor por defecto.
    let modelContainer: ModelContainer

    /// Si el almacén persistente no puede abrirse conservamos sus archivos intactos,
    /// arrancamos en modo temporal y explicamos el problema al usuario.
    private let persistenceWarning: String?

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
                .task {
                    // La carpeta de cómics se prepara y se excluye de la copia de
                    // seguridad ANTES de que exista ningún archivo dentro: excluir
                    // después no retira del respaldo lo ya copiado.
                    _ = try? LocalComicFile.prepareComicsDirectory()

                    SampleLibrarySeeder.seedIfNeeded(context: modelContainer.mainContext)
                }
        }
        .modelContainer(modelContainer)
    }
}
