import Foundation
import Testing
import UIKit
@testable import PanelMax

/// Lectura de EPUB reales, comprimidos en ZIP. Se generan en cada test (ver
/// `ComicFixtures.makeComicEPUB`) dentro de una carpeta temporal propia.
@Suite("Lectura de EPUB")
struct EPUBArchiveTests {

    @Test("Cuenta una página por cada imagen del orden de lectura")
    func countsPages() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try ComicFixtures.makeComicEPUB(in: directory, pageCount: 4)

        #expect(try ComicArchiveFactory.pageCount(at: url) == 4)
    }

    @Test("Devuelve cada página en el orden del spine")
    func pagesFollowReadingOrder() async throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // El manifest del fixture va al revés: el orden correcto solo puede
        // salir del spine.
        let url = try ComicFixtures.makeComicEPUB(in: directory, pageCount: 3)
        let archive = try ComicArchiveFactory.open(url: url)

        for index in 0..<3 {
            let page = try #require(await archive.page(at: index))
            #expect(Int(page.size.width * page.scale) == ComicFixtures.pageWidth(index),
                    "La posición \(index) no tiene la página esperada")
        }
    }

    @Test("Pedir una página fuera de rango devuelve nil en vez de romper")
    func outOfRangePageIsNil() async throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = try ComicArchiveFactory.open(url: try ComicFixtures.makeComicEPUB(in: directory, pageCount: 2))

        #expect(await archive.page(at: -1) == nil)
        #expect(await archive.page(at: 2) == nil)
    }

    @Test("Un EPUB de texto se rechaza con su motivo")
    func textEPUBIsRejected() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try ComicFixtures.makeTextEPUB(in: directory)

        #expect {
            try ComicArchiveFactory.pageCount(at: url)
        } throws: { error in
            guard case ComicArchiveError.textEPUB = error else { return false }
            return true
        }
    }

    @Test("Un ZIP sin container.xml no se acepta como EPUB")
    func zipWithoutContainerIsUnsupported() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Un CBZ renombrado a .epub: tiene imágenes, pero no es un EPUB.
        let url = try ComicFixtures.makeValidCBZ(named: "renombrado.epub", in: directory)

        #expect {
            try ComicArchiveFactory.pageCount(at: url)
        } throws: { error in
            guard case ComicArchiveError.unsupportedFormat = error else { return false }
            return true
        }
    }

    @Test("Una página que declara pesar más de lo permitido se rechaza al abrir")
    func oversizedDocumentIsRejected() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Una «página» XHTML de 3 MB: ninguna real ocupa tanto, y leerla
        // entera solo para buscar una imagen sería un riesgo de memoria.
        let huge = String(repeating: "<p>a</p>", count: 400_000)
        let url = try ComicFixtures.makeEPUB(at: directory.appending(path: "enorme.epub"),
                                             pageBodies: [huge])

        #expect(throws: (any Error).self) {
            try ComicArchiveFactory.pageCount(at: url)
        }
    }
}
