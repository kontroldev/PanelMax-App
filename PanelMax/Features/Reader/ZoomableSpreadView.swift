import SwiftUI
import UIKit

/// Controla el zoom de un pliego desde fuera del `UIViewRepresentable`.
///
/// El doble toque sigue siendo un `.onTapGesture(count: 2)` de SwiftUI,
/// colocado en el mismo nivel de la jerarquía que antes (sobre el
/// contenido del pliego, por debajo del toque simple que muestra u oculta
/// los mandos en `ReaderView`). Así se conserva la misma relación entre
/// gestos que ya funcionaba: SwiftUI arbitra el simple contra el doble
/// toque igual que lo hacía antes, solo que ahora el doble toque actúa
/// sobre un `UIScrollView` en vez de sobre un `@State` de SwiftUI.
final class SpreadZoomController {
    fileprivate weak var scrollView: UIScrollView?
    private let doubleTapZoom: CGFloat

    init(doubleTapZoom: CGFloat) {
        self.doubleTapZoom = doubleTapZoom
    }

    func toggleZoom() {
        guard let scrollView else { return }
        if scrollView.zoomScale > 1 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            scrollView.setZoomScale(doubleTapZoom, animated: true)
        }
    }
}

/// Zoom y desplazamiento de un pliego mediante `UIScrollView` nativo.
///
/// La versión anterior reimplementaba el pellizco y el arrastre a mano con
/// gestos de SwiftUI (`MagnifyGesture` + `DragGesture`) encima del
/// `TabView(.page)`, arbitrando a mano contra el gesto de pasar página.
/// Eso obligaba a SwiftUI a reevaluar el `body` entero del pliego en cada
/// fotograma del arrastre, lo que se notaba como tirones al desplazarse con
/// zoom en pantallas grandes (iPad Pro).
///
/// `UIScrollView` resuelve el pellizco, el arrastre y el límite de los
/// bordes de forma nativa. Y al anidarlo dentro del `TabView` (que por
/// debajo también es un scroll view) UIKit decide solo quién se queda con
/// el arrastre: si no hay zoom, este scroll view no tiene nada que
/// desplazar y el toque cae al `TabView`; si hay zoom, es este scroll view
/// el que puede moverse y se queda con el gesto. No hace falta ninguna
/// lógica de prioridad manual.
struct ZoomableSpreadView: UIViewRepresentable {
    let images: [UIImage]
    let fillsWidth: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    let zoomController: SpreadZoomController

    static let maximumZoom: CGFloat = 5

    func makeUIView(context: Context) -> SpreadScrollView {
        let scrollView = SpreadScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = Self.maximumZoom
        scrollView.minimumZoomScale = 1
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 0
        stack.distribution = .fillEqually
        scrollView.addSubview(stack)
        scrollView.contentView = stack
        context.coordinator.contentView = stack

        zoomController.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: SpreadScrollView, context: Context) {
        scrollView.isAccessibilityElement = true
        scrollView.accessibilityLabel = accessibilityLabel
        scrollView.accessibilityHint = accessibilityHint
        zoomController.scrollView = scrollView

        guard let stack = context.coordinator.contentView else { return }

        // Las vistas de imagen solo se reconstruyen si cambia el número de
        // páginas del pliego: crear `UIImageView` nuevos en cada actualización
        // de SwiftUI (p. ej. al mostrar u ocultar los mandos) perdería el
        // zoom en curso, porque `UIScrollView` lo guarda en la vista que
        // recibe de `viewForZooming`.
        if stack.arrangedSubviews.count != images.count {
            stack.arrangedSubviews.forEach {
                stack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            for _ in images {
                let imageView = UIImageView()
                imageView.clipsToBounds = true
                stack.addArrangedSubview(imageView)
            }
            // El pliego cambió de forma (una página <-> dos páginas): el
            // tamaño de contenido que tenía calculado ya no vale, así que se
            // fuerza a `SpreadScrollView` a recalcularlo en el próximo paso
            // de layout en vez de esperar a que el tamaño de `bounds` cambie
            // (que, si no ha habido rotación, no va a cambiar).
            scrollView.invalidateContentLayout()
        }

        let imageViews = stack.arrangedSubviews.compactMap { $0 as? UIImageView }
        for (imageView, image) in zip(imageViews, images) {
            imageView.image = image
            imageView.contentMode = (fillsWidth && images.count == 1) ? .scaleAspectFill : .scaleAspectFit
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var contentView: UIStackView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }
    }
}

/// El `UIScrollView` del pliego. Fija el tamaño de su contenido en
/// `layoutSubviews`, no en `updateUIView` del `UIViewRepresentable`: cuando
/// SwiftUI llama a `updateUIView` por primera vez, `bounds` puede estar
/// todavía a cero porque el motor de layout no ha terminado de darle tamaño
/// a la vista. `layoutSubviews` es el único momento en que UIKit garantiza
/// que `bounds` ya es el tamaño real, así que es el sitio correcto para
/// calcular el tamaño del contenido sin arriesgarse a dejarlo en cero para
/// siempre.
final class SpreadScrollView: UIScrollView {
    var contentView: UIStackView?
    private var lastLaidOutSize: CGSize?

    func invalidateContentLayout() {
        lastLaidOutSize = nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let contentView else { return }
        let size = bounds.size
        guard size.width > 0, size.height > 0, size != lastLaidOutSize else { return }
        lastLaidOutSize = size
        zoomScale = 1
        contentView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
    }
}
