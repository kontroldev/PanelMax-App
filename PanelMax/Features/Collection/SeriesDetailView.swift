import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

/// Ficha de una serie catalogada a mano.
///
/// Es la pantalla donde se decide todo: aquí es donde el usuario añade
/// números, cambia su estado y vincula el archivo que corresponde a cada
/// uno. El grid de números reutiliza el mismo lenguaje visual que tenía la
/// ficha con catálogo remoto, pero alimentado por `series.issues`, no por
/// una respuesta de red.
struct SeriesDetailView: View {

    let series: Series

    @Environment(\.modelContext) private var context
    @Query(sort: \LocalComicFile.importedAt, order: .reverse) private var allFiles: [LocalComicFile]

    @State private var showsEditSeries = false
    @State private var showsAddIssues = false
    @State private var linkingIssue: Issue?
    @State private var presentedFile: LocalComicFile?
    @State private var confirmsDeletion = false
    @State private var errorMessage: String?
    @State private var relinkTarget: LocalComicFile?
    @State private var showsRelinkImporter = false
    @Environment(\.dismiss) private var dismiss

    /// Portada elegida directamente desde la ficha, sin pasar por "Editar
    /// serie". Mismo atajo que ya tenía el formulario, pero aquí se escribe
    /// al momento: no hay nada más en un formulario pendiente de guardar.
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isPickingCover = false
    @State private var pendingCoverTask: Task<Void, Never>?

    /// El ancho mínimo de cada cuadrito escala con el tamaño de texto: con
    /// Dynamic Type grande, un mínimo fijo de 64 puntos dejaría los números
    /// recortados. El máximo evita además que en un iPad de 13" salgan veinte
    /// columnas de cuadritos diminutos.
    @ScaledMetric(relativeTo: .subheadline) private var chipMinimumWidth: CGFloat = 64

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: chipMinimumWidth, maximum: 110), spacing: 10)]
    }

    private var store: CollectionStore { CollectionStore(context: context) }
    private var libraryStore: LibraryStore { LibraryStore(context: context) }

    private var sortedIssues: [Issue] {
        ComicNumber.sorted(series.issues ?? [], by: \.number)
    }

    /// Archivos importados que todavía no están ligados a ningún número:
    /// son los candidatos para "Vincular archivo".
    private var unlinkedFiles: [LocalComicFile] {
        allFiles.filter { $0.issue == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                progressLine
                numbersGrid
            }
            .padding(16)
        }
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showsEditSeries = true
                    } label: {
                        Label("Editar serie", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        Label("Eliminar serie", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Opciones de la serie")
            }
        }
        .sheet(isPresented: $showsEditSeries) {
            SeriesFormView(series: series)
        }
        .sheet(isPresented: $showsAddIssues) {
            AddIssuesView(series: series)
        }
        .sheet(item: $linkingIssue) { issue in
            LinkFileView(issue: issue, candidates: unlinkedFiles)
        }
        .fullScreenCover(item: $presentedFile) { file in
            ReaderView(file: file)
        }
        .fileImporter(isPresented: $showsRelinkImporter,
                      allowedContentTypes: ImportedLibraryView.importableTypes) { result in
            handleRelink(result)
        }
        // `PhotosPickerItem` solo entrega un identificador: la carga y el
        // guardado en disco son asíncronos, así que van en `.onChange`. A
        // diferencia de `SeriesFormView`, aquí no hay nada pendiente de
        // guardar: se escribe directamente en el modelo en cuanto la imagen
        // está lista.
        .onChange(of: selectedCoverItem) { _, newItem in
            guard let newItem else { return }
            isPickingCover = true
            pendingCoverTask?.cancel()
            let oldCoverFilename = series.coverImageFilename
            pendingCoverTask = Task {
                defer {
                    selectedCoverItem = nil // permite volver a elegir la misma foto más tarde
                    isPickingCover = false
                }
                guard !Task.isCancelled,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      !Task.isCancelled,
                      let image = UIImage(data: data),
                      let resized = ImageResizer.jpegData(from: image),
                      let newFilename = try? ThumbnailStore.save(resized) else {
                    return
                }
                do {
                    try store.updateSeries(series,
                                           title: series.title,
                                           publisher: series.publisher,
                                           startYear: series.startYear,
                                           totalIssues: series.totalIssues,
                                           coverImageFilename: newFilename)
                    // Solo se borra la anterior una vez el guardado ha
                    // tenido éxito, igual que en `SeriesFormView.save()`.
                    ThumbnailStore.delete(oldCoverFilename)
                } catch {
                    context.rollback()
                    ThumbnailStore.delete(newFilename)
                    errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog("¿Eliminar esta serie?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Eliminar serie", role: .destructive) { deleteSeries() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrarán sus números y su progreso. Los cómics importados no se eliminan: seguirán disponibles en Biblioteca.")
        }
        .alert("No se ha podido completar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { visible in if !visible { errorMessage = nil } }
        )) {
            Button("De acuerdo", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Secciones

    private var headerCard: some View {
        // Calculados FUERA del closure de `PhotosPicker`: su `label` lo tipa
        // PhotosUI como `@Sendable`, y `series` no se puede leer directamente
        // desde ahí. Valores locales, capturados por valor, no tienen ese
        // problema (mismo patrón que `SeriesFormView`).
        let coverURL = series.coverImageURL
        let hasCover = series.coverImageFilename != nil
        let accentColor = Theme.accent

        return HStack(alignment: .top, spacing: 12) {
            PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    LocalCoverImage(url: coverURL, width: 88, cornerRadius: 10)
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(accentColor, in: Circle())
                        .offset(x: 4, y: 4)
                }
            }
            .buttonStyle(.plain)
            .disabled(isPickingCover)
            .accessibilityLabel(hasCover ? "Cambiar portada de la serie" : "Añadir portada a la serie")

            VStack(alignment: .leading, spacing: 5) {
                Text(series.title).font(.title3.weight(.bold))
                if !series.publisher.isEmpty {
                    Text(series.publisher).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                if let year = series.startYear {
                    Text(String(year)).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var progressLine: some View {
        if let completion = series.completion {
            // `series.allOwnedIssues` no se cachea (a propósito: es lógica de
            // modelo simple y ya muy probada, ver `CollectionMathTests`), así
            // que cada acceso vuelve a filtrar `series.issues` entero. Antes
            // se leía aquí Y en el texto de abajo — dos pasadas donde basta
            // una — igual que ya se corrigió en `CollectionView` (ver
            // `CollectionSnapshot`, mismo motivo).
            let owned = series.allOwnedIssues
            let missing = series.missingNumbers
            VStack(alignment: .leading, spacing: 5) {
                Theme.sectionLabel("Tu progreso")
                ProgressView(value: completion).tint(Theme.accent)
                Text("\(owned.count) de \(series.totalIssues) números")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                if !missing.isEmpty {
                    Text("Te faltan: \(missing.map(String.init).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var numbersGrid: some View {
        // Se calcula UNA vez: `sortedIssues` ordena `series.issues` entero
        // (ver `ComicNumber.sorted`), y antes se leía dos veces por render
        // (`.isEmpty` y el `ForEach`), así que el orden se recalculaba dos
        // veces para pintar exactamente lo mismo.
        let issues = sortedIssues
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Theme.sectionLabel("Números")
                Spacer()
                Button {
                    showsAddIssues = true
                } label: {
                    Label("Añadir", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                }
            }

            if issues.isEmpty {
                ContentUnavailableView {
                    Label("Todavía no hay números", systemImage: "books.vertical")
                } description: {
                    Text("Añade los que tengas, o un rango entero de una vez.")
                } actions: {
                    Button("Añadir números") { showsAddIssues = true }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(issues) { issue in
                        NumberChip(issue: issue)
                            .contextMenu { menu(for: issue) }
                    }
                }
            }
        }
    }

    /// Menú contextual: cambiar estado, cambiar formato, vincular o
    /// desvincular un archivo, leer, y quitar de la colección.
    @ViewBuilder
    private func menu(for issue: Issue) -> some View {
        ForEach(CollectionState.allCases) { state in
            Button {
                write { try store.setState(state, for: issue) }
            } label: {
                Label(state.label, systemImage: state.systemImage)
            }
            .disabled(issue.entry?.state == state)
        }

        Divider()

        ForEach(CollectionFormat.allCases) { format in
            Button {
                write { try store.setFormat(format, for: issue) }
            } label: {
                Label(format.label, systemImage: format == .physical ? "book.closed" : "iphone")
            }
            .disabled(issue.entry?.format == format)
        }

        Divider()

        if let file = issue.file {
            if file.isAvailable {
                Button {
                    presentedFile = file
                } label: {
                    Label("Leer", systemImage: "book.fill")
                }
            } else {
                Button {
                    relinkTarget = file
                    showsRelinkImporter = true
                } label: {
                    Label("Volver a enlazar archivo", systemImage: "link")
                }
            }
            Button {
                write { try store.unlink(file) }
            } label: {
                Label("Desvincular archivo", systemImage: "link.badge.minus")
            }
        } else if !unlinkedFiles.isEmpty {
            Button {
                linkingIssue = issue
            } label: {
                Label("Vincular archivo importado", systemImage: "link")
            }
        }

        Divider()

        Button(role: .destructive) {
            write { try store.remove(issue) }
        } label: {
            Label("Quitar de la colección", systemImage: "trash")
        }
    }

    // MARK: - Acciones

    private func deleteSeries() {
        // Se lee antes de borrar: una vez borrado el modelo, `series` ya no
        // es válido para leer sus propiedades.
        let coverToRemove = series.coverImageFilename
        do {
            try store.deleteSeries(series)
            ThumbnailStore.delete(coverToRemove)
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    /// El archivo se captura ANTES de que el selector se cierre y ponga
    /// `showsRelinkImporter` a `false`: `relinkTarget` es un estado aparte,
    /// así que sigue disponible cuando llega el resultado.
    private func handleRelink(_ result: Result<URL, Error>) {
        guard let file = relinkTarget else { return }
        relinkTarget = nil

        switch result {
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                errorMessage = error.localizedDescription
            }
        case .success(let url):
            Task {
                do {
                    try await libraryStore.relink(file, to: url)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func write(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

/// Cuadrito de número. El color distingue los tres estados que el modelo
/// admite, no solo «lo tienes / no lo tienes».
private struct NumberChip: View {
    let issue: Issue

    private var state: CollectionState? { issue.entry?.state }

    private var background: Color {
        switch state {
        case .owned, .read: Theme.accent
        case .wanted:       Theme.premiumSoft
        case .none:         Color(.secondarySystemGroupedBackground)
        }
    }

    private var foreground: Color {
        switch state {
        case .owned, .read: .white
        case .wanted:       Theme.premium
        case .none:         .primary
        }
    }

    /// El archivo puede estar vinculado pero haber perdido el acceso
    /// (marcador caducado, copia interna perdida en una restauración de
    /// backup): en ese caso no basta con mirar `issue.isReadable`.
    private var fileIsUnavailable: Bool {
        guard let file = issue.file else { return false }
        return !file.isAvailable
    }

    private var accessibilityValue: String {
        let base: String
        switch state {
        case .owned: base = "en la colección"
        case .read:  base = "leído"
        case .wanted: base = "lo quieres"
        case .none:  base = "sin estado"
        }
        return fileIsUnavailable ? "\(base), archivo no disponible" : base
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(issue.number)
                .font(.subheadline.weight(.semibold))
            if fileIsUnavailable {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
            } else if issue.isReadable {
                Image(systemName: "book.fill").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .panelGlass(cornerRadius: 8,
                    tint: state == nil ? nil : background,
                    isInteractive: true,
                    fallbackFill: background,
                    strokeColor: state == nil ? Theme.hairline : .clear)
        .accessibilityLabel("Número \(issue.number)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Mantén pulsado para cambiar el estado, el formato o vincular un archivo.")
    }
}

#Preview {
    NavigationStack {
        SeriesDetailView(series: Series(catalogID: "preview", title: "Ronin Neón", totalIssues: 12))
    }
    .modelContainer(PreviewData.container)
}
