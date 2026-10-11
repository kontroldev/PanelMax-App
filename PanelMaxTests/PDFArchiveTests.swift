import Foundation
import Testing
import UIKit
@testable import PanelMax

/// `PDFArchive` es la otra mitad del lector, junto a `CBZArchive`. Los PDF se
/// generan en cada test (ver `ComicFixtures.makePDF`) en una carpeta temporal.
@Suite("Lectura de PDF")
struct PDFArchiveTests {

    @Test("Cuenta las páginas del PDF")
    func countsPages() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try ComicFixtures.makePDF(at: directory.appending(path: "comic.pdf"), pageCount: 4)

        #expect(try ComicArchiveFactory.pageCount(at: url) == 4)
    }

    @Test("Renderiza una página respetando su proporción")
    func rendersPageWithItsAspectRatio() async throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Páginas de 200 × 300 puntos: proporción 2:3.
        let url = try ComicFixtures.makePDF(at: directory.appending(path: "comic.pdf"),
                                            pageCount: 2,
                                            pageSize: CGSize(width: 200, height: 300))
        let archive = try ComicArchiveFactory.open(url: url, pdfTargetWidth: 1_290)

        let page = try #require(await archive.page(at: 0))
        let ratio = page.size.width / page.size.height

        #expect(abs(ratio - 2.0 / 3.0) < 0.01)
    }

    @Test("Pedir una página fuera de rango devuelve nil en vez de romper")
    func outOfRangePageIsNil() async throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try ComicFixtures.makePDF(at: directory.appending(path: "comic.pdf"), pageCount: 2)
        let archive = try ComicArchiveFactory.open(url: url)

        #expect(await archive.page(at: -1) == nil)
        #expect(await archive.page(at: 2) == nil)
    }

    @Test("Un archivo con extensión .pdf que no es un PDF se rechaza")
    func corruptPDFThrows() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "roto.pdf")
        try Data("esto no es un pdf".utf8).write(to: url)

        #expect {
            try ComicArchiveFactory.pageCount(at: url)
        } throws: { error in
            guard case ComicArchiveError.unsupportedFormat = error else { return false }
            return true
        }
    }
}
