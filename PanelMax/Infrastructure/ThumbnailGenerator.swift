import UIKit

/// Genera la portada de un cómic a partir de su propia primera página.
///
/// Sin catálogo remoto no hay portadas que descargar: la única imagen
/// disponible es la que ya está dentro del archivo. Generarla una vez, en la
/// importación, evita volver a descomprimir el CBZ entero cada vez que una
/// rejilla necesita pintar una miniatura.
enum ThumbnailGenerator {

    /// Abre el archivo ya copiado, extrae su primera página y la reduce a un
    /// tamaño de miniatura. Nunca lanza: una portada que falla no debe impedir
    /// que la importación termine con éxito.
    nonisolated static func makeThumbnail(for url: URL) async -> Data? {
        guard let archive = try? ComicArchiveFactory.open(url: url) else { return nil }
        guard let page = await archive.page(at: 0) else { return nil }
        return ImageResizer.jpegData(from: page)
    }
}

/// Reduce y comprime cualquier `UIImage` a un tamaño manejable como
/// miniatura. Compartido por la portada que se extrae de la página 1 de un
/// cómic y por la que el usuario elige a mano para una serie: ambas deben
/// caber en unos pocos KB en `Documents/Covers`, no en los varios MB que
/// entrega la Fototeca directamente.
enum ImageResizer {

    nonisolated private static let maxDimension: CGFloat = 640
    nonisolated private static let compressionQuality: CGFloat = 0.7

    nonisolated static func jpegData(from image: UIImage) -> Data? {
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        let scale = min(maxDimension / width, maxDimension / height, 1)
        let targetSize = CGSize(width: width * scale, height: height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: compressionQuality)
    }
}

/// Escritura y borrado de miniaturas en `Documents/Covers`.
enum ThumbnailStore {

    @discardableResult
    nonisolated static func save(_ data: Data) throws -> String {
        let directory = try LocalComicFile.prepareCoversDirectory()
        let filename = "\(UUID().uuidString).jpg"
        let url = directory.appending(path: filename, directoryHint: .notDirectory)
        try data.write(to: url, options: .atomic)
        return filename
    }

    /// Borrado silencioso: una miniatura huérfana ocupa unos pocos KB y no
    /// merece interrumpir el flujo de borrado del cómic al que pertenecía.
    nonisolated static func delete(_ filename: String?) {
        guard let filename, let url = try? LocalComicFile.coverStorageURL(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
