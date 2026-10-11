#if canImport(ZIPFoundation)
import Foundation
import UIKit
@preconcurrency import ZIPFoundation

/// Saca las páginas de un ZIP ya abierto. Lo comparten `CBZArchive` y
/// `EPUBArchive`: los dos formatos son ZIP con imágenes dentro y solo se
/// diferencian en cómo deciden qué imagen va en cada página.
///
/// CORRECCIÓN IMPORTANTE respecto a la primera versión del lector: `TabView`
/// precarga las páginas vecinas, así que `page(at:)` se llama para dos o tres
/// índices A LA VEZ. Dos extracciones simultáneas sobre el mismo `Archive` son
/// una carrera de datos: fallos aleatorios e imposibles de reproducir. Por eso
/// todas las extracciones pasan por una cola en serie, y la clase puede
/// declararse `@unchecked Sendable` con la conciencia tranquila: el estado
/// mutable compartido (el `Archive`) solo se toca desde esa cola, y `NSCache`
/// ya es seguro entre hilos.
nonisolated final class ZIPPageExtractor: @unchecked Sendable {

    /// Una sola imagen de cómic no debería necesitar 128 MB descomprimida. Este
    /// límite también se comprueba durante la extracción por si el ZIP miente.
    static let maximumEntrySize: UInt64 = 128 * 1_024 * 1_024
    static let maximumExpandedArchiveSize: UInt64 = 4 * 1_024 * 1_024 * 1_024
    static let maximumPageCount = 10_000
    /// Se corta también el número total de entradas, no solo las imágenes:
    /// así un ZIP con millones de ficheros basura no agota memoria al filtrarlo.
    static let maximumArchiveEntryCount = 20_000

    private let archive: Archive
    private let pages: [Entry]

    /// Única puerta de acceso al `Archive`. Ver el comentario de la clase.
    private let queue: DispatchQueue

    /// Caché de páginas ya descomprimidas. Sin esto, pasar página atrás
    /// vuelve a descomprimir la imagen entera.
    private let cache = NSCache<NSNumber, UIImage>()

    /// - Parameter label: nombre de la cola, para distinguirla al depurar.
    init(archive: Archive, pages: [Entry], label: String) throws {
        guard !pages.isEmpty else { throw ComicArchiveError.emptyArchive }
        guard pages.count <= Self.maximumPageCount else { throw ComicArchiveError.tooManyPages }

        // Defensa contra «bombas ZIP»: archivos diminutos que dicen
        // descomprimirse en gigas.
        var expandedSize: UInt64 = 0
        for entry in pages {
            let entrySize = UInt64(entry.uncompressedSize)
            guard entrySize <= Self.maximumEntrySize else {
                throw ComicArchiveError.unsafeCompressedEntry
            }
            let (newSize, overflow) = expandedSize.addingReportingOverflow(entrySize)
            guard !overflow, newSize <= Self.maximumExpandedArchiveSize else {
                throw ComicArchiveError.unsafeCompressedEntry
            }
            expandedSize = newSize
        }

        self.archive = archive
        self.pages = pages
        self.queue = DispatchQueue(label: label, qos: .userInitiated)
        cache.countLimit = 6   // suficiente para ir y volver sin comerse la memoria
    }

    var pageCount: Int { pages.count }

    func page(at index: Int) async -> UIImage? {
        guard pages.indices.contains(index) else { return nil }
        if let cached = cache.object(forKey: NSNumber(value: index)) { return cached }

        let entry = pages[index]
        let archive = self.archive

        // Descomprimir es caro: fuera del hilo principal, y en serie (ver arriba).
        let image: UIImage? = await withCheckedContinuation { continuation in
            queue.async {
                let data = try? archive.extractData(of: entry, maximumSize: Self.maximumEntrySize)
                continuation.resume(returning: data.flatMap { ImageDownsampler.image(from: $0) })
            }
        }

        if let image { cache.setObject(image, forKey: NSNumber(value: index)) }
        return image
    }
}

extension Archive {

    /// Extrae una entrada entera en memoria, cortando en cuanto supere
    /// `maximumSize`. Se comprueba mientras se descomprime, no solo con el
    /// tamaño que declara el ZIP, porque un archivo manipulado puede mentir.
    nonisolated func extractData(of entry: Entry, maximumSize: UInt64) throws -> Data {
        guard UInt64(entry.uncompressedSize) <= maximumSize else {
            throw ComicArchiveError.unsafeCompressedEntry
        }
        var data = Data()
        _ = try extract(entry) { chunk in
            guard UInt64(data.count + chunk.count) <= maximumSize else {
                throw ComicArchiveError.unsafeCompressedEntry
            }
            data.append(chunk)
        }
        return data
    }
}
#endif
