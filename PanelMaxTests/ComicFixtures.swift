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

    /// Nombres visibles (sin ocultos) que hay ahora mismo en `Documents/Comics`.
    /// Sirve para comprobar que una importación fallida no deja copias huérfanas.
    static func comicsDirectoryContents() -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            atPath: LocalComicFile.comicsDirectory.path
        )) ?? []
        return Set(contents.filter { !$0.hasPrefix(".") })
    }
}
