import Foundation
import Testing
@testable import PanelMax

/// Qué imagen corresponde a cada página de un EPUB, y qué EPUB se rechazan.
///
/// Se prueba con EPUB descritos en memoria (ruta → contenido), sin ZIP: así
/// cada test enseña justo el caso que importa. La lectura de EPUB reales,
/// comprimidos, está en `EPUBArchiveTests`.
@Suite("Índice de los EPUB")
struct EPUBPackageTests {

    // MARK: - Utilidades

    /// Un EPUB en memoria: container, índice con el spine dado y archivos sueltos.
    private func makeFiles(spine: [(id: String, href: String, mediaType: String)],
                           linearNo: Set<String> = [],
                           files: [String: String]) -> [String: String] {
        let manifest = spine.map {
            "<item id=\"\($0.id)\" href=\"\($0.href)\" media-type=\"\($0.mediaType)\"/>"
        }.joined()
        let itemrefs = spine.map {
            linearNo.contains($0.id) ? "<itemref idref=\"\($0.id)\" linear=\"no\"/>" : "<itemref idref=\"\($0.id)\"/>"
        }.joined()
        var all = files
        all[EPUBPackage.containerPath] = ComicFixtures.epubContainerXML
        all["OEBPS/content.opf"] = """
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
              <manifest>\(manifest)</manifest><spine>\(itemrefs)</spine>
            </package>
            """
        return all
    }

    private func parse(_ files: [String: String]) throws -> EPUBPackage {
        try EPUBPackage.parse(fileExists: { files[$0] != nil },
                              readFile: { files[$0].map { Data($0.utf8) } })
    }

    /// Comprueba que `body` lanza justo ese caso de `ComicArchiveError`.
    /// `#expect(throws:)` con un valor exige que el error sea `Equatable`, y
    /// `ComicArchiveError` no lo es; comparar su nombre basta para estos casos,
    /// que no llevan datos asociados.
    private func expectArchiveError(_ expected: ComicArchiveError,
                                    sourceLocation: SourceLocation = #_sourceLocation,
                                    _ body: () throws -> Void) {
        let error = #expect(throws: ComicArchiveError.self, sourceLocation: sourceLocation) {
            try body()
        }
        if let error {
            #expect(String(describing: error) == String(describing: expected), sourceLocation: sourceLocation)
        }
    }

    /// Páginas XHTML de cómic, una imagen cada una, en `OEBPS/text/`.
    private func comicFiles(pageCount: Int) -> (spine: [(id: String, href: String, mediaType: String)], files: [String: String]) {
        var files: [String: String] = [:]
        var spine: [(id: String, href: String, mediaType: String)] = []
        for index in 0..<pageCount {
            spine.append((id: "p\(index)", href: "text/p\(index).xhtml", mediaType: "application/xhtml+xml"))
            files["OEBPS/text/p\(index).xhtml"] = ComicFixtures.epubPage(body: "<img src=\"../images/p\(index).jpg\"/>")
            files["OEBPS/images/p\(index).jpg"] = "imagen"
        }
        return (spine, files)
    }

    // MARK: - EPUB de cómic

    @Test("Sigue el orden del spine, no el del manifest ni el de los nombres")
    func followsSpineOrder() throws {
        let comic = comicFiles(pageCount: 3)
        // El spine se recorre al revés: p2, p1, p0.
        let package = try parse(makeFiles(spine: comic.spine.reversed(), files: comic.files))

        #expect(package.pageImagePaths == ["OEBPS/images/p2.jpg", "OEBPS/images/p1.jpg", "OEBPS/images/p0.jpg"])
    }

    @Test("Encuentra la imagen dentro de un SVG a pantalla completa")
    func findsSVGImage() throws {
        let files = makeFiles(
            spine: [(id: "p0", href: "p0.xhtml", mediaType: "application/xhtml+xml")],
            files: [
                "OEBPS/p0.xhtml": ComicFixtures.epubPage(body: """
                    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 800 1200">
                      <image width="800" height="1200" xlink:href="img/portada.png"/>
                    </svg>
                    """),
                "OEBPS/img/portada.png": "imagen"
            ]
        )

        #expect(try parse(files).pageImagePaths == ["OEBPS/img/portada.png"])
    }

    @Test("El spine puede apuntar directamente a una imagen")
    func spineCanPointToAnImage() throws {
        let files = makeFiles(spine: [(id: "p0", href: "images/p0.png", mediaType: "image/png")],
                              files: ["OEBPS/images/p0.png": "imagen"])

        #expect(try parse(files).pageImagePaths == ["OEBPS/images/p0.png"])
    }

    @Test("Tolera entidades de HTML como &nbsp;, que XML no conoce")
    func toleratesHTMLEntities() throws {
        let files = makeFiles(
            spine: [(id: "p0", href: "p0.xhtml", mediaType: "application/xhtml+xml")],
            files: [
                "OEBPS/p0.xhtml": ComicFixtures.epubPage(body: "<div>&nbsp;&copy;</div><img src=\"p0.jpg\"/>"),
                "OEBPS/p0.jpg": "imagen"
            ]
        )

        #expect(try parse(files).pageImagePaths == ["OEBPS/p0.jpg"])
    }

    @Test("Un número de página junto a la imagen no la descarta")
    func shortTextIsTolerated() throws {
        let files = makeFiles(
            spine: [(id: "p0", href: "p0.xhtml", mediaType: "application/xhtml+xml")],
            files: [
                "OEBPS/p0.xhtml": ComicFixtures.epubPage(body: "<img src=\"p0.jpg\"/><p>Página 12</p>"),
                "OEBPS/p0.jpg": "imagen"
            ]
        )

        #expect(try parse(files).pageImagePaths.count == 1)
    }

    @Test("Una página de créditos sin imagen no impide abrir el cómic")
    func creditsPageIsSkipped() throws {
        var comic = comicFiles(pageCount: 5)
        comic.spine.append((id: "creditos", href: "text/creditos.xhtml", mediaType: "application/xhtml+xml"))
        comic.files["OEBPS/text/creditos.xhtml"] = ComicFixtures.epubPage(
            body: "<p>Guion y dibujo: Ana Pérez. Color: Luis Gil. Rotulación: Marta Ruiz. Edición: Viñetas Libres, 2026.</p>"
        )

        #expect(try parse(makeFiles(spine: comic.spine, files: comic.files)).pageImagePaths.count == 5)
    }

    @Test("Las páginas fuera del orden de lectura (linear=\"no\") no cuentan")
    func nonLinearItemsAreIgnored() throws {
        var comic = comicFiles(pageCount: 2)
        comic.spine.append((id: "nota", href: "text/nota.xhtml", mediaType: "application/xhtml+xml"))
        comic.files["OEBPS/text/nota.xhtml"] = ComicFixtures.epubPage(body: "<img src=\"../images/nota.jpg\"/>")
        comic.files["OEBPS/images/nota.jpg"] = "imagen"

        let package = try parse(makeFiles(spine: comic.spine, linearNo: ["nota"], files: comic.files))

        #expect(package.pageImagePaths == ["OEBPS/images/p0.jpg", "OEBPS/images/p1.jpg"])
    }

    // MARK: - EPUB que se rechazan

    @Test("Una novela (texto en todos los capítulos) se rechaza como EPUB de texto")
    func novelIsRejected() {
        var files: [String: String] = [:]
        var spine: [(id: String, href: String, mediaType: String)] = []
        // Una portada con imagen y doce capítulos de texto.
        spine.append((id: "portada", href: "portada.xhtml", mediaType: "application/xhtml+xml"))
        files["OEBPS/portada.xhtml"] = ComicFixtures.epubPage(body: "<img src=\"portada.jpg\"/>")
        files["OEBPS/portada.jpg"] = "imagen"
        for chapter in 1...12 {
            spine.append((id: "c\(chapter)", href: "c\(chapter).xhtml", mediaType: "application/xhtml+xml"))
            files["OEBPS/c\(chapter).xhtml"] = ComicFixtures.epubPage(
                body: String(repeating: "<p>Era una noche oscura y tormentosa sobre la ciudad dormida.</p>", count: 5)
            )
        }

        expectArchiveError(.textEPUB) {
            _ = try parse(makeFiles(spine: spine, files: files))
        }
    }

    @Test("Páginas con texto real encima del dibujo se rechazan: se perdería el texto")
    func textOverImagesIsRejected() {
        var comic = comicFiles(pageCount: 3)
        for index in 0..<3 {
            comic.files["OEBPS/text/p\(index).xhtml"] = ComicFixtures.epubPage(body: """
                <img src="../images/p\(index).jpg"/>
                <div class="bocadillo">¡No puede ser! Llevamos tres días siguiendo su rastro por toda la ciudad y ahora resulta que nunca estuvo aquí.</div>
                """)
        }

        expectArchiveError(.textEPUB) {
            _ = try parse(makeFiles(spine: comic.spine, files: comic.files))
        }
    }

    @Test("Un EPUB con las páginas cifradas (DRM) se rechaza como protegido")
    func drmIsRejected() {
        var comic = comicFiles(pageCount: 2)
        comic.files[EPUBPackage.encryptionPath] = """
            <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
                        xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
              <enc:EncryptedData>
                <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
                <enc:CipherData><enc:CipherReference URI="OEBPS/images/p0.jpg"/></enc:CipherData>
              </enc:EncryptedData>
            </encryption>
            """

        expectArchiveError(.protectedEPUB) {
            _ = try parse(makeFiles(spine: comic.spine, files: comic.files))
        }
    }

    @Test("Las fuentes ofuscadas no son DRM: el cómic se abre igual")
    func obfuscatedFontsAreNotDRM() throws {
        var comic = comicFiles(pageCount: 2)
        comic.files[EPUBPackage.encryptionPath] = """
            <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
                        xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
              <enc:EncryptedData>
                <enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
                <enc:CipherData><enc:CipherReference URI="OEBPS/fonts/rotulos.otf"/></enc:CipherData>
              </enc:EncryptedData>
            </encryption>
            """

        #expect(try parse(makeFiles(spine: comic.spine, files: comic.files)).pageImagePaths.count == 2)
    }

    @Test("Una imagen de internet nunca cuenta como página: la app no usa la red")
    func remoteImagesAreIgnored() {
        let files = makeFiles(
            spine: [(id: "p0", href: "p0.xhtml", mediaType: "application/xhtml+xml")],
            files: ["OEBPS/p0.xhtml": ComicFixtures.epubPage(body: "<img src=\"https://ejemplo.com/p0.jpg\"/>")]
        )

        expectArchiveError(.textEPUB) {
            _ = try parse(files)
        }
    }

    @Test("Sin container.xml no es un EPUB")
    func missingContainerIsUnsupported() {
        expectArchiveError(.unsupportedFormat) {
            _ = try parse(["OEBPS/content.opf": "<package/>"])
        }
    }

    // MARK: - Rutas

    @Test("Resuelve referencias relativas a rutas dentro del ZIP",
          arguments: [
              ("../images/p1.png", "OEBPS/text", "OEBPS/images/p1.png"),
              ("./p1.png", "OEBPS", "OEBPS/p1.png"),
              ("p%201.png#arriba", "OEBPS", "OEBPS/p 1.png"),
              ("/OEBPS/p1.png", "otra/carpeta", "OEBPS/p1.png"),
              ("content.opf", "", "content.opf")
          ])
    func resolvesRelativePaths(reference: String, directory: String, expected: String) {
        #expect(EPUBPackage.resolve(reference, relativeTo: directory) == expected)
    }

    @Test("Rechaza rutas que salen del ZIP, direcciones web y datos incrustados",
          arguments: ["../../fuera.png", "https://ejemplo.com/p1.png", "data:image/png;base64,AAAA", "mailto:alguien@ejemplo.com", ""])
    func rejectsUnsafeReferences(reference: String) {
        #expect(EPUBPackage.resolve(reference, relativeTo: "OEBPS") == nil)
    }
}
