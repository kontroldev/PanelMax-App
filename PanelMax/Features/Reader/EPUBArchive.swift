#if canImport(ZIPFoundation)
import Foundation
import UIKit
@preconcurrency import ZIPFoundation

/// EPUB de cómic: un ZIP con una imagen por página.
///
/// Qué imagen va en cada página lo decide `EPUBPackage` leyendo el índice del
/// propio EPUB (su orden de lectura, no el nombre de los archivos, a
/// diferencia de los CBZ). La extracción, la caché y los límites de seguridad
/// son los mismos que los de los CBZ (`ZIPPageExtractor`), así que el lector,
/// el zoom, la doble página y el progreso funcionan sin saber que es un EPUB.
nonisolated final class EPUBArchive: ComicArchive {

    /// Tope para los documentos de texto del EPUB (índice y páginas XHTML):
    /// uno real ocupa unos pocos KB. Evita que un archivo manipulado obligue
    /// a cargar cientos de MB en memoria solo para buscar una imagen.
    static let maximumDocumentSize: UInt64 = 2 * 1_024 * 1_024

    private let extractor: ZIPPageExtractor
    private let securityAccess: SecurityScopedAccess

    nonisolated init(url: URL, securityAccess: SecurityScopedAccess) throws {
        let archive = try Archive(url: url, accessMode: .read)

        var scannedEntries = 0
        var entriesByPath: [String: Entry] = [:]
        for entry in archive {
            scannedEntries += 1
            guard scannedEntries <= ZIPPageExtractor.maximumArchiveEntryCount else {
                throw ComicArchiveError.tooManyPages
            }
            if entry.type == .file { entriesByPath[entry.path] = entry }
        }

        let package = try EPUBPackage.parse(
            fileExists: { entriesByPath[$0] != nil },
            readFile: { path in
                guard let entry = entriesByPath[path] else { return nil }
                return try archive.extractData(of: entry, maximumSize: Self.maximumDocumentSize)
            }
        )

        self.extractor = try ZIPPageExtractor(archive: archive,
                                              pages: package.pageImagePaths.compactMap { entriesByPath[$0] },
                                              label: "com.raulgallego.panelmax.epub")
        self.securityAccess = securityAccess
    }

    nonisolated var pageCount: Int { extractor.pageCount }

    nonisolated func page(at index: Int) async -> UIImage? {
        await extractor.page(at: index)
    }
}
#endif
