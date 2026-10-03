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

    /// Ancho fijo de la portada. El alto se deriva de él con la proporción
    /// 2:3 estándar de un cómic, así que el tamaño final queda determinado
    /// por completo por este único número.
    ///
    /// A propósito NO se deja que el tamaño salga de combinar un
    /// `.aspectRatio(_, contentMode: .fit)` interno con un `.frame(width:)`
    /// puesto por fuera, como tenía antes: esa combinación depende de qué
    /// alto le proponga el contenedor (una fila de `Form`, un `HStack`...), y
    /// con una foto del carrete de proporción muy distinta a 2:3 — un
    /// panorámico ancho y bajo, por ejemplo — ese alto propuesto podía acabar
    /// siendo mayor de lo esperado, así que la portada salía más grande que
    /// su caja y se montaba sobre los botones de al lado. Fijar aquí dentro
    /// las dos dimensiones (`width` Y `height`) hace que la portada mida
    /// siempre lo mismo pase lo que pase alrededor, sea cual sea la foto.
    var width: CGFloat
    var cornerRadius: CGFloat = 8

    /// Inicializador explícito y `nonisolated`: sin él, el memberwise
    /// sintetizado queda aislado a `@MainActor` (como el resto del tipo, por
    /// conformar `View`), y algunos llamadores construyen esta vista desde un
    /// closure que el propio framework tipa como `@Sendable` — por ejemplo el
    /// `label` de `PhotosPicker` en `SeriesDetailView`. Aquí solo se copian
    /// valores simples (`URL`, `CGFloat`), así que no hace falta tocar el
    /// actor principal para construir la estructura. Mismo patrón que
    /// `ComicArchive.init(url:)`.
    nonisolated init(url: URL?, width: CGFloat, cornerRadius: CGFloat = 8) {
        self.url = url
        self.width = width
        self.cornerRadius = cornerRadius
    }

    private var height: CGFloat { width * 3 / 2 }

    /// Portada decodificada en segundo plano cuando no estaba ya en caché.
    /// Ver `.task` más abajo: por qué no se decodifica directamente en `body`.
    @State private var decoded: UIImage?

    var body: some View {
        ZStack {
            if let url, let uiImage = Self.cachedImageIfPresent(at: url) ?? decoded {
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
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
        // Solo entra aquí si `cachedImageIfPresent` ya ha fallado arriba: una
        // portada cacheada no pasa nunca por esta tarea, así que volver a una
        // fila ya vista sigue siendo instantáneo y sin parpadeo, exactamente
        // como antes. La tarea solo existe para el fallo de caché: leer el
        // JPEG de disco y decodificarlo es justo el trabajo que antes se hacía
        // DENTRO de `body`, en el hilo principal, para cada portada nueva que
        // entraba en pantalla — con una biblioteca grande, decenas de esas
        // decodificaciones síncronas de golpe al arrancar son lo que se nota
        // como lentitud. Aquí se reparte en tareas en segundo plano y la
        // portada aparece en cuanto está lista, sin bloquear el primer fotograma.
        .task(id: url) {
            guard let url, Self.cachedImageIfPresent(at: url) == nil else { return }
            let image = await Task.detached(priority: .utility) {
                Self.decodeFromDisk(at: url)
            }.value
            guard !Task.isCancelled else { return }
            if let image { Self.store(image, for: url) }
            decoded = image
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

    /// Solo consulta la caché en memoria: ni toca disco ni decodifica nada,
    /// así que es seguro llamarla directamente desde `body`.
    private static func cachedImageIfPresent(at url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Es seguro cachear por URL sin invalidación aparte: `ThumbnailStore`
    /// escribe cada portada con un nombre de archivo nuevo (UUID) cada vez
    /// que se genera o se reemplaza una, así que una portada que cambia
    /// siempre trae una URL distinta. La antigua, huérfana, se borra por su
    /// lado (ver `ThumbnailStore.delete`); nunca hay dos contenidos distintos
    /// bajo la misma URL.
    nonisolated private static func decodeFromDisk(at url: URL) -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }

    private static func store(_ image: UIImage, for url: URL) {
        let decodedBytes = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: decodedBytes)
    }
}
