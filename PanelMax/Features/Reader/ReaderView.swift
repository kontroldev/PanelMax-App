import SwiftUI
import SwiftData

/// El lector.
///
/// Reglas de diseño: pantalla completa, sin barras, un toque para mostrar los mandos.
/// El progreso se guarda al SALIR, no en cada página: guardar en cada gesto
/// castiga la batería y llena el registro de escrituras de CloudKit.
struct ReaderView: View {

    private let issue: Issue?
    private let importedFile: LocalComicFile?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var archive: (any ComicArchive)?
    @State private var currentPage = 0
    @State private var showsControls = true
    @State private var fillsWidth = false
    @State private var openingError: String?
    @State private var progressError: String?

    /// Preferencia del usuario para la doble página. Se recuerda entre cómics
    /// porque es una decisión de cómo te gusta leer, no de qué estás leyendo.
    @AppStorage("readerPrefersDoublePage") private var prefersDoublePage = true

    /// Estado del deslizador de páginas. Separado de `currentPage` a
    /// propósito: `currentPage` mueve el `TabView` (y por tanto descomprime
    /// páginas) en cada cambio, así que solo se actualiza al soltar el dedo,
    /// no en cada punto intermedio del arrastre.
    @State private var isScrubbing = false
    @State private var scrubPage: Double = 0

    private var store: CollectionStore { CollectionStore(context: context) }

    /// Memoiza el pliego calculado. Sin esto, `layout(for:)` reconstruía un
    /// array del tamaño del cómic entero en CADA evaluación de `body`: cada
    /// cambio de página, cada toque para mostrar u ocultar los mandos, cada
    /// punto del arrastre del deslizador. Ver `SpreadLayoutCache` más abajo.
    @State private var layoutCache = SpreadLayoutCache()

    private var totalPages: Int { archive?.pageCount ?? 0 }

    /// Página mostrada en la cabecera: la del arrastre en curso si se está
    /// arrastrando, o la real si no.
    private var displayedPage: Int {
        isScrubbing ? Int(scrubPage.rounded()) : currentPage
    }

    /// Si la ventana da sitio para dos páginas, con independencia de que el
    /// usuario lo tenga activado.
    ///
    /// Se decide a partir del tamaño real de la ventana, no de la orientación
    /// del dispositivo: en Split View o Stage Manager un iPad en horizontal
    /// puede darle a la app una columna estrecha, y ahí dos páginas juntas se
    /// verían minúsculas. Medir el ancho disponible cubre los dos casos con
    /// una sola regla.
    private func fitsDoublePage(in size: CGSize) -> Bool {
        size.width > size.height && size.width >= 700
    }

    /// Si de hecho se están enseñando dos páginas ahora mismo.
    private func usesDoublePage(in size: CGSize) -> Bool {
        prefersDoublePage && fitsDoublePage(in: size)
    }

    private func layout(for size: CGSize) -> SpreadLayout {
        layoutCache.layout(pageCount: totalPages, isDouble: usesDoublePage(in: size))
    }

    /// Selección del `TabView` en pliegos, derivada de la página actual.
    ///
    /// Guardar la PÁGINA y derivar el pliego (en vez de al revés) es lo que
    /// hace que girar el iPad conserve la posición: la página no cambia, solo
    /// cambia el pliego que la contiene.
    private func spreadSelection(for layout: SpreadLayout) -> Binding<Int> {
        Binding(
            get: { layout.spreadIndex(containing: currentPage) },
            set: { currentPage = layout.firstPage(ofSpreadAt: $0) }
        )
    }

    init(issue: Issue) {
        self.issue = issue
        self.importedFile = issue.file
    }

    /// Los archivos importados también se pueden leer sin vincularlos antes a
    /// una ficha del catálogo.
    init(file: LocalComicFile) {
        self.issue = file.issue
        self.importedFile = file
    }

    var body: some View {
        GeometryReader { geometry in
            let spreadLayout = layout(for: geometry.size)

            ZStack {
                Color.black.ignoresSafeArea()

                if let openingError {
                    ContentUnavailableView("No se puede abrir", systemImage: "exclamationmark.triangle",
                                           description: Text(openingError))
                        .foregroundStyle(.white)
                } else if let archive {
                    TabView(selection: spreadSelection(for: spreadLayout)) {
                        ForEach(Array(spreadLayout.spreads.enumerated()), id: \.offset) { index, spread in
                            SpreadView(archive: archive,
                                       spread: spread,
                                       // "Rellenar ancho" recorta los márgenes de un
                                       // escaneo, pero en un pliego de dos páginas
                                       // recortaría justo por el lomo, que es donde
                                       // están las viñetas a doble página.
                                       fillsWidth: fillsWidth && spread.pages.count == 1)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() }
                    }
                } else {
                    ProgressView().tint(.white)
                }

                if showsControls {
                    controls(isDouble: usesDoublePage(in: geometry.size),
                             fitsDouble: fitsDoublePage(in: geometry.size))
                }
            }
        }
        .statusBarHidden(!showsControls)
        .navigationBarBackButtonHidden()
        .task { await open() }
        .onDisappear { saveProgress(reportErrors: false) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveProgress(reportErrors: false) }
        }
        .alert("No se ha podido guardar el progreso", isPresented: Binding(
            get: { progressError != nil },
            set: { visible in if !visible { progressError = nil } }
        )) {
            Button("De acuerdo", role: .cancel) {}
        } message: {
            Text(progressError ?? "")
        }
    }

    // MARK: - Mandos

    private func controls(isDouble: Bool, fitsDouble: Bool) -> some View {
        VStack {
            HStack {
                Button {
                    if saveProgress(reportErrors: true) { dismiss() }
                } label: {
                    Label(issue?.series?.title ?? importedFile?.displayName ?? "Volver",
                          systemImage: "chevron.left")
                        .font(.footnote)
                }
                // El texto del botón es el título del cómic, así que sin
                // etiqueta VoiceOver lo lee como si fuera un rótulo y no se
                // entiende que sirva para salir del lector.
                .accessibilityLabel("Cerrar el lector")
                .accessibilityHint("Guarda tu progreso y vuelve atrás")

                Spacer()

                Text("Pág. \(displayedPage + 1) / \(max(totalPages, 1))")
                    .font(.footnote)
                    .accessibilityLabel("Página \(displayedPage + 1) de \(max(totalPages, 1))")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .panelGlass(cornerRadius: 18,
                        tint: .white.opacity(0.18),
                        fallbackFill: .black.opacity(0.55),
                        strokeColor: .white.opacity(0.18))
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()

            if totalPages > 1 {
                pageSlider
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            HStack(spacing: 22) {
                Button {
                    withAnimation { fillsWidth.toggle() }
                } label: {
                    Label(fillsWidth ? "Página completa" : "Ajustar ancho",
                          systemImage: fillsWidth ? "arrow.down.right.and.arrow.up.left" : "arrow.left.and.right")
                        .font(.footnote)
                        .foregroundStyle(fillsWidth ? Theme.premium : .white)
                }
                .disabled(isDouble)
                .opacity(isDouble ? 0.4 : 1)
                .accessibilityLabel("Ajuste de la página")
                .accessibilityValue(fillsWidth ? "Rellenando el ancho" : "Página completa")
                .accessibilityHint(isDouble
                                   ? "No disponible en doble página"
                                   : "Alterna entre ver la página entera o rellenar el ancho")

                // El interruptor solo aparece donde la doble página es
                // posible. En un iPhone en vertical sería un mando que no
                // hace nada visible, y eso confunde más que ayudar.
                if fitsDouble && totalPages > 1 {
                    Button {
                        withAnimation { prefersDoublePage.toggle() }
                    } label: {
                        Label(prefersDoublePage ? "Doble página" : "Página única",
                              systemImage: prefersDoublePage ? "book.pages" : "doc")
                            .font(.footnote)
                            .foregroundStyle(prefersDoublePage ? Theme.premium : .white)
                    }
                    .accessibilityLabel("Modo de página")
                    .accessibilityValue(prefersDoublePage ? "Doble página" : "Página única")
                    .accessibilityHint("Alterna entre ver una página o dos a la vez.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .panelGlass(cornerRadius: 18,
                        tint: .white.opacity(0.18),
                        isInteractive: true,
                        fallbackFill: .black.opacity(0.55),
                        strokeColor: .white.opacity(0.18))
            .padding(.bottom, 14)
        }
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [.black.opacity(0.75), .clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
        .transition(.opacity)
    }

    /// Deslizador para saltar directamente a una página. En un CBZ de ciento
    /// ochenta páginas, pasar de una en una es inusable.
    private var pageSlider: some View {
        Slider(
            value: Binding(
                get: { isScrubbing ? scrubPage : Double(currentPage) },
                set: { newValue in
                    isScrubbing = true
                    scrubPage = newValue
                }
            ),
            in: 0...Double(max(totalPages - 1, 0)),
            step: 1,
            onEditingChanged: { editing in
                if !editing {
                    currentPage = Int(scrubPage.rounded())
                    isScrubbing = false
                }
            }
        )
        .tint(.white)
        .accessibilityLabel("Página")
        .accessibilityValue("\(displayedPage + 1) de \(max(totalPages, 1))")
    }

    // MARK: - Acciones

    private func open() async {
        guard let file = importedFile else {
            openingError = "Este número no tiene ningún archivo importado. Impórtalo desde Biblioteca ▸ Importar cómic."
            return
        }

        do {
            let url = try file.resolveURL()

            // Si iOS dio el marcador por obsoleto se regenera AQUÍ, dentro del
            // alcance de seguridad. Antes se lanzaba `fileUnavailable` y el
            // cómic quedaba inaccesible de forma permanente.
            if file.needsBookmarkRefresh {
                let didAccess = url.startAccessingSecurityScopedResource()
                file.refreshBookmarkIfNeeded(from: url)
                if didAccess { url.stopAccessingSecurityScopedResource() }
                try? context.save()
            }

            // Se calcula AQUÍ, no dentro de PDFArchive: esta función corre en
            // el actor principal (herencia del aislamiento por defecto del
            // proyecto), que es el único sitio desde el que `UIScreen` puede
            // leerse. `ComicArchiveFactory.open` es `nonisolated` a propósito
            // para poder llamarse desde el `Task.detached` de abajo, así que
            // el valor tiene que entrar ya calculado, no calcularse dentro.
            let pdfTargetWidth = PDFArchive.preferredRenderWidth()

            let opened = try await Task.detached(priority: .userInitiated) {
                try ComicArchiveFactory.open(url: url, pdfTargetWidth: pdfTargetWidth)
            }.value
            guard !Task.isCancelled else { return }
            archive = opened
            // Los registros anteriores a la biblioteca propia solo tenían progreso
            // en Issue; se conserva como compatibilidad al abrirlos por primera vez.
            let savedPage = file.lastReadAt == nil
                ? (issue?.progress?.currentPage ?? file.currentPage)
                : file.currentPage
            currentPage = min(max(savedPage, 0), max(opened.pageCount - 1, 0))
        } catch {
            openingError = error.localizedDescription
        }
    }

    @discardableResult
    private func saveProgress(reportErrors: Bool) -> Bool {
        guard totalPages > 0, let file = importedFile else { return true }

        do {
            file.updateProgress(page: currentPage, totalPages: totalPages)
            if let issue {
                // `saveProgress` guarda todo el contexto, incluido el progreso
                // propio del archivo actualizado justo arriba.
                try store.saveProgress(for: issue, page: currentPage, totalPages: totalPages)
            } else {
                try context.save()
            }
            return true
        } catch {
            context.rollback()
            if reportErrors { progressError = error.localizedDescription }
            return false
        }
    }
}

// MARK: - Caché del pliego

/// Memoiza el último `SpreadLayout` calculado, con su clave `(pageCount,
/// isDouble)`. Guardada en `@State` solo para conservar la MISMA instancia
/// entre evaluaciones de `body` — no para que SwiftUI observe sus mutaciones:
/// es una clase normal, no `@Observable`, así que mutarla dentro de `body` es
/// seguro y no invalida la vista por sí sola.
///
/// `SpreadLayout(pageCount:isDouble:)` es O(páginas): sin esta caché se
/// reconstruía en cada cambio de página, cada toque para mostrar los mandos
/// y cada punto del arrastre del deslizador, aunque ni el número de páginas
/// ni el modo doble hubieran cambiado.
private final class SpreadLayoutCache {
    private var pageCount = -1
    private var isDouble = false
    private var cached = SpreadLayout(pageCount: 0, isDouble: false)

    func layout(pageCount: Int, isDouble: Bool) -> SpreadLayout {
        guard pageCount != self.pageCount || isDouble != self.isDouble else { return cached }
        self.pageCount = pageCount
        self.isDouble = isDouble
        cached = SpreadLayout(pageCount: pageCount, isDouble: isDouble)
        return cached
    }
}

/// Un pliego: una página, o dos lado a lado en iPad apaisado.
///
/// El zoom SE MANTIENE al soltar los dedos. En la primera versión volvía a 1 en
/// `onEnded`, lo que hacía imposible detenerse en una viñeta: justo lo que se
/// espera de un lector de cómics. Al ampliar se habilita el arrastre y se le da
/// prioridad sobre el paso de página del `TabView`.
///
/// El zoom y el arrastre se aplican al pliego ENTERO, no a cada página por
/// separado. Si cada página tuviera su propio zoom, ampliar una viñeta que
/// cruza el lomo desencajaría las dos mitades.
private struct SpreadView: View {
    let archive: any ComicArchive
    let spread: SpreadLayout.Spread
    let fillsWidth: Bool

    private static let maximumZoom: CGFloat = 5
    private static let doubleTapZoom: CGFloat = 2.5

    @State private var images: [Int: UIImage] = [:]
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var failedPages: Set<Int> = []
    @State private var loadAttempt = 0

    /// Estado transitorio del gesto: se descarta solo al levantar los dedos.
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private var effectiveZoom: CGFloat {
        min(max(zoom * pinch, 1), Self.maximumZoom)
    }

    /// Se pinta el pliego en cuanto TODAS sus páginas están listas. Enseñar
    /// media doble página mientras carga la otra mitad produce un salto de
    /// composición muy visible.
    private var isReady: Bool {
        spread.pages.allSatisfy { images[$0] != nil }
    }

    private var hasFailed: Bool {
        !failedPages.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isReady {
                    HStack(spacing: 0) {
                        ForEach(spread.pages, id: \.self) { page in
                            if let image = images[page] {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: fillsWidth ? .fill : .fit)
                            }
                        }
                    }
                    .scaleEffect(effectiveZoom)
                    .offset(x: offset.width + drag.width,
                            y: offset.height + drag.height)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .gesture(magnification(in: geometry.size))
                    // Solo se roba el arrastre al TabView cuando hay zoom;
                    // sin ampliar, deslizar sigue pasando de página.
                    .highPriorityGesture(pan(in: geometry.size), including: zoom > 1 ? .all : .subviews)
                    .onTapGesture(count: 2) { toggleZoom(in: geometry.size) }
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint("Pellizca para ampliar. Toca dos veces para alternar el zoom.")
                } else if hasFailed {
                    VStack(spacing: 12) {
                        Label("Página no disponible", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Button("Reintentar") { loadAttempt += 1 }
                            .buttonStyle(.bordered)
                    }
                    .foregroundStyle(.white)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    ProgressView().tint(.white)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .task(id: taskID) {
            failedPages = []
            for page in spread.pages {
                let image = await archive.page(at: page)
                guard !Task.isCancelled else { return }
                if let image {
                    images[page] = image
                } else {
                    failedPages.insert(page)
                }
            }
        }
    }

    /// Recarga cuando cambia el pliego (al rotar el iPad, una misma vista puede
    /// pasar de enseñar una página a enseñar dos) o cuando se pulsa Reintentar.
    private var taskID: String {
        "\(spread.pages.map(String.init).joined(separator: "-"))#\(loadAttempt)"
    }

    private var accessibilityLabel: String {
        switch spread {
        case .single(let page):
            return "Página \(page + 1)"
        case .double(let left, let right):
            return "Páginas \(left + 1) y \(right + 1)"
        }
    }

    // MARK: - Gestos

    private func magnification(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                zoom = min(max(zoom * value.magnification, 1), Self.maximumZoom)
                if zoom == 1 {
                    withAnimation(.snappy) { offset = .zero }
                } else {
                    offset = clamped(offset, in: size)
                }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in
                state = zoom > 1 ? value.translation : .zero
            }
            .onEnded { value in
                guard zoom > 1 else { return }
                offset = clamped(CGSize(width: offset.width + value.translation.width,
                                        height: offset.height + value.translation.height),
                                 in: size)
            }
    }

    private func toggleZoom(in size: CGSize) {
        withAnimation(.snappy(duration: 0.25)) {
            if zoom > 1 {
                zoom = 1
                offset = .zero
            } else {
                zoom = Self.doubleTapZoom
            }
        }
    }

    /// Impide que el pliego se arrastre fuera de la pantalla y deje un hueco negro.
    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let limitX = max((size.width * zoom - size.width) / 2, 0)
        let limitY = max((size.height * zoom - size.height) / 2, 0)
        return CGSize(width: min(max(proposed.width, -limitX), limitX),
                      height: min(max(proposed.height, -limitY), limitY))
    }
}
