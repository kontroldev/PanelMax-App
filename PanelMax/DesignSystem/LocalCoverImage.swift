import SwiftUI

/// Miniatura local de un cómic, con marcador de posición si no hay ninguna.
///
/// Reemplaza a la antigua `CoverImage`, que descargaba portadas de un
/// catálogo remoto. Aquí la imagen ya vive en disco (ver `ThumbnailGenerator`),
/// así que no hace falta estado de carga asíncrono: leerla es prácticamente
/// instantánea. Pero SÍ hace falta caché: esta vista aparece en listas
/// (`CollectionView`, `HomeView`...) donde `ForEach` recrea la vista cada vez
/// que una fila entra en pantalla, y sin caché eso significa releer y
/// redecodificar el mismo JPEG cada vez que se hace scroll de vuelta a una
/// fila que ya se había visto.
struct LocalCoverImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if let url, let uiImage = Self.cachedImage(at: url) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Theme.placeholder)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.title3)
                            .foregroundStyle(Theme.secondaryText.opacity(0.5))
                    }
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit) // proporción estándar de portada de cómic
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
    }

    // MARK: - Caché

    /// Compartida por todas las instancias de `LocalCoverImage` de la app:
    /// mismo patrón `NSCache` que ya usan `CBZArchive`/`PDFArchive` para las
    /// páginas del lector.
    ///
    /// El límite es en BYTES decodificados, no en número de imágenes: una
    /// portada de ~640 px de lado decodificada en memoria pesa unos 2-3 MB
    /// (aunque el JPEG en disco pese unos pocos cientos de KB), así que
    /// limitar solo por cantidad podría acumular varios cientos de MB sin
    /// darse cuenta con una biblioteca grande.
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024 // ~64 MB, unas 25-30 portadas decodificadas
        return cache
    }()

    /// Es seguro cachear por URL sin invalidación aparte: `ThumbnailStore`
    /// escribe cada portada con un nombre de archivo nuevo (UUID) cada vez
    /// que se genera o se reemplaza una, así que una portada que cambia
    /// siempre trae una URL distinta. La antigua, huérfana, se borra por su
    /// lado (ver `ThumbnailStore.delete`); nunca hay dos contenidos distintos
    /// bajo la misma URL.
    private static func cachedImage(at url: URL) -> UIImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        let decodedBytes = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: key, cost: decodedBytes)
        return image
    }
}
