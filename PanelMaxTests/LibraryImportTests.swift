import Foundation
import SwiftData
import Testing
@testable import PanelMax

/// `LibraryStore.importFiles` es la puerta de entrada de todo cómic.
///
/// A diferencia de `CBZArchiveTests`, esta suite SÍ escribe en
/// `Documents/Comics` y `Documents/Covers` del proceso de tests, porque es
/// justo lo que se quiere comprobar. Cada test borra lo que ha importado.
/// `.serialized` porque varios tests comparan el contenido de `Comics/`
/// antes y después: dos importaciones en paralelo se pisarían la cuenta.
@Suite("Importación de cómics", .serialized)
@MainActor
struct LibraryImportTests {

    // MARK: - Utilidades

    /// Borra las copias internas y miniaturas de lo importado en un test.
    private func removeImportedCopies(in context: ModelContext) {
        let files = (try? context.fetch(FetchDescriptor<LocalComicFile>())) ?? []
        for file in files {
            if let url = try? file.localCopyURL() {
                try? FileManager.default.removeItem(at: url)
            }
            ThumbnailStore.delete(file.thumbnailFilename)
        }
    }

    private func importedFiles(in context: ModelContext) throws -> [LocalComicFile] {
        try context.fetch(FetchDescriptor<LocalComicFile>())
    }

    // MARK: - Casos felices

    @Test("Un CBZ válido se copia, se registra y recibe miniatura")
    func importsValidCBZ() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        let url = try ComicFixtures.makeValidCBZ(named: "Cuervo Negro 01.cbz", in: source, pageCount: 3)
        let skipped = try await LibraryStore(context: context).importFiles(from: [url])

        #expect(skipped.isEmpty)
        let file = try #require(try importedFiles(in: context).first)
        #expect(file.displayName == "Cuervo Negro 01")
        #expect(file.pageCount == 3)
        #expect(file.fileSize > 0)

        // La copia vive dentro de `Comics/` y es independiente del original.
        let copy = try #require(try file.localCopyURL())
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(copy != url)

        // La miniatura sale de la página 1 y existe en disco.
        let thumbnail = try #require(file.thumbnailURL)
        #expect(FileManager.default.fileExists(atPath: thumbnail.path))
    }

    @Test("Borrar el original después de importar no rompe el cómic")
    func importedCopySurvivesOriginalDeletion() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer { removeImportedCopies(in: context) }

        let url = try ComicFixtures.makeValidCBZ(in: source)
        try await LibraryStore(context: context).importFiles(from: [url])

        // Simula que el usuario borra el archivo de iCloud Drive.
        try FileManager.default.removeItem(at: source)

        let file = try #require(try importedFiles(in: context).first)
        #expect(file.isAvailable)
        #expect(try ComicArchiveFactory.open(file).pageCount == 3)
    }

    // MARK: - Lotes mixtos

    @Test("Un archivo no compatible se omite sin abortar el resto del lote")
    func mixedBatchImportsValidAndSkipsTheRest() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        let valid = try ComicFixtures.makeValidCBZ(named: "bueno.cbz", in: source)
        let text = source.appending(path: "notas.txt")
        try Data("no es un cómic".utf8).write(to: text)
        let corrupt = source.appending(path: "roto.cbz")
        try Data("tampoco es un zip".utf8).write(to: corrupt)

        let before = ComicFixtures.comicsDirectoryContents()
        let skipped = try await LibraryStore(context: context).importFiles(from: [valid, text, corrupt])

        #expect(Set(skipped.map(\.name)) == ["notas.txt", "roto.cbz"])
        let files = try importedFiles(in: context)
        #expect(files.map(\.displayName) == ["bueno"])

        // Solo debe haber aparecido UNA copia nueva: la del CBZ válido. El
        // corrupto se copió para validarlo, pero no puede quedarse dentro.
        let added = ComicFixtures.comicsDirectoryContents().subtracting(before)
        let copied = try #require(files.first?.localFilename)
        #expect(added == [copied])
    }

    @Test("Si ningún archivo vale, se avisa y no queda nada copiado")
    func batchWithNothingValidThrows() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: source) }

        let corrupt = source.appending(path: "roto.cbz")
        try Data("no es un zip".utf8).write(to: corrupt)
        let empty = try ComicFixtures.makeCBZ(at: source.appending(path: "vacio.cbz"), entries: [
            (path: "LEEME.txt", data: Data("sin páginas".utf8))
        ])

        let before = ComicFixtures.comicsDirectoryContents()
        await #expect {
            try await LibraryStore(context: context).importFiles(from: [corrupt, empty])
        } throws: { error in
            guard case ComicImportError.noneImported(let skipped) = error else { return false }
            return skipped.count == 2
        }

        #expect(try importedFiles(in: context).isEmpty)
        #expect(ComicFixtures.comicsDirectoryContents() == before)
    }

    // MARK: - Duplicados

    @Test("Reimportar el mismo archivo no lo duplica ni deja una copia huérfana")
    func reimportIsRejectedAsDuplicate() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        let url = try ComicFixtures.makeValidCBZ(in: source)
        let store = LibraryStore(context: context)
        try await store.importFiles(from: [url])

        let before = ComicFixtures.comicsDirectoryContents()
        await #expect {
            try await store.importFiles(from: [url])
        } throws: { error in
            guard case ComicImportError.noneImported(let skipped) = error else { return false }
            return skipped.count == 1
        }

        #expect(try importedFiles(in: context).count == 1)
        // `ComicImportBatch.copy` ya había copiado el duplicado a `Comics/`:
        // `importFiles` tiene que haberlo borrado al descartarlo.
        #expect(ComicFixtures.comicsDirectoryContents() == before)
    }

    @Test("Elegir el mismo archivo dos veces en un lote lo importa una sola vez")
    func duplicateWithinBatchIsImportedOnce() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        let url = try ComicFixtures.makeValidCBZ(in: source)
        let before = ComicFixtures.comicsDirectoryContents()
        let skipped = try await LibraryStore(context: context).importFiles(from: [url, url])

        #expect(skipped.count == 1)
        let files = try importedFiles(in: context)
        #expect(files.count == 1)
        let copied = try #require(files.first?.localFilename)
        #expect(ComicFixtures.comicsDirectoryContents().subtracting(before) == [copied])
    }

    @Test("La detección de duplicados ignora mayúsculas y espacios del nombre")
    func duplicateDetectionNormalizesName() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let first = try ComicFixtures.makeTemporaryDirectory()
        let second = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        // Mismo contenido (mismo tamaño), nombre con otra capitalización.
        let original = try ComicFixtures.makeValidCBZ(named: "comic.cbz", in: first)
        let renamed = second.appending(path: "COMIC.cbz")
        try FileManager.default.copyItem(at: original, to: renamed)

        let store = LibraryStore(context: context)
        try await store.importFiles(from: [original])
        await #expect(throws: ComicImportError.self) {
            try await store.importFiles(from: [renamed])
        }
        #expect(try importedFiles(in: context).count == 1)
    }
}
