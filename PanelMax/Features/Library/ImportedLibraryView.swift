import SwiftUI
import SwiftData

/// Biblioteca de copias privadas importadas por el usuario.
///
/// Un archivo no necesita estar emparejado con el catálogo para abrirse. Al
/// eliminarlo, primero se mueve a una papelera interna, después se guarda la
/// eliminación en SwiftData y solo entonces se borra físicamente. Si falla el
/// guardado, el movimiento se deshace y el cómic continúa disponible.
struct ImportedLibraryView: View {

    @Query(sort: \LocalComicFile.importedAt, order: .reverse)
    private var files: [LocalComicFile]

    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if files.isEmpty {
                ContentUnavailableView(
                    "No hay cómics importados",
                    systemImage: "books.vertical",
                    description: Text("Importa un CBZ o PDF desde Perfil para leerlo aquí.")
                )
            } else {
                List {
                    ForEach(files) { file in
                        NavigationLink {
                            ReaderView(file: file)
                        } label: {
                            ImportedComicRow(file: file)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Cómics importados")
        .toolbar {
            if !files.isEmpty { EditButton() }
        }
        .task {
            PendingComicDeletion.cleanup(
                protecting: Set(files.compactMap(\.localFilename))
            )
        }
        .alert("No se ha podido eliminar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { visible in if !visible { errorMessage = nil } }
        )) {
            Button("De acuerdo", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func delete(at offsets: IndexSet) {
        let selected = offsets.compactMap { files.indices.contains($0) ? files[$0] : nil }
        guard !selected.isEmpty else { return }

        var staged: [PendingComicDeletion] = []
        do {
            // Se preparan todos antes de tocar SwiftData: borrar varias filas es
            // una única operación y no puede quedar a medias.
            for file in selected {
                if let deletion = try PendingComicDeletion.stage(file) {
                    staged.append(deletion)
                }
            }

            selected.forEach(context.delete)
            try context.save()

            for deletion in staged {
                do {
                    try deletion.finish()
                } catch {
                    // El registro ya no existe. La copia queda en una carpeta de
                    // limpieza y se reintentará al volver a abrir esta pantalla.
                    errorMessage = "El cómic se quitó de la biblioteca, pero su copia interna no se ha podido limpiar todavía. PanelMax volverá a intentarlo."
                }
            }
        } catch {
            context.rollback()
            var restorationFailed = false
            for deletion in staged.reversed() {
                do {
                    try deletion.restore()
                } catch {
                    restorationFailed = true
                }
            }
            errorMessage = restorationFailed
                ? "\(error.localizedDescription) Las copias que no pudieron volver a su ubicación se han conservado en la carpeta de recuperación y no se borrarán."
                : error.localizedDescription
        }
    }
}

private struct ImportedComicRow: View {
    let file: LocalComicFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.localFilename?.lowercased().hasSuffix(".pdf") == true
                  ? "doc.richtext.fill"
                  : "books.vertical.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)

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
        .accessibilityElement(children: .combine)
    }

    private var format: String {
        guard let filename = file.localFilename else { return "ARCHIVO" }
        let value = (filename as NSString).pathExtension.uppercased()
        return value == "ZIP" ? "CBZ" : value
    }
}

/// Movimiento reversible de una copia privada. Nunca se toca el archivo externo
/// de un bookmark: PanelMax solo es dueño de lo que copió a `Documents/Comics`.
private struct PendingComicDeletion {
    let original: URL
    let pending: URL

    static var directory: URL {
        LocalComicFile.comicsDirectory
            .appending(path: ".PendingDeletion", directoryHint: .isDirectory)
    }

    static func stage(_ file: LocalComicFile) throws -> PendingComicDeletion? {
        let original: URL
        do {
            guard let localURL = try file.localCopyURL() else { return nil }
            original = localURL
        } catch {
            // Un nombre persistido manipulado se puede quitar de la biblioteca,
            // pero por seguridad jamás se usa para una operación de archivos.
            return nil
        }

        guard FileManager.default.fileExists(atPath: original.path) else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recoveryDirectory = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: false)
        let pending = recoveryDirectory.appending(path: original.lastPathComponent, directoryHint: .notDirectory)
        try FileManager.default.moveItem(at: original, to: pending)
        return PendingComicDeletion(original: original, pending: pending)
    }

    func restore() throws {
        guard FileManager.default.fileExists(atPath: pending.path) else { return }
        try FileManager.default.moveItem(at: pending, to: original)
        try? FileManager.default.removeItem(at: pending.deletingLastPathComponent())
    }

    func finish() throws {
        guard FileManager.default.fileExists(atPath: pending.path) else { return }
        try FileManager.default.removeItem(at: pending.deletingLastPathComponent())
    }

    /// Limpia eliminaciones confirmadas y recupera automáticamente una copia si
    /// el registro SwiftData volvió tras un fallo de guardado. El nombre original
    /// se conserva como nombre del archivo dentro de cada carpeta de recuperación.
    static func cleanup(protecting filenames: Set<String>) {
        guard let recoveryDirectories = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }

        for recoveryDirectory in recoveryDirectories {
            guard let pendingFiles = try? FileManager.default.contentsOfDirectory(
                at: recoveryDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            guard let pending = pendingFiles.first else {
                try? FileManager.default.removeItem(at: recoveryDirectory)
                continue
            }

            let originalFilename = pending.lastPathComponent
            if filenames.contains(originalFilename) {
                // Hay registro: si su ruta está vacía, completamos la restauración.
                if let original = try? LocalComicFile.storageURL(for: originalFilename),
                   !FileManager.default.fileExists(atPath: original.path) {
                    try? FileManager.default.moveItem(at: pending, to: original)
                    if !FileManager.default.fileExists(atPath: pending.path) {
                        try? FileManager.default.removeItem(at: recoveryDirectory)
                    }
                }
            } else {
                // Ya no hay metadatos que apunten a esta copia: la eliminación se
                // guardó correctamente y es seguro completar el borrado físico.
                try? FileManager.default.removeItem(at: recoveryDirectory)
            }
        }
    }
}

#Preview {
    NavigationStack { ImportedLibraryView() }
        .modelContainer(PreviewData.container)
}
