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
    /// EPUB de texto (una novela) o con texto real encima del dibujo: solo
    /// se admiten EPUB de cómic con una imagen por página (ver `EPUBPackage`).
    case textEPUB
    /// EPUB protegido con DRM: sus páginas están cifradas y no se pueden leer.
    case protectedEPUB

    /// Un EPUB bien formado que no se puede abrir por lo que contiene, no por
    /// estar roto. La importación lo explica tal cual en vez de decir solo
    /// «no es compatible».
    nonisolated var isIncompatibleEPUB: Bool {
        switch self {
        case .textEPUB, .protectedEPUB: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .fileUnavailable:   return "El archivo ya no está disponible en este dispositivo."
        case .unsupportedFormat: return "Formato no admitido. \(AppInfo.displayName) abre CBZ, PDF y EPUB de cómic."
        case .emptyArchive:      return "El archivo no contiene páginas."
        case .archiveTooLarge:   return "El archivo supera el tamaño máximo admitido de 2 GB."
        case .tooManyPages:      return "El archivo contiene demasiadas páginas para abrirlo de forma segura."
        case .unsafeCompressedEntry: return "El archivo contiene una página comprimida de tamaño peligroso."
        case .pageUnavailable(let page): return "No se ha podido mostrar la página \(page)."
        case .textEPUB:
            return "Es un EPUB de texto, como una novela, o con texto encima de los dibujos. \(AppInfo.displayName) abre EPUB de cómic con una imagen por página."
        case .protectedEPUB:
            return "Este EPUB está protegido con DRM (por ejemplo, si se compró en Apple Books o Kindle) y no se puede abrir. \(AppInfo.displayName) solo abre archivos sin protección."
        }
    }
}

/// Cualquier cosa de la que se puedan sacar páginas.
///
/// El lector no sabe si detrás hay un ZIP, un PDF o un EPUB, y eso es lo que
/// permite añadir formatos sin tocar la interfaz.
protocol ComicArchive: AnyObject, Sendable {
    nonisolated var pageCount: Int { get }
    nonisolated func page(at index: Int) async -> UIImage?
}

/// Formatos de imagen que pueden ser una página, compartido por CBZ y EPUB.
enum ComicPageImage {
    nonisolated static let extensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]

    nonisolated static func isSupported(_ path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }
}

// MARK: - Fábrica

enum ComicArchiveFactory {

    /// Abre el archivo adecuado según la extensión.
    ///
    /// Si el archivo viene de un marcador de seguridad hay que pedir acceso antes
    /// de leerlo; el `defer` lo libera pase lo que pase.
    ///
    /// `pdfTargetWidth` solo importa para PDF (ver `PDFArchive.preferredRenderWidth()`).
    /// El valor por defecto vale para generar miniaturas en segundo plano, donde no
    /// hay pantalla que consultar y el resultado se va a reducir de todos modos.
    static func open(_ file: LocalComicFile, pdfTargetWidth: CGFloat = PDFArchive.defaultRenderWidth) throws -> any ComicArchive {
        let url = try file.resolveURL()
        return try open(url: url, pdfTargetWidth: pdfTargetWidth)
    }

    /// Abre una URL y mantiene vivo el acceso de seguridad durante toda la lectura.
    /// PDFKit y ZIPFoundation leen páginas de forma diferida, así que liberar el
    /// permiso justo después del inicializador hace fallar archivos de iCloud.
    nonisolated static func open(url: URL, pdfTargetWidth: CGFloat = PDFArchive.defaultRenderWidth) throws -> any ComicArchive {
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
        case "epub":
            return try EPUBArchive(url: url, securityAccess: access)
        #endif
        case "pdf":
            return try PDFArchive(url: url, targetWidth: pdfTargetWidth, securityAccess: access)
        default:
            throw ComicArchiveError.unsupportedFormat
        }
    }

    /// Igual que `open(url:pdfTargetWidth:)`, pero siempre fuera del hilo
    /// principal: abrir un CBZ recorre todas sus entradas, y con un
    /// recopilatorio grande eso se nota. El resultado (`any ComicArchive`) es
    /// `Sendable`, así que puede volver sin problema a la vista que lo pidió.
    @concurrent
    nonisolated static func openInBackground(url: URL,
                                             pdfTargetWidth: CGFloat = PDFArchive.defaultRenderWidth) async throws -> any ComicArchive {
        try open(url: url, pdfTargetWidth: pdfTargetWidth)
    }

    /// Valida el archivo durante la importación y devuelve sus páginas. Abrirlo
    /// aquí evita guardar en la biblioteca archivos vacíos, corruptos o, en el
    /// caso de los EPUB, de texto o con DRM.
    nonisolated static func pageCount(at url: URL) throws -> Int {
        let archive = try open(url: url)
        return archive.pageCount
    }
}

/// Conserva el permiso de una URL externa hasta que el archivo deja de usarse.
///
/// `Sendable` a secas, sin `@unchecked`: solo guarda constantes (`let`) de
/// tipos que ya son `Sendable`, así que el compilador puede comprobarlo solo.
nonisolated final class SecurityScopedAccess: Sendable {
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
/// La extracción (cola en serie, caché y límites de seguridad) la hace
/// `ZIPPageExtractor`, compartido con `EPUBArchive`. Aquí solo se decide qué
/// imágenes son páginas y en qué orden van. Ya no necesita `@unchecked`:
/// solo guarda constantes de tipos `Sendable`, y el compilador lo comprueba.
nonisolated final class CBZArchive: ComicArchive {

    private let extractor: ZIPPageExtractor
    private let securityAccess: SecurityScopedAccess

    fileprivate nonisolated init(url: URL, securityAccess: SecurityScopedAccess) throws {
        // API comprobada con ZIPFoundation 0.9.20 (última versión estable).
        let archive = try Archive(url: url, accessMode: .read)

        var scannedEntries = 0
        var entries: [Entry] = []
        for entry in archive {
            scannedEntries += 1
            guard scannedEntries <= ZIPPageExtractor.maximumArchiveEntryCount else {
                throw ComicArchiveError.tooManyPages
            }
            if entry.type == .file, Self.isImage(entry.path) {
                entries.append(entry)
                guard entries.count <= ZIPPageExtractor.maximumPageCount else {
                    throw ComicArchiveError.tooManyPages
                }
            }
        }
        // Orden natural: sin esto, "pagina10" va antes que "pagina2".
        entries.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        self.extractor = try ZIPPageExtractor(archive: archive,
                                              pages: entries,
                                              label: "com.raulgallego.panelmax.cbz")
        self.securityAccess = securityAccess
    }

    nonisolated var pageCount: Int { extractor.pageCount }

    nonisolated func page(at index: Int) async -> UIImage? {
        await extractor.page(at: index)
    }

    nonisolated private static func isImage(_ path: String) -> Bool {
        // Los ZIP de macOS traen basura: __MACOSX, .DS_Store, ficheros ocultos.
        let name = (path as NSString).lastPathComponent
        guard !name.hasPrefix("."), !path.contains("__MACOSX") else { return false }
        return ComicPageImage.isSupported(path)
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

    /// Ancho en píxeles al que se rasteriza cada página. Lo calcula la vista
    /// del lector a partir de su propio tamaño (ver `preferredRenderWidth`) y
    /// llega aquí ya como un número: esta clase no sabe nada de pantallas.
    private let targetWidth: CGFloat

    fileprivate nonisolated init(url: URL, targetWidth: CGFloat, securityAccess: SecurityScopedAccess) throws {
        guard let document = PDFDocument(url: url) else { throw ComicArchiveError.unsupportedFormat }
        guard document.pageCount > 0 else { throw ComicArchiveError.emptyArchive }
        guard document.pageCount <= 10_000 else { throw ComicArchiveError.tooManyPages }
        self.document = document
        self.numberOfPages = document.pageCount
        self.targetWidth = targetWidth
        self.securityAccess = securityAccess
        cache.countLimit = 6
    }

    nonisolated var pageCount: Int { numberOfPages }

    /// Ancho de rasterizado por defecto para quien abra un PDF sin pasar por
    /// la pantalla (por ejemplo, generar una miniatura en segundo plano). Es
    /// el mismo valor que se usaba antes de tener en cuenta la pantalla real.
    nonisolated static let defaultRenderWidth: CGFloat = 1_290

    /// Ancho de rasterizado ideal para la ventana del lector, con suelo de
    /// 1290 px (para que un iPhone pequeño no renderice páginas pobres) y
    /// techo de 2400 px, el mismo límite que usa `ImageDownsampler` para los CBZ.
    ///
    /// Recibe el tamaño de la vista (en puntos) y la escala de la pantalla
    /// en la que se dibuja, en vez de consultar `UIScreen.main`: esa API está
    /// obsoleta y, en iPad con varias ventanas o con una pantalla externa,
    /// puede devolver la pantalla equivocada. Se usa el lado más largo para
    /// que girar el dispositivo no deje páginas ya renderizadas pequeñas.
    nonisolated static func preferredRenderWidth(viewSize: CGSize, displayScale: CGFloat) -> CGFloat {
        let longestSide = max(viewSize.width, viewSize.height) * max(displayScale, 1)
        return min(max(longestSide, 1_290), 2_400)
    }

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
                // El ancho objetivo ya no se calcula aquí dentro: antes estaba
                // fijado a 1290 px (el ancho del iPhone 16 Pro), así que en un
                // iPad de 13" (2064 px de ancho) cada página se renderizaba
                // pequeña y el sistema la escalaba hacia arriba, con el
                // resultado de un PDF visiblemente borroso. Ahora llega ya
                // calculado desde fuera, en `self.targetWidth`.
                let maximumDimension: CGFloat = 4_096
                let scale = min(self.targetWidth / bounds.width,
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
