import Foundation
import SwiftData

/// Operaciones sobre la biblioteca de archivos importados.
///
/// Mismo papel que `CollectionStore` para la colección catalogada a mano:
/// las vistas no orquestan copia de archivos, miniaturas ni papelera interna
/// por su cuenta, todo pasa por aquí. Antes esta lógica vivía repartida
/// dentro de `ImportedLibraryView` (import, borrado reversible, y los tipos
/// de soporte de ambos) — mezclada con la vista que la disparaba.
@MainActor
struct LibraryStore {

    let context: ModelContext

    // MARK: - Importación

    /// Sincrónico a propósito: se llama ANTES de marcar el indicador de carga
    /// en la vista y de lanzar la tarea de importación, para no encenderlo ni
    /// un instante si ya había una importación en marcha.
    @discardableResult
    func beginImporting() -> Bool {
        ComicImportCoordinator.begin()
    }

    func endImporting() {
        ComicImportCoordinator.end()
    }

    /// Copia un lote de archivos ya elegidos por el usuario al contenedor
    /// privado, genera su miniatura y los inserta en la biblioteca.
    ///
    /// Copiar en vez de guardar solo el marcador evita el problema clásico:
    /// el usuario borra el archivo de iCloud Drive y el cómic deja de abrirse.
    ///
    /// Llamar a `beginImporting()` es responsabilidad de quien invoca esto,
    /// no de esta función: así la vista puede decidir NO encender su
    /// indicador de carga cuando ya había una importación en curso.
    func importFiles(from urls: [URL]) async throws {
        // Un contenedor propio, no `context`: un contexto separado hace que
        // un fallo del lote no revierta cambios no relacionados de la
        // interfaz principal que estuvieran pendientes de guardar.
        let container = context.container

        let drafts = try await Task.detached(priority: .userInitiated) {
            try ComicImportBatch.copy(urls)
        }.value

        do {
            let importContext = ModelContext(container)
            for draft in drafts {
                let file = LocalComicFile(displayName: draft.displayName,
                                          localFilename: draft.filename)
                file.fileSize = draft.fileSize
                file.pageCount = draft.pageCount

                // La portada sale de la propia página 1. Si falla, el cómic
                // se importa igual, solo que sin miniatura.
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
    }

    // MARK: - Borrado

    /// Borra varios archivos importados.
    ///
    /// Primero se mueve cada copia a una papelera interna, después se guarda
    /// la eliminación en SwiftData y solo entonces se borra físicamente. Si
    /// falla el guardado, el movimiento se deshace y el cómic sigue
    /// disponible: borrar varias filas es una única operación y no puede
    /// quedar a medias.
    func delete(_ files: [LocalComicFile]) throws {
        guard !files.isEmpty else { return }

        var staged: [PendingComicDeletion] = []
        var cleanupFailed = false

        do {
            // Se preparan todos antes de tocar SwiftData.
            for file in files {
                if let deletion = try PendingComicDeletion.stage(file) {
                    staged.append(deletion)
                }
            }

            let thumbnailsToRemove = files.map(\.thumbnailFilename)
            files.forEach(context.delete)
            try context.save()

            for deletion in staged {
                do {
                    try deletion.finish()
                } catch {
                    // El registro ya no existe: la copia queda en la carpeta
                    // de limpieza y se reintentará al volver a abrir la
                    // biblioteca (ver `PendingComicDeletion.cleanup`). No es
                    // un fallo que deba deshacer el borrado ya guardado.
                    cleanupFailed = true
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
            let message = restorationFailed
                ? "\(error.localizedDescription) Las copias que no pudieron volver a su ubicación se han conservado en la carpeta de recuperación y no se borrarán."
                : error.localizedDescription
            throw LibraryDeleteError.failed(message)
        }

        // Fuera del `do/catch` de arriba a propósito: el borrado YA se
        // guardó con éxito en este punto, así que esto no debe entrar por
        // el camino de deshacer/restaurar de la rama `catch`.
        if cleanupFailed {
            throw LibraryDeleteError.partialCleanupFailure
        }
    }
}

/// Errores de `LibraryStore.delete(_:)`. El borrado en sí (el registro
/// SwiftData) puede haber tenido éxito aunque se lance
/// `.partialCleanupFailure`: es un aviso, no una reversión.
enum LibraryDeleteError: LocalizedError {
    case failed(String)
    case partialCleanupFailure

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        case .partialCleanupFailure:
            return "El cómic se quitó de la biblioteca, pero su copia interna no se ha podido limpiar todavía. \(AppInfo.displayName) volverá a intentarlo."
        }
    }
}
