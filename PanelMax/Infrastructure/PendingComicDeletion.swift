import Foundation

/// Movimiento reversible de una copia privada. Nunca se toca el archivo externo
/// de un bookmark: PanelMax solo es dueño de lo que copió a `Documents/Comics`.
///
/// Infraestructura pura (solo `FileManager`, sin SwiftData ni SwiftUI): es lo
/// que permite que `LibraryStore.delete(_:)` pueda deshacer un borrado a
/// medias sin saber nada de cómo está montada la pantalla que lo pidió.
struct PendingComicDeletion {
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
