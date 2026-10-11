import Foundation

/// Lectura tolerante de los XML de un EPUB (`container.xml`, el `.opf` y las
/// páginas XHTML) con `XMLParser`, sin librerías de terceros.
///
/// No construye un árbol completo: solo recoge lo que `EPUBPackage` necesita
/// (los elementos con sus atributos, la primera imagen del cuerpo y cuánto
/// texto visible hay). Los nombres llegan sin prefijo de espacio de nombres:
/// `opf:item` se guarda como `item` y `svg:image` como `image`.
///
/// Es tolerante a propósito. Muchos EPUB reales traen XHTML imperfecto
/// (entidades HTML como `&nbsp;` que XML no conoce, por ejemplo). Ante un
/// error se conserva lo leído hasta ese punto, que en una página de cómic
/// suele bastar: la imagen está al principio.
nonisolated final class EPUBXMLScanner: NSObject, XMLParserDelegate {

    struct Element {
        let name: String
        let attributes: [String: String]
    }

    private(set) var elements: [Element] = []

    /// Referencia (`src` o `href`) de la primera imagen dentro de `<body>`:
    /// un `<img>` normal o un `<image>` de SVG, que también se usa mucho en
    /// páginas de cómic para encajar la imagen a pantalla completa.
    private(set) var firstImageReference: String?

    /// Caracteres de texto visible dentro de `<body>`, sin contar espacios
    /// ni el contenido de `<script>` o `<style>`.
    private(set) var bodyTextLength = 0

    private var isInsideBody = false
    private var hiddenDepth = 0

    static func scan(_ data: Data) -> EPUBXMLScanner {
        let scanner = EPUBXMLScanner()
        let parser = XMLParser(data: withHTMLEntitiesReplaced(data))
        // Nunca se descargan DTD ni entidades externas: la 1.0 no usa la red,
        // y un archivo importado no debe poder hacer que la app pida nada.
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = scanner
        parser.parse()
        return scanner
    }

    /// XML solo conoce cinco entidades (`&amp;`, `&lt;`...). Las de HTML,
    /// como `&nbsp;` o `&copy;`, rompen el análisis: se cambian por un
    /// espacio, que para lo que se busca aquí no cambia nada.
    private static func withHTMLEntitiesReplaced(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8), text.contains("&") else { return data }
        let htmlEntity = /&(?!(?:amp|lt|gt|quot|apos);)[A-Za-z][A-Za-z0-9]*;/
        return Data(text.replacing(htmlEntity, with: " ").utf8)
    }

    private static func localName(_ qualifiedName: String) -> String {
        qualifiedName.split(separator: ":").last.map(String.init) ?? qualifiedName
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let name = Self.localName(elementName)
        elements.append(Element(name: name, attributes: attributes))

        switch name {
        case "body":
            isInsideBody = true
        case "script", "style":
            hiddenDepth += 1
        case "img" where isInsideBody && firstImageReference == nil:
            firstImageReference = attributes["src"]
        case "image" where isInsideBody && firstImageReference == nil:
            firstImageReference = attributes["xlink:href"] ?? attributes["href"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        switch Self.localName(elementName) {
        case "body":
            isInsideBody = false
        case "script", "style":
            hiddenDepth = max(hiddenDepth - 1, 0)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideBody, hiddenDepth == 0 else { return }
        bodyTextLength += string.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }
}
