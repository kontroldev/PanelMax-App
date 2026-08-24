import Foundation
import SwiftData

/// Un archivo CBZ o PDF que el usuario ha importado desde Archivos o iCloud Drive.
///
/// Importante para App Review y para tu tranquilidad legal: la app NO descarga
/// cómics de ningún sitio. Solo abre lo que el usuario ya tiene en su dispositivo.
@Model
final class LocalComicFile {

    var displayName: String = ""

    /// Marcador de seguridad (security-scoped bookmark).
    /// No se guarda la ruta: en iOS las rutas cambian entre lanzamientos y actualizaciones.
    var bookmark: Data?

    /// Copia interna del archivo dentro del contenedor de la app.
    /// Alternativa al marcador cuando el usuario elige "copiar a PanelMax".
    var localFilename: String?

    /// El marcador resolvió pero iOS lo dio por obsoleto. No se persiste:
    /// es una señal de una sesión concreta para regenerarlo tras leerlo.
    @Transient
    var needsBookmarkRefresh: Bool = false

    var pageCount: Int = 0
    var importedAt: Date = Date()
    var fileSize: Int64 = 0

    /// Progreso propio del archivo. Es necesario porque un cómic importado puede
    /// leerse sin estar vinculado a ningún número del catálogo.
    var currentPage: Int = 0
    var lastReadAt: Date?
    var isFinished: Bool = false

    /// Número del catálogo al que se ha vinculado, si el usuario lo ha emparejado.
    var issue: Issue?

    init(displayName: String, bookmark: Data? = nil, localFilename: String? = nil) {
        self.displayName = displayName
        self.bookmark = bookmark
        self.localFilename = localFilename
        self.importedAt = Date()
    }

    /// Carpeta privada donde viven las copias que sí pertenecen a PanelMax.
    /// Nunca se elimina un archivo externo al borrar un registro de la biblioteca.
    nonisolated static var comicsDirectory: URL {
        URL.documentsDirectory.appending(path: "Comics", directoryHint: .isDirectory)
    }

    /// Crea la carpeta de cómics y la marca como excluida de la copia de seguridad.
    ///
    /// Sin esto, cada CBZ importado se sube a iCloud dentro del respaldo del
    /// dispositivo. Apple lo trata como uso indebido del almacenamiento (una
    /// biblioteca de 40 cómics puede ocupar varios GB del iCloud del usuario)
    /// y es una causa habitual de rechazo. El contenido es recuperable: el
    /// usuario conserva los originales en Archivos o iCloud Drive.
    @discardableResult
    nonisolated static func prepareComicsDirectory(using manager: FileManager = .default) throws -> URL {
        let directory = comicsDirectory
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
        return directory
    }

    /// Marca una URL para que no entre en la copia de seguridad de iCloud.
    /// Excluir la carpeta basta: la exclusión se hereda por su contenido.
    nonisolated static func excludeFromBackup(_ url: URL) throws {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }

    /// Construye una URL interna y rechaza nombres manipulados o rutas que escapen
    /// de `Documents/Comics` (por ejemplo, datos persistentes dañados con `../`).
    nonisolated static func storageURL(for filename: String) throws -> URL {
        let leaf = (filename as NSString).lastPathComponent
        guard !filename.isEmpty,
              filename == leaf,
              filename != ".",
              filename != ".." else {
            throw ComicArchiveError.fileUnavailable
        }

        let directory = comicsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = directory
            .appending(path: filename, directoryHint: .notDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let directoryPrefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"

        guard candidate.path.hasPrefix(directoryPrefix) else {
            throw ComicArchiveError.fileUnavailable
        }
        return candidate
    }

    /// Devuelve la copia privada, si el registro usa una. No apunta nunca al
    /// archivo original escogido en Archivos/iCloud Drive.
    func localCopyURL() throws -> URL? {
        guard let localFilename else { return nil }
        return try Self.storageURL(for: localFilename)
    }

    /// Devuelve la URL utilizable del archivo.
    ///
    /// Si viene de un marcador hay que llamar a `startAccessingSecurityScopedResource()`
    /// antes de leerlo y a `stop...` al terminar. De eso se encarga `ComicArchive`.
    func resolveURL() throws -> URL {
        if let localURL = try localCopyURL() {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                throw ComicArchiveError.fileUnavailable
            }
            return localURL
        }

        guard let bookmark else {
            throw ComicArchiveError.fileUnavailable
        }

        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark,
                          options: [],
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)

        // Un marcador obsoleto SIGUE resolviendo a una URL válida: iOS solo avisa
        // de que conviene regenerarlo. Rechazarlo aquí dejaba el cómic inaccesible
        // para siempre tras una actualización del sistema o del propio binario.
        if isStale {
            needsBookmarkRefresh = true
        }
        return url
    }

    /// Regenera el marcador tras acceder correctamente al archivo. Debe llamarse
    /// dentro del alcance de seguridad, no después de liberarlo.
    func refreshBookmarkIfNeeded(from url: URL) {
        guard needsBookmarkRefresh else { return }
        if let refreshed = try? url.bookmarkData() {
            bookmark = refreshed
        }
        needsBookmarkRefresh = false
    }

    /// Actualiza el estado de lectura con valores válidos para el archivo abierto.
    func updateProgress(page: Int, totalPages: Int) {
        guard totalPages > 0 else { return }
        let clampedPage = min(max(page, 0), totalPages - 1)
        self.currentPage = clampedPage
        self.pageCount = totalPages
        self.lastReadAt = .now
        self.isFinished = clampedPage >= totalPages - 1
    }

    var progressFraction: Double {
        guard pageCount > 0, lastReadAt != nil else { return 0 }
        return min(Double(currentPage + 1) / Double(pageCount), 1)
    }

    var progressDescription: String? {
        guard pageCount > 0, lastReadAt != nil else { return nil }
        return "Pág. \(currentPage + 1) / \(pageCount)"
    }
}
