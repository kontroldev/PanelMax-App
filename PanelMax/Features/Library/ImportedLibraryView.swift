import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Biblioteca de copias privadas importadas por el usuario.
///
/// Es la otra mitad del producto además de la colección catalogada a mano:
/// aquí se importa, se lee y se borra. Antes vivía escondida bajo un
/// `NavigationLink` en Perfil; al ser una app sin catálogo, importar es una
/// de las dos cosas que hace la app, así que tiene pestaña propia.
///
/// La vista solo orquesta estado de interfaz (qué se enseña, cuándo se
/// deshabilita un botón) y delega en `LibraryStore` cómo se copian, guardan y
/// borran los archivos — ver `LibraryStore` para el mecanismo de papelera
/// interna reversible.
struct ImportedLibraryView: View {

    @Query(sort: \LocalComicFile.importedAt, order: .reverse)
    private var files: [LocalComicFile]

    @Environment(\.modelContext) private var context

    @State private var showsImporter = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var skippedMessage: String?
    @State private var presentedFile: LocalComicFile?
    @State private var query = ""

    private var store: LibraryStore { LibraryStore(context: context) }

    private var visibleFiles: [LocalComicFile] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return files }
        return files.filter { $0.displayName.lowercased().contains(normalized) }
    }

    var body: some View {
        // Se calcula UNA vez: mientras se busca, `visibleFiles` filtra
        // `files` entero, y antes se leía dos veces por render (`.isEmpty`
        // arriba y el `ForEach` de la lista) — el mismo filtrado repetido
        // para pintar lo mismo.
        let visible = visibleFiles
        NavigationStack {
            Group {
                if files.isEmpty {
                    ContentUnavailableView {
                        Label("No hay cómics importados", systemImage: "books.vertical")
                    } description: {
                        Text("Importa un CBZ o PDF desde tu dispositivo para leerlo aquí.")
                    } actions: {
                        Button("Importar cómic") { importComic() }
                    }
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(visible) { file in
                            Button {
                                presentedFile = file
                            } label: {
                                ImportedComicRow(file: file)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $query, prompt: "Buscar por nombre")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !files.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        importComic()
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .disabled(isImporting)
                    .accessibilityLabel("Importar cómic")
                }
            }
            .fileImporter(isPresented: $showsImporter,
                          allowedContentTypes: Self.importableTypes,
                          allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            .fullScreenCover(item: $presentedFile) { file in
                ReaderView(file: file)
            }
            .task {
                PendingComicDeletion.cleanup(
                    protecting: Set(files.compactMap(\.localFilename))
                )
            }
            .alert("No se ha podido completar", isPresented: Binding(
                get: { errorMessage != nil },
                set: { visible in if !visible { errorMessage = nil } }
            )) {
                Button("De acuerdo", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Importación completada", isPresented: Binding(
                get: { skippedMessage != nil },
                set: { visible in if !visible { skippedMessage = nil } }
            )) {
                Button("De acuerdo", role: .cancel) {}
            } message: {
                Text(skippedMessage ?? "")
            }
        }
    }

    // MARK: - Importación

    static let importableTypes: [UTType] = {
        var types: [UTType] = [.pdf, .zip]
        if let cbz = UTType(filenameExtension: "cbz") { types.append(cbz) }
        return types
    }()

    private func importComic() {
        showsImporter = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            // Cerrar el selector no es un fallo que haya que enseñar al usuario.
            if (error as NSError).code != NSUserCancelledError {
                errorMessage = error.localizedDescription
            }

        case .success(let urls):
            guard !urls.isEmpty, !isImporting else { return }

            guard store.beginImporting() else {
                errorMessage = "Ya hay otra importación en curso. Espera a que termine antes de añadir más cómics."
                return
            }

            isImporting = true
            let importer = store

            Task {
                defer {
                    isImporting = false
                    importer.endImporting()
                }
                do {
                    let skipped = try await importer.importFiles(from: urls)
                    if !skipped.isEmpty {
                        skippedMessage = Self.skippedMessage(for: skipped)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Mensaje para los archivos que se omitieron aunque el resto del lote
    /// se haya importado con éxito (ver `LibraryStore.importFiles`).
    private static func skippedMessage(for skipped: [SkippedComicImport]) -> String {
        let intro = skipped.count == 1
            ? "Se omitió 1 archivo porque no era compatible:"
            : "Se omitieron \(skipped.count) archivos porque no eran compatibles:"
        let detail = skipped.prefix(5).map { "• \($0.name)" }.joined(separator: "\n")
        let rest = skipped.count > 5 ? "\n… y \(skipped.count - 5) más." : ""
        return "\(intro)\n\(detail)\(rest)\n\nEl resto de los cómics se ha importado correctamente."
    }

    // MARK: - Borrado

    private func delete(at offsets: IndexSet) {
        let selected = offsets.compactMap { visibleFiles.indices.contains($0) ? visibleFiles[$0] : nil }
        do {
            try store.delete(selected)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ImportedComicRow: View {
    let file: LocalComicFile

    var body: some View {
        HStack(spacing: 12) {
            LocalCoverImage(url: file.thumbnailURL, width: 40, cornerRadius: 6)
                .accessibilityHidden(true) // decorativa: el nombre ya se anuncia

            VStack(alignment: .leading, spacing: 4) {
                Text(file.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Text(format)
                    Text("·")
                    Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
                    if let position = file.progressDescription {
                        Text("·")
                        Text(file.isFinished ? "Terminado" : position)
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)

                if file.lastReadAt != nil, file.pageCount > 0 {
                    ProgressView(value: file.progressFraction)
                        .tint(file.isFinished ? .green : Theme.accent)
                }
            }
        }
        .padding(.vertical, 3)
        // Con `.combine` se leían los separadores «·» sueltos y la barra de
        // progreso como un porcentaje aparte. Con `.ignore` se controla la
        // frase completa: nombre, y después formato, tamaño y estado.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(file.displayName)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = [format, ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)]
        if file.isFinished {
            parts.append("Terminado")
        } else if let position = file.progressDescription {
            parts.append(position)
        } else {
            parts.append("Sin empezar")
        }
        return parts.joined(separator: ", ")
    }

    private var format: String {
        guard let filename = file.localFilename else { return "ARCHIVO" }
        let value = (filename as NSString).pathExtension.uppercased()
        return value == "ZIP" ? "CBZ" : value
    }
}

#Preview {
    ImportedLibraryView()
        .modelContainer(PreviewData.container)
}
