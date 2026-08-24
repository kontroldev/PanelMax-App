import Foundation
import Testing
@testable import PanelMax

/// `LocalComicFile.storageURL` es la barrera que impide que un nombre de
/// archivo persistido y manipulado apunte fuera de `Documents/Comics`.
///
/// Era la única defensa de seguridad de la app sin ninguna prueba detrás.
@Suite("Seguridad de rutas de archivo")
struct FileSafetyTests {

    private var comicsPath: String {
        LocalComicFile.comicsDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    @Test("Un nombre normal resuelve dentro de la carpeta de cómics")
    func acceptsPlainFilename() throws {
        let url = try LocalComicFile.storageURL(for: "A1B2C3.cbz")

        #expect(url.lastPathComponent == "A1B2C3.cbz")
        #expect(url.path.hasPrefix(comicsPath + "/"))
    }

    @Test("Rechaza rutas que suben de directorio",
          arguments: ["../secreto.cbz",
                      "../../Library/Preferences/algo.plist",
                      "subcarpeta/../../fuera.cbz"])
    func rejectsTraversal(name: String) {
        #expect(throws: ComicArchiveError.self) {
            try LocalComicFile.storageURL(for: name)
        }
    }

    @Test("Rechaza nombres con separadores de ruta",
          arguments: ["carpeta/comic.cbz", "/etc/passwd", "a/b/c.pdf"])
    func rejectsPathSeparators(name: String) {
        #expect(throws: ComicArchiveError.self) {
            try LocalComicFile.storageURL(for: name)
        }
    }

    @Test("Rechaza nombres vacíos y referencias a directorio",
          arguments: ["", ".", ".."])
    func rejectsDegenerateNames(name: String) {
        #expect(throws: ComicArchiveError.self) {
            try LocalComicFile.storageURL(for: name)
        }
    }

    @Test("Un registro sin copia interna no devuelve URL local")
    func bookmarkOnlyRecordHasNoLocalCopy() throws {
        let file = LocalComicFile(displayName: "Externo", bookmark: Data([0x01]))

        #expect(try file.localCopyURL() == nil)
    }

    @Test("Un registro sin copia ni marcador no se puede resolver")
    func unresolvableRecordThrows() {
        let file = LocalComicFile(displayName: "Huérfano")

        #expect(throws: ComicArchiveError.self) {
            _ = try file.resolveURL()
        }
    }
}

/// Casos límite del orden natural que no cubría la suite original.
@Suite("Orden natural de números, casos límite")
struct ComicNumberEdgeTests {

    @Test("El cero va antes que el uno")
    func zeroComesFirst() {
        #expect(ComicNumber.areInIncreasingOrder("0", "1"))
        #expect(!ComicNumber.areInIncreasingOrder("1", "0"))
    }

    @Test("Los negativos se ordenan por valor, no por texto")
    func negativesSortByValue() {
        #expect(ComicNumber.sorted(["-1", "2", "0"]) { $0 } == ["-1", "0", "2"])
    }

    @Test("Un entero siempre precede a un especial")
    func integersBeforeSpecials() {
        #expect(ComicNumber.areInIncreasingOrder("999", "Anual 1"))
        #expect(!ComicNumber.areInIncreasingOrder("Anual 1", "999"))
    }

    @Test("Dos números iguales no se consideran en orden estricto")
    func equalNumbersAreNotIncreasing() {
        #expect(!ComicNumber.areInIncreasingOrder("5", "5"))
        #expect(!ComicNumber.areInIncreasingOrder("Anual", "Anual"))
    }

    @Test("Una lista vacía o de un elemento se ordena sin fallar")
    func trivialInputs() {
        #expect(ComicNumber.sorted([String]()) { $0 }.isEmpty)
        #expect(ComicNumber.sorted(["7"]) { $0 } == ["7"])
    }
}
