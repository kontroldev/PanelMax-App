import SwiftUI
import SwiftData
import StoreKit
import UniformTypeIdentifiers

/// Perfil y ajustes.
///
/// Aquí viven tres cosas que App Review mira: el estado de la suscripción con su
/// botón de gestión, los enlaces legales y la atribución de la fuente de datos.
struct SettingsView: View {

    @Query private var importedFiles: [LocalComicFile]

    @Environment(SubscriptionStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.catalog) private var catalog

    @State private var paywall: PaywallReason?
    @State private var showsManageSubscriptions = false
    @State private var showsImporter = false
    @State private var importError: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                subscriptionSection
                librarySection
                statsSection(stats)
                legalSection
                aboutSection
            }
            .navigationTitle("Perfil")
            .paywall($paywall)
            .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
            .fileImporter(isPresented: $showsImporter,
                          allowedContentTypes: Self.importableTypes,
                          allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            // Binding calculado, no `.constant`: ver el mismo arreglo en PaywallView.
            .alert("No se ha podido importar", isPresented: Binding(
                get: { importError != nil },
                set: { visible in if !visible { importError = nil } }
            )) {
                Button("De acuerdo", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: - Suscripción

    private var subscriptionSection: some View {
        Section {
            if store.isPremium {
                HStack {
                    Label(store.hasLifetimeAccess ? "PanelMax+ para siempre" : "PanelMax+ activo",
                          systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.premium)
                    Spacer()
                }

                // Un acceso lifetime es una compra no consumible: no tiene una
                // suscripción que cancelar. Si ambas compras coexisten, mantenemos
                // este botón para que el usuario pueda cancelar la renovación.
                if store.hasActiveSubscription {
                    Button("Gestionar suscripción") { showsManageSubscriptions = true }
                }
            } else {
                Button {
                    paywall = .general
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Hazte PanelMax+").font(.headline)
                        Text("Colección, importaciones y series sin límites.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                // 3.1.2 · restaurar también fuera del muro: mucha gente lo busca aquí.
                Button("Restaurar compras") {
                    Task { await store.restore() }
                }
                .disabled(store.isWorking)
            }
        } header: {
            Text("PanelMax+")
        }
        .alert("No se ha podido completar", isPresented: Binding(
            get: { store.lastError != nil },
            set: { visible in if !visible { store.clearError() } }
        )) {
            Button("De acuerdo", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    // MARK: - Biblioteca

    private var librarySection: some View {
        Section("Tus cómics") {
            Button {
                importComic()
            } label: {
                if isImporting {
                    HStack {
                        ProgressView()
                        Text("Importando…")
                    }
                } else {
                    Label("Importar cómic (CBZ o PDF)", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(isImporting)

            NavigationLink {
                ImportedLibraryView()
            } label: {
                LabeledContent {
                    Text("\(importedFiles.count)")
                        .foregroundStyle(Theme.secondaryText)
                } label: {
                    Label("Biblioteca importada", systemImage: "books.vertical")
                }
            }

            if !store.isPremium {
                let used = importedFiles.count
                Text("\(used) de \(FreeLimits.importedFiles) importaciones del plan gratuito")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// Los dos recuentos se resuelven de una vez, fuera del constructor de la
    /// lista: antes cada `fetchCount` se ejecutaba dentro del cuerpo de la
    /// `Section` y se repetía en cada evaluación de la vista.
    private var stats: (entries: Int, followed: Int) {
        let collection = CollectionStore(context: context)
        return (collection.entryCount(), collection.followedSeriesCount())
    }

    private func statsSection(_ stats: (entries: Int, followed: Int)) -> some View {
        Section("Tu colección") {
            LabeledContent("Números guardados", value: "\(stats.entries)")
            LabeledContent("Series seguidas", value: "\(stats.followed)")
        }
    }

    // MARK: - Legal y atribución

    private var legalSection: some View {
        Section("Legal") {
            Link("Condiciones de uso", destination: LegalLinks.terms)
            Link("Política de privacidad", destination: LegalLinks.privacy)
            Link("Soporte", destination: LegalLinks.support)
        }
    }

    /// La atribución NO es opcional: la licencia de la fuente de datos la exige,
    /// y el revisor de Apple busca precisamente esto en una app de catálogo.
    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Datos de \(catalog.attribution.name)")
                    .font(.subheadline.weight(.semibold))
                Text(catalog.attribution.licenseNote)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Link("Visitar la fuente", destination: catalog.attribution.url)
                    .font(.caption)
            }
            .padding(.vertical, 4)

            LabeledContent("Versión", value: Bundle.main.appVersion)
        } header: {
            Text("Acerca de")
        } footer: {
            Text("PanelMax no distribuye cómics. Muestra información pública de las obras y abre los archivos que tú importas desde tu dispositivo.")
        }
    }

    // MARK: - Importación

    static let importableTypes: [UTType] = {
        var types: [UTType] = [.pdf, .zip]
        if let cbz = UTType(filenameExtension: "cbz") { types.append(cbz) }
        return types
    }()

    private func importComic() {
        let gate = PremiumGate(isPremium: store.isPremium)

        if let reason = gate.check(.importFile(current: importedFiles.count)) {
            paywall = reason
            return
        }
        showsImporter = true
    }

    /// Copia el archivo dentro del contenedor de la app.
    ///
    /// Copiar en vez de guardar solo el marcador evita el problema clásico:
    /// el usuario borra el archivo de iCloud Drive y el cómic deja de abrirse.
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            // Cerrar el selector no es un fallo que haya que enseñar al usuario.
            if (error as NSError).code != NSUserCancelledError {
                importError = error.localizedDescription
            }

        case .success(let urls):
            guard !urls.isEmpty, !isImporting else { return }

            let remaining = max(FreeLimits.importedFiles - importedFiles.count, 0)
            guard store.isPremium || urls.count <= remaining else {
                importError = ComicImportError.freeLimit(selected: urls.count, remaining: remaining).localizedDescription
                return
            }

            guard ComicImportCoordinator.begin() else {
                importError = "Ya hay otra importación en curso. Espera a que termine antes de añadir más cómics."
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

                    // Se vuelve a comprobar al terminar la copia. Así una segunda
                    // importación o un cambio de contexto no puede abrir una carrera
                    // que sobrepase el límite gratuito.
                    let currentCount = (try? context.fetchCount(FetchDescriptor<LocalComicFile>())) ?? importedFiles.count
                    let stillFits = store.isPremium
                        || currentCount + drafts.count <= FreeLimits.importedFiles
                    guard stillFits else {
                        guard ComicImportBatch.rollback(drafts) else {
                            throw ComicImportError.cleanupFailed
                        }
                        throw ComicImportError.freeLimit(
                            selected: drafts.count,
                            remaining: max(FreeLimits.importedFiles - currentCount, 0)
                        )
                    }

                    do {
                        // Un contexto separado hace que un fallo del lote no revierta
                        // cambios no relacionados de la interfaz principal.
                        let importContext = ModelContext(container)
                        for draft in drafts {
                            let file = LocalComicFile(displayName: draft.displayName,
                                                      localFilename: draft.filename)
                            file.fileSize = draft.fileSize
                            file.pageCount = draft.pageCount
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
                    importError = error.localizedDescription
                }
            }
        }
    }
}

/// Coordina todas las escenas de la app. Sin este bloqueo, dos ventanas podían
/// comprobar a la vez la misma cuota gratuita y superar el límite entre ambas.
@MainActor
private enum ComicImportCoordinator {
    private static var isRunning = false


    static func begin() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    static func end() {
        isRunning = false
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
    case freeLimit(selected: Int, remaining: Int)
    case unavailable(String)
    case unsupported(String)
    case tooLarge(String)
    case batchTooLarge
    case insufficientSpace
    case persistence(String)
    case cleanupFailed

    var errorDescription: String? {
        switch self {
        case .freeLimit(let selected, let remaining):
            if remaining == 0 {
                return "Has alcanzado el límite de importaciones del plan gratuito."
            }
            return "Has seleccionado \(selected) archivos, pero en el plan gratuito solo te quedan \(remaining) importaciones. No se ha copiado ninguno."
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
        let destination = try LocalComicFile.prepareComicsDirectory(using: manager)
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

extension Bundle {
    /// "1.0 (12)", que es lo que hay que enseñar en Ajustes y pedir en los informes de fallo.
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(SubscriptionStore())
        .modelContainer(PreviewData.container)
}
