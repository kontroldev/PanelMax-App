import Foundation
import SwiftData
import Testing
@testable import PanelMax

/// «Exportar colección» es la única forma de sacar del dispositivo lo que el
/// usuario ha catalogado a mano. Si el JSON sale mal, se pierde sin avisar.
@Suite("Exportar colección")
@MainActor
struct CollectionExporterTests {

    /// Mismo formato de fecha que usa `CollectionExporter`.
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test("Exporta solo los números de la colección, en orden natural")
    func exportsCollectedIssuesInNaturalOrder() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["10", "Anual 2024", "2"], totalIssues: 12)

        // Un número sin ficha de colección (un hueco) no debe exportarse.
        let gap = Issue(catalogID: "s1-3", number: "3")
        gap.series = series
        context.insert(gap)

        let export = try decoder.decode(CollectionExporter.Export.self,
                                        from: try CollectionExporter.makeJSON(series: [series]))
        let exported = try #require(export.series.first)

        #expect(exported.title == "Serie")
        #expect(exported.totalIssues == 12)
        #expect(exported.issues.map(\.number) == ["2", "10", "Anual 2024"])
        #expect(exported.issues.allSatisfy { $0.state == CollectionState.owned.label })
    }

    @Test("Marca qué números tienen un cómic importado vinculado")
    func marksIssuesWithImportedFile() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "2"])
        let first = try #require(series.issues?.first { $0.number == "1" })

        let file = LocalComicFile(displayName: "Cómic", localFilename: "a.cbz")
        file.issue = first
        context.insert(file)

        let export = try decoder.decode(CollectionExporter.Export.self,
                                        from: try CollectionExporter.makeJSON(series: [series]))
        let issues = try #require(export.series.first?.issues)

        #expect(issues.first { $0.number == "1" }?.hasImportedFile == true)
        #expect(issues.first { $0.number == "2" }?.hasImportedFile == false)
    }

    @Test("Una colección vacía produce un JSON válido sin series")
    func emptyCollectionIsValidJSON() throws {
        let export = try decoder.decode(CollectionExporter.Export.self,
                                        from: try CollectionExporter.makeJSON(series: []))

        #expect(export.series.isEmpty)
    }

    @Test("El archivo exportado lleva el nombre de la app y se puede leer de vuelta")
    func exportFileIsReadable() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1"])

        let url = try CollectionExporter.makeExportFile(series: [series])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.lastPathComponent.hasPrefix(AppInfo.displayName))
        #expect(url.pathExtension == "json")
        let export = try decoder.decode(CollectionExporter.Export.self, from: try Data(contentsOf: url))
        #expect(export.series.count == 1)
    }
}
