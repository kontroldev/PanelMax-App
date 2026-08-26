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

    private var totalPages: Int { archive?.pageCount ?? 0 }

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
        ZStack {
            Color.black.ignoresSafeArea()

            if let openingError {
                ContentUnavailableView("No se puede abrir", systemImage: "exclamationmark.triangle",
                                       description: Text(openingError))
                    .foregroundStyle(.white)
            } else if let archive {
                TabView(selection: $currentPage) {
                    ForEach(0..<archive.pageCount, id: \.self) { index in
                        PageView(archive: archive, index: index, fillsWidth: fillsWidth)
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

            if showsControls { controls }
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

    private var controls: some View {
        VStack {
            HStack {
                Button {
                    if saveProgress(reportErrors: true) { dismiss() }
                } label: {
                    Label(issue?.series?.title ?? importedFile?.displayName ?? "Volver",
                          systemImage: "chevron.left")
                        .font(.footnote)
                }

                Spacer()

                Text("Pág. \(currentPage + 1) / \(max(totalPages, 1))")
                    .font(.footnote)
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

            HStack {
                Button {
                    withAnimation { fillsWidth.toggle() }
                } label: {
                    Label(fillsWidth ? "Página completa" : "Ajustar ancho",
                          systemImage: fillsWidth ? "arrow.down.right.and.arrow.up.left" : "arrow.left.and.right")
                        .font(.footnote)
                        .foregroundStyle(fillsWidth ? Theme.premium : .white)
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

    // MARK: - Acciones

    private func open() async {
        guard let file = importedFile else {
            openingError = "Este número no tiene ningún archivo importado. Impórtalo desde Perfil ▸ Importar cómic."
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

            let opened = try await Task.detached(priority: .userInitiated) {
                try ComicArchiveFactory.open(url: url)
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
                try CollectionStore(context: context)
                    .saveProgress(for: issue, page: currentPage, totalPages: totalPages)
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

/// Una página, con zoom por pellizco.
///
/// El zoom SE MANTIENE al soltar los dedos. En la primera versión volvía a 1 en
/// `onEnded`, lo que hacía imposible detenerse en una viñeta: justo lo que se
/// espera de un lector de cómics. Al ampliar se habilita el arrastre y se le da
/// prioridad sobre el paso de página del `TabView`.
private struct PageView: View {
    let archive: any ComicArchive
    let index: Int
    let fillsWidth: Bool

    private static let maximumZoom: CGFloat = 5
    private static let doubleTapZoom: CGFloat = 2.5

    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var loadFailed = false
    @State private var loadAttempt = 0

    /// Estado transitorio del gesto: se descarta solo al levantar los dedos.
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private var effectiveZoom: CGFloat {
        min(max(zoom * pinch, 1), Self.maximumZoom)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fillsWidth ? .fill : .fit)
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
                        .accessibilityLabel("Página \(index + 1)")
                        .accessibilityHint("Pellizca para ampliar. Toca dos veces para alternar el zoom.")
                } else if loadFailed {
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
        .task(id: loadAttempt) {
            loadFailed = false
            image = await archive.page(at: index)
            loadFailed = image == nil
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

    /// Impide que la página se arrastre fuera de la pantalla y deje un hueco negro.
    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let limitX = max((size.width * zoom - size.width) / 2, 0)
        let limitY = max((size.height * zoom - size.height) / 2, 0)
        return CGSize(width: min(max(proposed.width, -limitX), limitX),
                      height: min(max(proposed.height, -limitY), limitY))
    }
}
