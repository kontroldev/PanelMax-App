import Foundation
import SwiftData
import Testing
@testable import PanelMax

/// El esquema de la base de datos, que es lo único que no se puede arreglar
/// con una actualización si sale mal: un fallo aquí deja al usuario sin su
/// colección.
@Suite("Esquema de la base de datos")
@MainActor
struct SchemaTests {

    @Test("Los nombres de las tablas no cambian al anidar los modelos en el esquema")
    func entityNamesAreStable() {
        // SwiftData identifica cada tabla por el nombre de la clase. Los
        // modelos viven ahora dentro de `PanelMaxSchemaV1`; si eso cambiara
        // los nombres, las colecciones guardadas por versiones anteriores
        // dejarían de abrirse.
        let names = Set(Schema.panelMax.entities.map(\.name))

        #expect(names == ["Series", "Issue", "CollectionEntry", "ReadingProgress", "LocalComicFile"])
    }

    @Test("La versión activa es la 1.0.0 y es la última del plan de migración")
    func activeVersionIsTheLatest() {
        #expect(Schema.panelMax.version == Schema.Version(1, 0, 0))
        #expect(PanelMaxMigrationPlan.schemas.last == PanelMaxSchemaV1.self)
    }

    @Test("Un almacén guardado en disco se vuelve a abrir con el plan de migración")
    func storeReopensWithMigrationPlan() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Coleccion.store", directoryHint: .notDirectory)

        // Mismo montaje que `PanelMaxApp`: esquema, plan de migración y disco.
        func openContainer() throws -> ModelContainer {
            let configuration = ModelConfiguration(schema: .panelMax, url: storeURL)
            return try ModelContainer(for: .panelMax,
                                      migrationPlan: PanelMaxMigrationPlan.self,
                                      configurations: [configuration])
        }

        do {
            let context = ModelContext(try openContainer())
            context.insert(Series(catalogID: "s1", title: "Cuervo Negro"))
            try context.save()
        }

        let reopened = ModelContext(try openContainer())
        let titles = try reopened.fetch(FetchDescriptor<Series>()).map(\.title)

        #expect(titles == ["Cuervo Negro"])
    }
}
