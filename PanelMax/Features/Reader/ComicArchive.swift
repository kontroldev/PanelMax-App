import Foundation
import UIKit
import ImageIO
import PDFKit
#if canImport(ZIPFoundation)
@preconcurrency import ZIPFoundation
#endif

enum ComicArchiveError: LocalizedError {
    case fileUnavailable
    case unsupportedFormat
    case emptyArchive
    case archiveTooLarge
    case tooManyPages
    case unsafeCompressedEntry
    case pageUnavailable(Int)

    var errorDescription: String? {
        switch self {
        case .fileUnavailable:   return "El archivo ya no está disponible en este dispositivo."
        case .unsupportedFormat: return "Formato no admitido. PanelMax abre CBZ y PDF."
        case .emptyArchive:      return "El archivo no contiene páginas."
        case .archiveTooLarge:   return "El archivo supera el tamaño máximo admitido de 2 GB."
        case .tooManyPages:      return "El archivo contiene demasiadas páginas para abrirlo de forma segura."
        case .unsafeCompressedEntry: return "El CBZ contiene una página comprimida de tamaño peligroso."
        case .pageUnavailable(let page): return "No se ha podido mostrar la página \(page)."
        }
    }
}

/// Cualquier cosa de la que se puedan sacar páginas.
///
/// El lector no sabe si detrás hay un ZIP o un PDF, y eso es lo que permite
/// añadir CBR o carpetas de imágenes más adelante sin tocar la interfaz.
protocol ComicArchive: AnyObject, Sendable {
    nonisolated var pageCount: Int { get }
    nonisolated func page(at index: Int) async -> UIImage?
}

// MARK: - Fábrica

enum ComicArchiveFactory {

    /// Abre el archivo adecuado según la extensión.
    ///
    /// Si el archivo viene de un marcador de seguridad hay que pedir acceso antes
    /// de leerlo; el `defer` lo libera pase lo que pase.
    static func open(_ file: LocalComicFile) throws -> any ComicArchive {
        let url = try file.resolveURL()
        return try open(url: url)
    }

    /// Abre una URL y mantiene vivo el acceso de seguridad durante toda la lectura.
    /// PDFKit y ZIPFoundation leen páginas de forma diferida, así que liberar el
    /// permiso justo después del inicializador hace fallar archivos de iCloud.
    nonisolated static func open(url: URL) throws -> any ComicArchive {
        let access = SecurityScopedAccess(url: url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile != false else { throw ComicArchiveError.fileUnavailable }
        if let size = values.fileSize, Int64(size) > 2 * 1_024 * 1_024 * 1_024 {
            throw ComicArchiveError.archiveTooLarge
        }

        switch url.pathExtension.lowercased() {
        #if canImport(ZIPFoundation)
        case "cbz", "zip":
            return try CBZArchive(url: url, securityAccess: access)
        #endif
        case "pdf":
            return try PDFArchive(url: url, securityAccess: access)
        default:
            throw ComicArchiveError.unsupportedFormat
        }
    }

    /// Valida el archivo durante la importación y devuelve sus páginas. Abrirlo
    /// aquí evita guardar en la biblioteca PDFs/CBZ vacíos o corruptos.
    nonisolated static func pageCount(at url: URL) throws -> Int {
        let archive = try open(url: url)
        return archive.pageCount
    }
}

/// Conserva el permiso de una URL externa hasta que el archivo deja de usarse.
nonisolated private final class SecurityScopedAccess: @unchecked Sendable {
    private let url: URL
    private let didStart: Bool

    nonisolated init(url: URL) {
        self.url = url
        self.didStart = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStart { url.stopAccessingSecurityScopedResource() }
    }
}

// MARK: - CBZ

#if canImport(ZIPFoundation)
/// CBZ: un ZIP con las páginas dentro, numeradas por nombre de archivo.
///
/// CORRECCIÓN IMPORTANTE respecto a la primera versión: `TabView` precarga las
/// páginas adyacentes, así que `page(at:)` se llama para dos o tres índices A LA VEZ.
/// La primera versión lanzaba una `Task.detached` por página, y dos extracciones
/// concurrentes sobre el mismo `Archive` son una carrera de datos: fallos aleatorios
/// e imposibles de reproducir. Ahora todas las extracciones pasan por una cola en
/// serie, y por eso la clase puede declararse `@unchecked Sendable` con la conciencia
/// tranquila: el estado mutable compartido (el `Archive`) solo se toca desde la cola.
nonisolated final class CBZArchive: ComicArchive, @unchecked Sendable {

    private let archive: Archive
    private let entries: [Entry]
    private let securityAccess: SecurityScopedAccess

    /// Única puerta de acceso al `Archive`. Ver el comentario de la clase.
    private let extractionQueue = DispatchQueue(label: "com.raulgallego.panelmax.cbz",
                                                qos: .userInitiated)

    /// Caché de páginas ya descomprimidas. `NSCache` es seguro entre hilos.
    /// Sin esto, pasar página atrás vuelve a descomprimir la imagen entera.
    private let cache = NSCache<NSNumber, UIImage>()

    /// Una sola imagen de cómic no debería necesitar 128 MB descomprimida. Este
    /// límite también se comprueba durante la extracción por si el ZIP miente.
    private static let maximumEntrySize: UInt64 = 128 * 1_024 * 1_024
    private static let maximumExpandedArchiveSize: UInt64 = 4 * 1_024 * 1_024 * 1_024
    private static let maximumPageCount = 10_000
    private static let maximumArchiveEntryCount = 20_000

    fileprivate nonisolated init(url: URL, securityAccess: SecurityScopedAccess) throws {
        // API comprobada con ZIPFoundation 0.9.20 (última versión estable).
        let archive = try Archive(url: url, accessMode: .read)

        // Se corta también el número total de entradas, no solo las imágenes:
        // así un ZIP con millones de ficheros basura no agota memoria al filtrarlo.
        var scannedEntries = 0
        var entries: [Entry] = []
        for entry in archive {
            scannedEntries += 1
            guard scannedEntries <= Self.maximumArchiveEntryCount else {
                throw ComicArchiveError.tooManyPages
            }
            if entry.type == .file, Self.isImage(entry.path) {
                entries.append(entry)
                guard entries.count <= Self.maximumPageCount else {
                    throw ComicArchiveError.tooManyPages
                }
            }
        }
        // Orden natural: sin esto, "pagina10" va antes que "pagina2".
        entries.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        guard !entries.isEmpty else { throw ComicArchiveError.emptyArchive }

        var expandedSize: UInt64 = 0
        for entry in entries {
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
        self.entries = entries
        self.securityAccess = securityAccess
        cache.countLimit = 6   // suficiente para ir y volver sin comerse la memoria
    }

    nonisolated var pageCount: Int { entries.count }

    nonisolated func page(at index: Int) async -> UIImage? {
        guard entries.indices.contains(index) else { return nil }

        if let cached = cache.object(forKey: NSNumber(value: index)) { return cached }

        let entry = entries[index]
        let archive = self.archive

        // Descomprimir es caro: fuera del hilo principal, y en serie (ver arriba).
        let image: UIImage? = await withCheckedContinuation { continuation in
            extractionQueue.async {
                do {
                    var data = Data()
                    _ = try archive.extract(entry) { chunk in
                        let remaining = Int(Self.maximumEntrySize) - data.count
                        guard chunk.count <= remaining else {
                            throw ComicArchiveError.unsafeCompressedEntry
                        }
                        data.append(chunk)
                    }
                    continuation.resume(returning: ImageDownsampler.image(from: data))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }

        if let image { cache.setObject(image, forKey: NSNumber(value: index)) }
        return image
    }

    nonisolated private static func isImage(_ path: String) -> Bool {
        // Los ZIP de macOS traen basura: __MACOSX, .DS_Store, ficheros ocultos.
        let name = (path as NSString).lastPathComponent
        guard !name.hasPrefix("."), !path.contains("__MACOSX") else { return false }
        return ["jpg", "jpeg", "png", "webp", "gif"].contains((path as NSString).pathExtension.lowercased())
    }
}
#endif

// MARK: - PDF

/// PDF: PDFKit viene con el sistema, así que este formato funciona sin dependencias.
///
/// `@unchecked Sendable`: todo acceso a `PDFDocument` pasa por `renderQueue`.
/// `TabView` pide páginas vecinas a la vez y PDFKit no documenta que esas lecturas
/// concurrentes sean seguras.
nonisolated final class PDFArchive: ComicArchive, @unchecked Sendable {

    private let document: PDFDocument
    private let numberOfPages: Int
    private let securityAccess: SecurityScopedAccess
    private let renderQueue = DispatchQueue(label: "com.raulgallego.panelmax.pdf",
                                            qos: .userInitiated)
    private let cache = NSCache<NSNumber, UIImage>()

    fileprivate nonisolated init(url: URL, securityAccess: SecurityScopedAccess) throws {
        guard let document = PDFDocument(url: url) else { throw ComicArchiveError.unsupportedFormat }
        guard document.pageCount > 0 else { throw ComicArchiveError.emptyArchive }
        guard document.pageCount <= 10_000 else { throw ComicArchiveError.tooManyPages }
        self.document = document
        self.numberOfPages = document.pageCount
        self.securityAccess = securityAccess
        cache.countLimit = 6
    }

    nonisolated var pageCount: Int { numberOfPages }

    /// Ancho en píxeles al que se rasteriza cada página del PDF.
    ///
    /// Se calcula una sola vez a partir de la pantalla del dispositivo, con un
    /// suelo de 1290 px (para que un iPhone pequeño no renderice páginas
    /// pobres) y un techo de 2400 px, que es el mismo límite que usa
    /// `ImageDownsampler` para los CBZ: por encima de eso el coste de memoria
    /// no compensa la mejora visible.
    nonisolated static let renderWidth: CGFloat = {
        let bounds = UIScreen.main.nativeBounds.size
        let nativeWidth = max(bounds.width, bounds.height) // apaisado incluido
        return min(max(nativeWidth, 1_290), 2_400)
    }()

    nonisolated func page(at index: Int) async -> UIImage? {
        guard index >= 0, index < numberOfPages else { return nil }
        if let cached = cache.object(forKey: NSNumber(value: index)) { return cached }

        let image: UIImage? = await withCheckedContinuation { continuation in
            renderQueue.async {
                guard let page = self.document.page(at: index) else {
                    continuation.resume(returning: nil)
                    return
                }

                let bounds = page.bounds(for: .mediaBox)
                guard bounds.width.isFinite, bounds.height.isFinite,
                      bounds.width > 0, bounds.height > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                // Nítido en Retina, pero con ambas dimensiones acotadas para que
                // una página deliberadamente extrema no reserve cientos de MB.
                //
                // El ancho objetivo se deriva de la pantalla real, no de una
                // constante: estaba fijado en 1290 px (el ancho del iPhone 16
                // Pro), así que en un iPad de 13" (2064 px de ancho) cada página
                // se renderizaba pequeña y el sistema la escalaba hacia arriba,
                // con el resultado de un PDF visiblemente borroso.
                let targetWidth = PDFArchive.renderWidth
                let maximumDimension: CGFloat = 4_096
                let scale = min(targetWidth / bounds.width,
                                maximumDimension / max(bounds.width, bounds.height))
                let size = CGSize(width: max(bounds.width * scale, 1),
                                  height: max(bounds.height * scale, 1))
                continuation.resume(returning: page.thumbnail(of: size, for: .mediaBox))
            }
        }

        if let image { cache.setObject(image, forKey: NSNumber(value: index)) }
        return image
    }
}

// MARK: - Reducción de tamaño

/// Los escaneos de cómic vienen a 3.000 px de ancho. Cargar treinta a pelo
/// revienta la memoria del iPhone. ImageIO permite decodificar ya reducido.
enum ImageDownsampler {

    nonisolated static func image(from data: Data, maxPixelSize: CGFloat = 2400) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}
