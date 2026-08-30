import Foundation
import SwiftData
import Testing
@testable import PanelMax

@Suite("Números de cómic")
@MainActor
struct ComicNumberTests {

    @Test("Ordena enteros por valor y deja especiales al final")
    func naturalOrder() {
        let values = ["10", "Anual 2024", "2", "1/2", "1", "0"]
        let sorted = ComicNumber.sorted(values) { $0 }

        #expect(sorted == ["0", "1", "2", "10", "1/2", "Anual 2024"])
    }

    @Test("Ordena los especiales de forma natural")
    func specialOrder() {
        let values = ["Anual 10", "Anual 2", "Anual 1"]
        #expect(ComicNumber.sorted(values) { $0 } == ["Anual 1", "Anual 2", "Anual 10"])
    }
}

@Suite("Progreso de lectura")
@MainActor
struct ReadingProgressTests {

    @Test("Evita divisiones por cero")
    func zeroPages() {
        let progress = ReadingProgress(currentPage: 0, totalPages: 0)
        #expect(progress.fraction == 0)
        #expect(progress.displayPosition == "Pág. 1 / 1")
    }

    @Test("Limita la fracción a uno")
    func clampsFraction() {
        let progress = ReadingProgress(currentPage: 99, totalPages: 10)
        #expect(progress.fraction == 1)
    }
}

@Suite("Colección")
@MainActor
struct CollectionStoreTests {

    @Test("Crear una serie no duplica al crear otra con el mismo título")
    func createSeriesAssignsUniqueCatalogID() throws {
        let container = try makeContainer()
        let store = CollectionStore(context: ModelContext(container))

        let first = try store.createSeries(title: "Serie", publisher: "Editorial", totalIssues: 12)
        let second = try store.createSeries(title: "Serie", publisher: "Editorial", totalIssues: 12)

        #expect(first.catalogID != second.catalogID)
        let saved = try store.context.fetch(FetchDescriptor<Series>())
        #expect(saved.count == 2)
    }

    @Test("Añadir el mismo número suelto dos veces no lo duplica")
    func addIssueIsIdempotent() throws {
        let container = try makeContainer()
        let store = CollectionStore(context: ModelContext(container))
        let series = try store.createSeries(title: "Serie")

        _ = try store.addIssue(number: "1", to: series, state: .owned)
        _ = try store.addIssue(number: "1", to: series, state: .read)

        #expect(series.issues?.count == 1)
        #expect(series.issues?.first?.entry?.state == .read)
    }

    @Test("Un rango añade todos los números y respeta lo que ya existía")
    func addIssueRangeSkipsExisting() throws {
        let container = try makeContainer()
        let store = CollectionStore(context: ModelContext(container))
        let series = try store.createSeries(title: "Serie")

        _ = try store.addIssue(number: "3", to: series, state: .wanted)
        _ = try store.addIssueRange(from: 1, through: 5, to: series, state: .owned)

        #expect(series.issues?.count == 5)
        let three = series.issues?.first { $0.number == "3" }
        // Ya existía como «lo quiero»: el rango no debe pisar su estado.
        #expect(three?.entry?.state == .wanted)
        let one = series.issues?.first { $0.number == "1" }
        #expect(one?.entry?.state == .owned)
    }

    @Test("Un rango invertido no añade nada")
    func addIssueRangeRejectsInverted() throws {
        let container = try makeContainer()
        let store = CollectionStore(context: ModelContext(container))
        let series = try store.createSeries(title: "Serie")

        let created = try store.addIssueRange(from: 5, through: 1, to: series)

        #expect(created.isEmpty)
        #expect(series.issues?.isEmpty != false)
    }

    @Test("Eliminar una serie no elimina el archivo importado vinculado")
    func deletingSeriesPreservesLinkedFile() throws {
        let container = try makeContainer()
        let store = CollectionStore(context: ModelContext(container))
        let series = try store.createSeries(title: "Serie")
        let issue = try store.addIssue(number: "1", to: series)

        let file = LocalComicFile(displayName: "Cómic", localFilename: "a.cbz")
        store.context.insert(file)
        try store.link(file, to: issue)

        try store.deleteSeries(series)

        let remainingFiles = try store.context.fetch(FetchDescriptor<LocalComicFile>())
        #expect(remainingFiles.count == 1)
        #expect(remainingFiles.first?.issue == nil)
    }

    @Test("El progreso se limita al rango real")
    func progressIsClamped() throws {
        let container = try makeContainer()
        let store = CollectionStore(context: ModelContext(container))
        let issue = Issue(catalogID: "issue-1", number: "1")
        store.context.insert(issue)

        try store.saveProgress(for: issue, page: 50, totalPages: 12)

        #expect(issue.progress?.currentPage == 11)
        #expect(issue.progress?.isFinished == true)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema.panelMax
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
