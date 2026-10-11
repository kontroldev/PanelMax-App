import Foundation
import SwiftData
import Testing
@testable import PanelMax

/// Importar EPUB a la biblioteca.
///
/// Extensión de `LibraryImportTests`, como `LibraryDeletionTests`, para
/// heredar su `.serialized`: estos tests también copian archivos a `Comics/`.
extension LibraryImportTests {

    @Test("Un EPUB de cómic se importa con sus páginas y su miniatura")
    func importsComicEPUB() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        let url = try ComicFixtures.makeComicEPUB(named: "Cuervo Negro 02.epub", in: source, pageCount: 3)
        let skipped = try await LibraryStore(context: context).importFiles(from: [url])

        #expect(skipped.isEmpty)
        let file = try #require(try importedFiles(in: context).first)
        #expect(file.displayName == "Cuervo Negro 02")
        #expect(file.pageCount == 3)
        #expect(file.localFilename?.hasSuffix(".epub") == true)
        // La portada sale de la primera página del orden de lectura.
        let thumbnail = try #require(file.thumbnailURL)
        #expect(FileManager.default.fileExists(atPath: thumbnail.path))
    }

    @Test("Un EPUB de texto se omite explicando por qué, sin abortar el resto del lote")
    func textEPUBIsSkippedWithReason() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        let comic = try ComicFixtures.makeComicEPUB(named: "comic.epub", in: source)
        let novel = try ComicFixtures.makeTextEPUB(named: "novela.epub", in: source)

        let before = ComicFixtures.comicsDirectoryContents()
        let skipped = try await LibraryStore(context: context).importFiles(from: [comic, novel])

        let reason = try #require(skipped.first { $0.name == "novela.epub" }?.reason)
        #expect(reason.contains("EPUB de texto"))
        #expect(try importedFiles(in: context).map(\.displayName) == ["comic"])
        // La copia de la novela, hecha para validarla, no puede quedarse.
        let copied = try #require(try importedFiles(in: context).first?.localFilename)
        #expect(ComicFixtures.comicsDirectoryContents().subtracting(before) == [copied])
    }
}
