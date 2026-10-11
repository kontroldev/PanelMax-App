import Foundation
import SwiftData
import Testing
@testable import PanelMax

/// Borrado y recuperación de cómics importados.
///
/// Es el único código de la app que borra archivos del usuario de forma
/// definitiva, y no tenía ningún test detrás.
///
/// Es una extensión de `LibraryImportTests`, no una suite aparte, a propósito:
/// así hereda su `.serialized`. Estos tests también escriben en `Comics/`
/// (la carpeta temporal de los tests, ver `StorageLocation`), y si corrieran
/// en paralelo con los de importación les descuadrarían el recuento de
/// archivos de esa carpeta.
extension LibraryImportTests {

    // MARK: - Borrado

    @Test("Borrar un cómic quita la ficha, la copia interna y la miniatura")
    func deleteRemovesRecordCopyAndThumbnail() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        let store = LibraryStore(context: context)
        try await store.importFiles(from: [try ComicFixtures.makeValidCBZ(in: source)])
        let file = try #require(try importedFiles(in: context).first)
        let filename = try #require(file.localFilename)
        let copy = try #require(try file.localCopyURL())
        let thumbnail = try #require(file.thumbnailURL)

        try store.delete([file])

        #expect(try importedFiles(in: context).isEmpty)
        #expect(FileManager.default.fileExists(atPath: copy.path) == false)
        #expect(FileManager.default.fileExists(atPath: thumbnail.path) == false)
        // Tampoco debe quedarse olvidada en la papelera interna.
        #expect(isInRecoveryFolder(filename) == false)
    }

    @Test("Borrar un cómic no toca el archivo original que eligió el usuario")
    func deleteNeverTouchesTheOriginal() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        let original = try ComicFixtures.makeValidCBZ(in: source)
        let store = LibraryStore(context: context)
        try await store.importFiles(from: [original])
        let file = try #require(try importedFiles(in: context).first)

        try store.delete([file])

        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    // MARK: - Papelera interna

    @Test("La limpieza devuelve a su sitio una copia cuya ficha sigue existiendo")
    func cleanupRestoresProtectedCopy() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        try await LibraryStore(context: context).importFiles(from: [try ComicFixtures.makeValidCBZ(in: source)])
        let file = try #require(try importedFiles(in: context).first)
        let filename = try #require(file.localFilename)
        let copy = try #require(try file.localCopyURL())

        // Simula un borrado que se quedó a medias: la copia ya se movió a la
        // papelera interna, pero el guardado en SwiftData no llegó a hacerse.
        let staged = try #require(try PendingComicDeletion.stage(file))
        #expect(FileManager.default.fileExists(atPath: copy.path) == false)

        PendingComicDeletion.cleanup(protecting: [filename])

        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(FileManager.default.fileExists(atPath: staged.pending.path) == false)
        #expect(file.isAvailable)
    }

    @Test("La limpieza borra del todo una copia que ya no tiene ficha")
    func cleanupRemovesUnprotectedCopy() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        try await LibraryStore(context: context).importFiles(from: [try ComicFixtures.makeValidCBZ(in: source)])
        let file = try #require(try importedFiles(in: context).first)
        let filename = try #require(file.localFilename)
        let copy = try #require(try file.localCopyURL())

        let staged = try #require(try PendingComicDeletion.stage(file))

        // Ningún nombre protegido: es el caso de un borrado que sí se guardó
        // en SwiftData pero cuya copia no se llegó a borrar del disco.
        PendingComicDeletion.cleanup(protecting: [])

        #expect(FileManager.default.fileExists(atPath: staged.pending.path) == false)
        #expect(FileManager.default.fileExists(atPath: copy.path) == false)
        #expect(isInRecoveryFolder(filename) == false)
    }

    // MARK: - Volver a enlazar

    @Test("Volver a enlazar recupera un cómic perdido sin perder su progreso")
    func relinkRecoversLostCopyAndKeepsProgress() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let source = try ComicFixtures.makeTemporaryDirectory()
        defer {
            removeImportedCopies(in: context)
            try? FileManager.default.removeItem(at: source)
        }

        let url = try ComicFixtures.makeValidCBZ(in: source, pageCount: 3)
        let store = LibraryStore(context: context)
        try await store.importFiles(from: [url])
        let file = try #require(try importedFiles(in: context).first)
        file.updateProgress(page: 1, totalPages: 3)
        try context.save()

        // Simula una restauración de copia de seguridad, que no incluye
        // `Comics/` porque está excluida a propósito.
        let lostCopy = try #require(try file.localCopyURL())
        try FileManager.default.removeItem(at: lostCopy)
        #expect(file.isAvailable == false)

        try await store.relink(file, to: url)

        #expect(file.isAvailable)
        #expect(file.localFilename != lostCopy.lastPathComponent)
        #expect(file.currentPage == 1)
        // Se reutiliza la misma ficha: no aparece un cómic duplicado.
        #expect(try importedFiles(in: context).count == 1)
    }

    // MARK: - Utilidades

    /// Si queda alguna copia con este nombre dentro de la papelera interna.
    private func isInRecoveryFolder(_ filename: String) -> Bool {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: PendingComicDeletion.directory,
                                                         includingPropertiesForKeys: nil)) ?? []
        return folders.contains {
            manager.fileExists(atPath: $0.appending(path: filename, directoryHint: .notDirectory).path)
        }
    }
}
