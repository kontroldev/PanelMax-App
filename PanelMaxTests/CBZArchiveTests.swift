import Foundation
import Testing
import UIKit
@testable import PanelMax

/// `CBZArchive` es lo que abre cada cómic que lee el usuario. Los CBZ se
/// generan en cada test (ver `ComicFixtures`) dentro de una carpeta temporal
/// propia, así que esta suite no toca `Documents/Comics`.
@Suite("Lectura de CBZ")
struct CBZArchiveTests {

    @Test("Cuenta solo las imágenes del archivo")
    func countsPages() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try ComicFixtures.makeValidCBZ(in: directory, pageCount: 3)

        #expect(try ComicArchiveFactory.pageCount(at: url) == 3)
    }

    @Test("Ordena las páginas con orden natural: pagina2 va antes que pagina10")
    func naturalPageOrder() async throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Se escriben desordenadas a propósito. Con orden alfabético simple
        // saldría pagina1, pagina10, pagina2.
        let url = try ComicFixtures.makeCBZ(at: directory.appending(path: "orden.cbz"), entries: [
            (path: "pagina10.png", data: ComicFixtures.png(width: ComicFixtures.pageWidth(2))),
            (path: "pagina1.png", data: ComicFixtures.png(width: ComicFixtures.pageWidth(0))),
            (path: "pagina2.png", data: ComicFixtures.png(width: ComicFixtures.pageWidth(1)))
        ])

        let archive = try ComicArchiveFactory.open(url: url)
        for index in 0..<3 {
            let page = try #require(await archive.page(at: index))
            #expect(Int(page.size.width * page.scale) == ComicFixtures.pageWidth(index),
                    "La posición \(index) no tiene la página esperada")
        }
    }

    @Test("Descarta la basura que añade macOS al comprimir")
    func ignoresMacOSJunk() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let page = ComicFixtures.png(width: 10)
        let url = try ComicFixtures.makeCBZ(at: directory.appending(path: "mac.cbz"), entries: [
            (path: "pagina1.png", data: page),
            (path: "__MACOSX/._pagina1.png", data: page),
            (path: ".DS_Store", data: Data([0x00, 0x01])),
            (path: "._oculta.png", data: page),
            (path: "LEEME.txt", data: Data("hola".utf8))
        ])

        #expect(try ComicArchiveFactory.pageCount(at: url) == 1)
    }

    @Test("Un ZIP sin imágenes no se puede abrir como cómic")
    func archiveWithoutImagesIsEmpty() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try ComicFixtures.makeCBZ(at: directory.appending(path: "vacio.cbz"), entries: [
            (path: "LEEME.txt", data: Data("sin páginas".utf8)),
            (path: "__MACOSX/._LEEME.txt", data: Data([0x00]))
        ])

        #expect {
            try ComicArchiveFactory.pageCount(at: url)
        } throws: { error in
            guard case ComicArchiveError.emptyArchive = error else { return false }
            return true
        }
    }

    @Test("Un archivo con extensión .cbz que no es un ZIP se rechaza")
    func corruptArchiveThrows() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "roto.cbz")
        try Data("esto no es un zip".utf8).write(to: url)

        #expect(throws: (any Error).self) {
            try ComicArchiveFactory.pageCount(at: url)
        }
    }

    @Test("Una extensión no admitida se rechaza aunque el contenido sea un ZIP")
    func unsupportedExtensionThrows() throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try ComicFixtures.makeValidCBZ(named: "comic.rar", in: directory)

        #expect {
            try ComicArchiveFactory.pageCount(at: url)
        } throws: { error in
            guard case ComicArchiveError.unsupportedFormat = error else { return false }
            return true
        }
    }

    @Test("Pedir una página fuera de rango devuelve nil en vez de romper")
    func outOfRangePageIsNil() async throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try ComicFixtures.makeValidCBZ(in: directory, pageCount: 2)
        let archive = try ComicArchiveFactory.open(url: url)

        #expect(await archive.page(at: -1) == nil)
        #expect(await archive.page(at: 2) == nil)
    }

    @Test("Pedir varias páginas a la vez no corrompe la extracción")
    func concurrentPageRequests() async throws {
        let directory = try ComicFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // El lector precarga las páginas vecinas en paralelo: es el escenario
        // que la cola de extracción en serie de `CBZArchive` debe soportar.
        let pageCount = 6
        let url = try ComicFixtures.makeValidCBZ(in: directory, pageCount: pageCount)
        let archive = try ComicArchiveFactory.open(url: url)

        let widths = await withTaskGroup(of: (Int, Int?).self) { group in
            for index in 0..<pageCount {
                group.addTask {
                    let page = await archive.page(at: index)
                    return (index, page.map { Int($0.size.width * $0.scale) })
                }
            }
            var result: [Int: Int?] = [:]
            for await (index, width) in group { result[index] = width }
            return result
        }

        for index in 0..<pageCount {
            #expect(widths[index] == ComicFixtures.pageWidth(index))
        }
    }
}
