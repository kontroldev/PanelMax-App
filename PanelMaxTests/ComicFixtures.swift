import Foundation
import UIKit
import ZIPFoundation
@testable import PanelMax

/// Archivos de prueba generados al vuelo, para no meter binarios en el repo.
///
/// Cada página es un PNG liso cuyo ANCHO identifica su posición prevista
/// (ver `pageWidth(_:)`): así un test puede saber qué página le ha devuelto
/// el lector sin comparar píxeles.
enum ComicFixtures {

    /// Carpeta temporal propia de cada llamada. Quien la crea la borra.
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ComicFixtures-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Ancho en píxeles de la página que debería salir en la posición `index`.
    static func pageWidth(_ index: Int) -> Int { (index + 1) * 10 }

    /// PNG liso de `width × 20` píxeles.
    static func png(width: Int, height: Int = 20) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }

    /// Crea un ZIP con las entradas indicadas (ruta dentro del ZIP → contenido).
    /// Se escriben en el orden dado: el lector debe reordenarlas por nombre.
    @discardableResult
    static func makeCBZ(at url: URL, entries: [(path: String, data: Data)]) throws -> URL {
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            let data = entry.data
            try archive.addEntry(with: entry.path,
                                 type: .file,
                                 uncompressedSize: Int64(data.count),
                                 compressionMethod: .deflate) { position, size in
                let start = Int(position)
                return data.subdata(in: start..<min(start + size, data.count))
            }
        }
        return url
    }

    /// CBZ válido de `pageCount` páginas, con nombres `pagina1.png`,
    /// `pagina2.png`... que solo quedan bien ordenados con orden natural.
    @discardableResult
    static func makeValidCBZ(named name: String = "comic.cbz",
                             in directory: URL,
                             pageCount: Int = 3) throws -> URL {
        let entries = (0..<pageCount).map { index in
            (path: "pagina\(index + 1).png", data: png(width: pageWidth(index)))
        }
        return try makeCBZ(at: directory.appending(path: name), entries: entries)
    }

    /// Nombres visibles (sin ocultos) que hay ahora mismo en `Comics/`.
    /// Sirve para comprobar que una importación fallida no deja copias huérfanas.
    static func comicsDirectoryContents() -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            atPath: LocalComicFile.comicsDirectory.path
        )) ?? []
        return Set(contents.filter { !$0.hasPrefix(".") })
    }

    // MARK: - EPUB

    static let epubContainerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """

    /// Página XHTML completa, como las de un EPUB real: con DOCTYPE, título y
    /// estilos en la cabecera (que no deben contar como texto de la página).
    static func epubPage(body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <head><title>Página del cómic</title><style>body { margin: 0; }</style></head>
          <body>\(body)</body>
        </html>
        """
    }

    /// Índice (`.opf`) con una página XHTML por cuerpo en `pageBodies`. El
    /// manifest se escribe AL REVÉS a propósito: el orden de lectura debe
    /// salir del spine, no del orden en que aparecen los archivos.
    static func epubPackageOPF(pageCount: Int, imageNames: [String]) -> String {
        let pageItems = (0..<pageCount).map {
            "<item id=\"p\($0)\" href=\"text/p\($0).xhtml\" media-type=\"application/xhtml+xml\"/>"
        }
        let imageItems = imageNames.map {
            "<item id=\"img-\($0)\" href=\"images/\($0)\" media-type=\"image/png\"/>"
        }
        let spine = (0..<pageCount).map { "<itemref idref=\"p\($0)\"/>" }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Prueba</dc:title></metadata>
              <manifest>\((pageItems.reversed() + imageItems).joined())</manifest>
              <spine>\(spine.joined())</spine>
            </package>
            """
    }

    /// EPUB con una página XHTML por cada cuerpo de `pageBodies`.
    @discardableResult
    static func makeEPUB(at url: URL,
                         pageBodies: [String],
                         images: [(name: String, data: Data)] = [],
                         extraEntries: [(path: String, data: Data)] = []) throws -> URL {
        var entries: [(path: String, data: Data)] = [
            (path: "mimetype", data: Data("application/epub+zip".utf8)),
            (path: "META-INF/container.xml", data: Data(epubContainerXML.utf8)),
            (path: "OEBPS/content.opf",
             data: Data(epubPackageOPF(pageCount: pageBodies.count, imageNames: images.map(\.name)).utf8))
        ]
        for (index, body) in pageBodies.enumerated() {
            entries.append((path: "OEBPS/text/p\(index).xhtml", data: Data(epubPage(body: body).utf8)))
        }
        for image in images {
            entries.append((path: "OEBPS/images/\(image.name)", data: image.data))
        }
        return try makeCBZ(at: url, entries: entries + extraEntries)
    }

    /// EPUB de cómic válido: una imagen por página, cada una con el ancho que
    /// identifica su posición (ver `pageWidth(_:)`), igual que los CBZ.
    @discardableResult
    static func makeComicEPUB(named name: String = "comic.epub",
                              in directory: URL,
                              pageCount: Int = 3) throws -> URL {
        let images = (0..<pageCount).map {
            (name: "pagina\($0 + 1).png", data: png(width: pageWidth($0)))
        }
        return try makeEPUB(at: directory.appending(path: name),
                            pageBodies: images.map { "<img src=\"../images/\($0.name)\" alt=\"\"/>" },
                            images: images)
    }

    /// EPUB de texto, como una novela: capítulos con párrafos y sin imágenes.
    @discardableResult
    static func makeTextEPUB(named name: String = "novela.epub",
                             in directory: URL,
                             chapters: Int = 5) throws -> URL {
        let paragraph = "<p>Era una noche oscura y tormentosa, y la lluvia caía a raudales sobre la ciudad dormida.</p>"
        return try makeEPUB(at: directory.appending(path: name),
                            pageBodies: Array(repeating: String(repeating: paragraph, count: 4), count: chapters))
    }

    // MARK: - PDF

    /// PDF de `pageCount` páginas de `pageSize` puntos, cada una con un color
    /// liso. Generado al vuelo, igual que los CBZ.
    @discardableResult
    static func makePDF(at url: URL,
                        pageCount: Int = 3,
                        pageSize: CGSize = CGSize(width: 200, height: 300)) throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        try renderer.writePDF(to: url) { context in
            for _ in 0..<pageCount {
                context.beginPage()
                UIColor.systemBlue.setFill()
                context.fill(CGRect(origin: .zero, size: pageSize))
            }
        }
        return url
    }
}
