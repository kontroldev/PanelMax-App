import SwiftUI

/// Miniatura local de un cómic, con marcador de posición si no hay ninguna.
///
/// Reemplaza a la antigua `CoverImage`, que descargaba portadas de un
/// catálogo remoto. Aquí la imagen ya vive en disco (ver `ThumbnailGenerator`),
/// así que no hace falta ni caché ni estado de carga asíncrono: leerla es
/// prácticamente instantáneo.
struct LocalCoverImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if let url, let uiImage = UIImage(contentsOfFile: url.path) {
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
}
