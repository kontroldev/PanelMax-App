import SwiftUI
import SwiftData

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
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 10)]

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

    @ViewBuilder
    private var progressLine: some View {
        if let completion = series.completion {
            let missing = series.missingNumbers
            VStack(alignment: .leading, spacing: 5) {
                Theme.sectionLabel("Tu progreso")
                ProgressView(value: completion).tint(Theme.accent)
                Text("\(series.allOwnedIssues.count) de \(series.totalIssues) números")
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
        VStack(alignment: .leading, spacing: 8) {
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

            if sortedIssues.isEmpty {
                ContentUnavailableView {
                    Label("Todavía no hay números", systemImage: "books.vertical")
                } description: {
                    Text("Añade los que tengas, o un rango entero de una vez.")
                } actions: {
                    Button("Añadir números") { showsAddIssues = true }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(sortedIssues) { issue in
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
                write { try CollectionStore(context: context).setState(state, for: issue) }
            } label: {
                Label(state.label, systemImage: state.systemImage)
            }
            .disabled(issue.entry?.state == state)
        }

        Divider()

        ForEach(CollectionFormat.allCases) { format in
            Button {
                write { try CollectionStore(context: context).setFormat(format, for: issue) }
            } label: {
                Label(format.label, systemImage: format == .physical ? "book.closed" : "iphone")
            }
            .disabled(issue.entry?.format == format)
        }

        Divider()

        if let file = issue.file {
            Button {
                presentedFile = file
            } label: {
                Label("Leer", systemImage: "book.fill")
            }
            Button {
                write { try CollectionStore(context: context).unlink(file) }
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
            write { try CollectionStore(context: context).remove(issue) }
        } label: {
            Label("Quitar de la colección", systemImage: "trash")
        }
    }

    // MARK: - Acciones

    private func deleteSeries() {
        do {
            try CollectionStore(context: context).deleteSeries(series)
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
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

    private var accessibilityValue: String {
        switch state {
        case .owned: "en la colección"
        case .read:  "leído"
        case .wanted: "lo quieres"
        case .none:  "sin estado"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(issue.number)
                .font(.subheadline.weight(.semibold))
            if issue.isReadable {
                Image(systemName: "book.fill").font(.system(size: 9))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
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
