import Foundation

/// Evita que dos importaciones se ejecuten a la vez.
///
/// Sin este guardián, pulsar «Importar» dos veces seguidas — o dos ventanas
/// de la misma app en Stage Manager en iPad — podría lanzar dos lotes de
/// copia simultáneos sobre la misma carpeta `Comics/`. `@MainActor` porque
/// solo se llama desde el hilo principal, al iniciar y terminar la tarea de
/// importación de la interfaz.
///
/// Se llama desde `LibraryStore`, no desde ninguna vista directamente: la
/// vista solo conoce `LibraryStore.beginImporting()`/`endImporting()`.
@MainActor
enum ComicImportCoordinator {
    private static var isImporting = false

    @discardableResult
    static func begin() -> Bool {
        guard !isImporting else { return false }
        isImporting = true
        return true
    }

    static func end() {
        isImporting = false
    }
}

struct ImportedComicDraft: Sendable {
    let displayName: String
    let filename: String
    let fileSize: Int64
    let pageCount: Int
    let url: URL
}

/// Un archivo del lote que no se pudo importar, con el motivo. El resto del
/// lote sigue adelante: un solo archivo no compatible ya no aborta los
/// demás (ver `ComicImportBatch.copy`).
struct SkippedComicImport: Sendable {
    let name: String
    let reason: String
}

/// Resultado de copiar un lote: lo que se importó y lo que se omitió.
struct ComicImportBatchResult: Sendable {
    let drafts: [ImportedComicDraft]
    let skipped: [SkippedComicImport]
}

enum ComicImportError: LocalizedError {
    case unavailable(String)
    case unsupported(String)
    case tooLarge(String)
    case batchTooLarge
    case insufficientSpace
    case persistence(String)
    /// Ningún archivo del lote pasó las comprobaciones. A diferencia de un
    /// archivo suelto no compatible (que solo se omite, ver `SkippedComicImport`),
    /// aquí no hay nada que importar y hay que avisar de todos modos.
    case noneImported([SkippedComicImport])
    /// La importación falló por `underlying` y, además, no se pudo deshacer
    /// la copia. Se conserva el error original porque es el que explica al
    /// usuario por qué no se importó nada.
    case cleanupFailed(underlying: any Error)

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
        case .noneImported(let skipped):
            let names = skipped.prefix(5).map(\.name).joined(separator: ", ")
            let rest = skipped.count > 5 ? " y \(skipped.count - 5) más" : ""
            return "No se pudo importar ningún archivo: \(names)\(rest)."
        case .cleanupFailed(let underlying):
            return "\(underlying.localizedDescription) Además, no se ha podido revertir por completo la copia. \(AppInfo.displayName) conservará los archivos temporales para evitar perder datos; comprueba el espacio disponible y vuelve a intentarlo."
        }
    }
}

/// Copia atómica de un lote. Los archivos se validan dentro de una carpeta
/// temporal privada y solo se mueven a su nombre definitivo cuando todos han
/// pasado las comprobaciones.
///
/// Un archivo no compatible (extensión, tamaño individual, corrupto) se
/// OMITE y se sigue con el resto: con lotes de decenas o cientos de cómics,
/// que uno solo no compatible cortara toda la subida obligaba a quitarlo a
/// mano y volver a seleccionar todo. Los límites que son del LOTE entero
/// (tamaño total o espacio en disco) sí siguen abortando la copia completa:
/// ahí no hay un archivo culpable que aislar, es la selección entera la que
/// no cabe.
enum ComicImportBatch {
    nonisolated static func copy(_ sources: [URL]) throws -> ComicImportBatchResult {
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
        var skipped: [SkippedComicImport] = []
        var batchSize: Int64 = 0

        do {
            for source in sources {
                let name = source.lastPathComponent
                let ext = source.pathExtension.lowercased()
                guard ["cbz", "zip", "pdf"].contains(ext) else {
                    skipped.append(SkippedComicImport(name: name,
                                                        reason: ComicImportError.unsupported(name).errorDescription ?? ""))
                    continue
                }

                let didAccess = source.startAccessingSecurityScopedResource()
                defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

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
                        // Límite del LOTE, no de este archivo: se propaga y
                        // aborta toda la copia (ver el `catch` de abajo).
                        throw ComicImportError.batchTooLarge
                    }

                    if let capacity = try destination.resourceValues(
                        forKeys: [.volumeAvailableCapacityForImportantUsageKey]
                    ).volumeAvailableCapacityForImportantUsage,
                       capacity < size + safetyReserve {
                        throw ComicImportError.insufficientSpace
                    }
                    batchSize = newBatchSize

                    let filename = "\(UUID().uuidString).\(ext)"
                    let temporaryURL = staging.appending(path: filename, directoryHint: .notDirectory)
                    try manager.copyItem(at: source, to: temporaryURL)

                    let pages: Int
                    do {
                        pages = try ComicArchiveFactory.pageCount(at: temporaryURL)
                    } catch {
                        // No es un CBZ/PDF legible pese a la extensión: se
                        // limpia la copia parcial y se omite, no se aborta el lote.
                        try? manager.removeItem(at: temporaryURL)
                        throw ComicImportError.unsupported(name)
                    }

                    let rawDisplayName = source.deletingPathExtension().lastPathComponent
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayName = String((rawDisplayName.isEmpty ? "Cómic importado" : rawDisplayName).prefix(160))
                    staged.append((displayName, filename, size, pages, temporaryURL))
                } catch ComicImportError.batchTooLarge {
                    throw ComicImportError.batchTooLarge
                } catch ComicImportError.insufficientSpace {
                    throw ComicImportError.insufficientSpace
                } catch let importError as ComicImportError {
                    skipped.append(SkippedComicImport(name: name, reason: importError.errorDescription ?? ""))
                } catch {
                    skipped.append(SkippedComicImport(name: name, reason: error.localizedDescription))
                }
            }
        } catch {
            // Fallo de LOTE (tamaño total o espacio en disco): se revierte
            // todo lo copiado hasta ahora, igual que antes de poder omitir
            // archivos sueltos.
            try? manager.removeItem(at: staging)
            throw error
        }

        guard !staged.isEmpty else {
            try? manager.removeItem(at: staging)
            throw ComicImportError.noneImported(skipped)
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
            return ComicImportBatchResult(drafts: completed, skipped: skipped)
        } catch {
            let removedFinals = rollback(completed)
            let removedStaging: Bool
            do {
                if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
                removedStaging = true
            } catch {
                removedStaging = false
            }
            guard removedFinals, removedStaging else { throw ComicImportError.cleanupFailed(underlying: error) }
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
