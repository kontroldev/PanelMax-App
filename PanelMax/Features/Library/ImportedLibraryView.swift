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
/// Al eliminar un archivo, primero se mueve a una papelera interna, después
/// se guarda la eliminación en SwiftData y solo entonces se borra
/// físicamente. Si falla el guardado, el movimiento se deshace y el cómic
/// continúa disponible.
struct ImportedLibraryView: View {

    @Query(sort: \LocalComicFile.importedAt, order: .reverse)
    private var files: [LocalComicFile]

    @Environment(\.modelContext) private var context

    @State private var showsImporter = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var query = ""

    private var visibleFiles: [LocalComicFile] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return files }
        return files.filter { $0.displayName.lowercased().contains(normalized) }
    }

    var body: some View {
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
                } else if visibleFiles.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(visibleFiles) { file in
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

    /// Copia el archivo dentro del contenedor de la app y genera su miniatura.
    ///
    /// Copiar en vez de guardar solo el marcador evita el problema clásico:
    /// el usuario borra el archivo de iCloud Drive y el cómic deja de abrirse.
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            // Cerrar el selector no es un fallo que haya que enseñar al usuario.
            if (error as NSError).code != NSUserCancelledError {
                errorMessage = error.localizedDescription
            }

        case .success(let urls):
            guard !urls.isEmpty, !isImporting else { return }

            guard ComicImportCoordinator.begin() else {
                errorMessage = "Ya hay otra importación en curso. Espera a que termine antes de añadir más cómics."
                return
            }

            isImporting = true
            let container = context.container

            Task {
                defer {
                    isImporting = false
                    ComicImportCoordinator.end()
                }
                do {
                    let drafts = try await Task.detached(priority: .userInitiated) {
                        try ComicImportBatch.copy(urls)
                    }.value

                    do {
                        // Un contexto separado hace que un fallo del lote no revierta
                        // cambios no relacionados de la interfaz principal.
                        let importContext = ModelContext(container)
                        for draft in drafts {
                            let file = LocalComicFile(displayName: draft.displayName,
                                                      localFilename: draft.filename)
                            file.fileSize = draft.fileSize
                            file.pageCount = draft.pageCount

                            // La portada sale de la propia página 1. Si falla,
                            // el cómic se importa igual, solo que sin miniatura.
                            if let data = await ThumbnailGenerator.makeThumbnail(for: draft.url),
                               let thumbnailFilename = try? ThumbnailStore.save(data) {
                                file.thumbnailFilename = thumbnailFilename
                            }

                            importContext.insert(file)
                        }
                        try importContext.save()
                    } catch {
                        guard ComicImportBatch.rollback(drafts) else {
                            throw ComicImportError.cleanupFailed
                        }
                        throw ComicImportError.persistence(error.localizedDescription)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Borrado

    private func delete(at offsets: IndexSet) {
        let selected = offsets.compactMap { visibleFiles.indices.contains($0) ? visibleFiles[$0] : nil }
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

            let thumbnailsToRemove = selected.map(\.thumbnailFilename)
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
            thumbnailsToRemove.forEach(ThumbnailStore.delete)
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
            LocalCoverImage(url: file.thumbnailURL, cornerRadius: 6)
                .frame(width: 40)

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

private struct ImportedComicDraft: Sendable {
    let displayName: String
    let filename: String
    let fileSize: Int64
    let pageCount: Int
    let url: URL
}

private enum ComicImportError: LocalizedError {
    case unavailable(String)
    case unsupported(String)
    case tooLarge(String)
    case batchTooLarge
    case insufficientSpace
    case persistence(String)
    case cleanupFailed

    var errorDescription: String? {
        switch self {
        case .unavailable(let name):
            return "No se puede acceder a «\(name)». Comprueba que siga disponible en Archivos o iCloud Drive."
        case .unsupported(let name):
            return "«\(name)» no es un CBZ o PDF compatible."
        case .tooLarge(let name):
            return "«\(name)» supera el tamaño máximo de 2 GB por archivo."
        case .batchTooLarge:
            return "La selección supera el máximo de 4 GB por importación. Divide los archivos en varios lotes."
        case .insufficientSpace:
            return "No hay espacio libre suficiente para copiar estos cómics de forma segura."
        case .persistence(let detail):
            return "Los archivos se han revertido porque no se pudo guardar la biblioteca: \(detail)"
        case .cleanupFailed:
            return "No se ha podido revertir por completo la copia. PanelMax conservará los archivos temporales para evitar perder datos; comprueba el espacio disponible y vuelve a intentarlo."
        }
    }
}

/// Copia atómica de un lote. Los archivos se validan dentro de una carpeta
/// temporal privada y solo se mueven a su nombre definitivo cuando todos han
/// pasado las comprobaciones. Cualquier error elimina el lote completo.
private enum ComicImportBatch {
    nonisolated static func copy(_ sources: [URL]) throws -> [ImportedComicDraft] {
        let manager = FileManager.default
        // Crea la carpeta y la excluye de la copia de seguridad de iCloud.
        let destination = try LocalComicFile.prepareComicsDirectory()
        let staging = destination.appending(path: ".Importing-\(UUID().uuidString)", directoryHint: .isDirectory)
        let maximumFileSize: Int64 = 2 * 1_024 * 1_024 * 1_024
        let maximumBatchSize: Int64 = 4 * 1_024 * 1_024 * 1_024
        let safetyReserve: Int64 = 200 * 1_024 * 1_024

        cleanupAbandonedStaging(in: destination, using: manager)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        var staged: [(displayName: String, filename: String, size: Int64, pages: Int, url: URL)] = []
        var batchSize: Int64 = 0

        for source in sources {
            let name = source.lastPathComponent
            let ext = source.pathExtension.lowercased()
            guard ["cbz", "zip", "pdf"].contains(ext) else {
                throw ComicImportError.unsupported(name)
            }

            let didAccess = source.startAccessingSecurityScopedResource()
            do {
                var isDirectory: ObjCBool = false
                guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else {
                    throw ComicImportError.unavailable(name)
                }

                let attributes = try manager.attributesOfItem(atPath: source.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      let number = attributes[.size] as? NSNumber else {
                    throw ComicImportError.unavailable(name)
                }

                let size = number.int64Value
                guard size > 0 else { throw ComicImportError.unsupported(name) }
                guard size <= maximumFileSize else { throw ComicImportError.tooLarge(name) }
                let (newBatchSize, overflow) = batchSize.addingReportingOverflow(size)
                guard !overflow, newBatchSize <= maximumBatchSize else {
                    throw ComicImportError.batchTooLarge
                }
                batchSize = newBatchSize

                if let capacity = try destination.resourceValues(
                    forKeys: [.volumeAvailableCapacityForImportantUsageKey]
                ).volumeAvailableCapacityForImportantUsage,
                   capacity < size + safetyReserve {
                    throw ComicImportError.insufficientSpace
                }

                let filename = "\(UUID().uuidString).\(ext)"
                let temporaryURL = staging.appending(path: filename, directoryHint: .notDirectory)
                try manager.copyItem(at: source, to: temporaryURL)

                let pages: Int
                do {
                    pages = try ComicArchiveFactory.pageCount(at: temporaryURL)
                } catch {
                    throw ComicImportError.unsupported(name)
                }

                let rawDisplayName = source.deletingPathExtension().lastPathComponent
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = String((rawDisplayName.isEmpty ? "Cómic importado" : rawDisplayName).prefix(160))
                staged.append((displayName, filename, size, pages, temporaryURL))
            } catch {
                if didAccess { source.stopAccessingSecurityScopedResource() }
                do {
                    try manager.removeItem(at: staging)
                } catch {
                    throw ComicImportError.cleanupFailed
                }
                throw error
            }
            if didAccess { source.stopAccessingSecurityScopedResource() }
        }

        var completed: [ImportedComicDraft] = []
        do {
            for item in staged {
                let finalURL = destination.appending(path: item.filename, directoryHint: .notDirectory)
                try manager.moveItem(at: item.url, to: finalURL)
                completed.append(ImportedComicDraft(displayName: item.displayName,
                                                     filename: item.filename,
                                                     fileSize: item.size,
                                                     pageCount: item.pages,
                                                     url: finalURL))
            }
            try manager.removeItem(at: staging)
            return completed
        } catch {
            let removedFinals = rollback(completed)
            let removedStaging: Bool
            do {
                if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
                removedStaging = true
            } catch {
                removedStaging = false
            }
            guard removedFinals, removedStaging else { throw ComicImportError.cleanupFailed }
            throw error
        }
    }

    @discardableResult
    nonisolated static func rollback(_ drafts: [ImportedComicDraft]) -> Bool {
        var succeeded = true
        for draft in drafts {
            do {
                if FileManager.default.fileExists(atPath: draft.url.path) {
                    try FileManager.default.removeItem(at: draft.url)
                }
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }

    /// Si iOS terminó la app en mitad de una copia, el `defer` no pudo ejecutarse.
    /// Solo se limpian lotes con más de 24 horas para no interferir con otra escena
    /// que esté importando en ese momento.
    nonisolated private static func cleanupAbandonedStaging(in directory: URL,
                                                            using manager: FileManager) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        guard let contents = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in contents where url.lastPathComponent.hasPrefix(".Importing-") {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  let modificationDate = values.contentModificationDate,
                  modificationDate < cutoff else { continue }
            try? manager.removeItem(at: url)
        }
    }
}

#Preview {
    ImportedLibraryView()
        .modelContainer(PreviewData.container)
}
