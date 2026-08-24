import SwiftUI

/// Portada con marcador de posición y caché.
///
/// `AsyncImage` no cachea en disco, así que en una rejilla de portadas
/// se pasa la vida redescargando. Esto usa la caché de `URLSession`,
/// que sí guarda en disco, y evita el parpadeo al hacer scroll.
struct CoverImage: View {

    let url: URL?
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?
    /// URL que corresponde a `image`. Sin esto, `.task` borraba la portada cada
    /// vez que la vista volvía a aparecer y toda la rejilla parpadeaba al
    /// regresar por el NavigationStack.
    @State private var loadedURL: URL?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Marcador de posición: nada de spinners, que hacen ruido visual en una rejilla.
                Rectangle()
                    .fill(Theme.placeholder)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.title3)
                            .foregroundStyle(Theme.secondaryText.opacity(0.5))
                    }
            }
        }
        .aspectRatio(2/3, contentMode: .fit) // proporción estándar de portada de cómic
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            loadedURL = nil
            return
        }

        // Ya está cargada esta misma portada: no se toca nada.
        guard loadedURL != url else { return }

        // Solo se limpia si había otra portada distinta, no al reaparecer.
        if loadedURL != nil { image = nil }

        do {
            let (data, response) = try await ImageLoader.session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  data.count <= ImageLoader.maximumImageBytes else { return }
            guard let decoded = UIImage(data: data) else { return }

            // La decodificación es cara: hacerla fuera del hilo principal evita tirones.
            let prepared = await decoded.byPreparingForDisplay() ?? decoded

            // La vista pudo reciclarse hacia otra portada mientras se descargaba.
            guard !Task.isCancelled else { return }
            image = prepared
            loadedURL = url
        } catch {
            // Silencio deliberado: una portada que no carga no es un error que mostrar.
        }
    }
}

/// Sesión compartida con caché grande solo para imágenes.
///
/// `URLSession` ya es `Sendable`, así que exponerla directamente evita envolverla
/// en un tipo que habría que declarar `Sendable` a mano bajo concurrencia estricta.
enum ImageLoader {
    static let maximumImageBytes = 20_000_000

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 50_000_000,
                                          diskCapacity: 300_000_000,
                                          directory: URL.cachesDirectory.appending(path: "Covers"))
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()
}
