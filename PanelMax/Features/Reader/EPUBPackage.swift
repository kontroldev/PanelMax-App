import Foundation

/// Qué imagen corresponde a cada página de un EPUB de cómic.
///
/// Un EPUB es un ZIP con páginas web (XHTML) dentro y un índice (el archivo
/// `.opf`) que dice en qué orden van. Para llegar a las imágenes hay tres
/// pasos:
///
/// 1. `META-INF/container.xml` dice dónde está el `.opf`.
/// 2. El `.opf` tiene el *manifest* (todos los archivos) y el *spine* (el
///    orden de lectura).
/// 3. Cada página del *spine* es un XHTML con, en un EPUB de cómic, una
///    única imagen a página completa.
///
/// Solo se admiten EPUB de **una imagen por página** (maquetación fija, que
/// es como se venden muchos cómics y mangas digitales). Un EPUB de texto,
/// como una novela, o uno cuyas páginas tienen texto real encima del dibujo,
/// se rechaza con un aviso claro: mostrar solo sus imágenes perdería el texto.
///
/// Es lógica pura, sin ZIP ni interfaz: recibe dos funciones para preguntar
/// si un archivo existe y para leerlo. Así se prueba entera con datos en
/// memoria (`EPUBPackageTests`), y `EPUBArchive` solo tiene que conectarla
/// con el ZIP real.
nonisolated struct EPUBPackage: Sendable {

    /// Rutas dentro del ZIP de la imagen de cada página, en orden de lectura.
    let pageImagePaths: [String]

    static let containerPath = "META-INF/container.xml"
    static let encryptionPath = "META-INF/encryption.xml"

    /// Mismo techo que los CBZ (ver `CBZArchive`).
    static let maximumSpineItems = 10_000

    /// Caracteres de texto visible (sin contar espacios) que se toleran en
    /// una página de imagen: «Página 12» o un título corto de capítulo. Más
    /// que eso ya es texto real, como un solo bocadillo (~90 caracteres), que
    /// se perdería al enseñar solo la imagen.
    static let maximumTextPerImagePage = 40

    /// Páginas sin imagen que se toleran: créditos, una página legal... Por
    /// encima, el EPUB es un libro de texto, no un cómic.
    static func maximumNonImagePages(forSpineCount count: Int) -> Int {
        max(2, count / 10)
    }

    /// - Parameters:
    ///   - fileExists: si hay un archivo con esa ruta dentro del ZIP.
    ///   - readFile: el contenido de ese archivo, o `nil` si no existe.
    static func parse(fileExists: (String) -> Bool,
                      readFile: (String) throws -> Data?) throws -> EPUBPackage {
        // 1. Dónde está el índice.
        guard let containerData = try readFile(containerPath),
              let opfReference = EPUBXMLScanner.scan(containerData)
                .elements.first(where: { $0.name == "rootfile" })?.attributes["full-path"],
              let opfPath = resolve(opfReference, relativeTo: ""),
              let opfData = try readFile(opfPath) else {
            throw ComicArchiveError.unsupportedFormat
        }

        // Archivos cifrados. Un EPUB con DRM (Apple Books, Kindle, Adobe)
        // los declara aquí. Las fuentes ofuscadas también aparecen, pero
        // eso no es DRM y no afecta: solo cuentan las páginas e imágenes.
        // Las rutas de este archivo van siempre desde la raíz del ZIP.
        let encryptedPaths: Set<String> = try readFile(encryptionPath).map { data in
            Set(EPUBXMLScanner.scan(data).elements
                .filter { $0.name == "CipherReference" }
                .compactMap { $0.attributes["URI"].flatMap { resolve($0, relativeTo: "") } })
        } ?? []

        // 2. Manifest y spine.
        let opf = EPUBXMLScanner.scan(opfData)
        let opfDirectory = directory(of: opfPath)
        var manifest: [String: (path: String, mediaType: String)] = [:]
        for item in opf.elements where item.name == "item" {
            guard let id = item.attributes["id"],
                  let href = item.attributes["href"],
                  let path = resolve(href, relativeTo: opfDirectory) else { continue }
            manifest[id] = (path, item.attributes["media-type"] ?? "")
        }
        // `linear="no"` marca páginas fuera del orden de lectura (notas,
        // índices emergentes): no forman parte del cómic.
        let spine = opf.elements
            .filter { $0.name == "itemref" && $0.attributes["linear"] != "no" }
            .compactMap { $0.attributes["idref"].flatMap { manifest[$0] } }

        guard !spine.isEmpty else { throw ComicArchiveError.emptyArchive }
        guard spine.count <= maximumSpineItems else { throw ComicArchiveError.tooManyPages }

        // 3. La imagen de cada página.
        var pages: [String] = []
        var nonImagePages = 0
        for item in spine {
            if encryptedPaths.contains(item.path) { throw ComicArchiveError.protectedEPUB }

            let imagePath: String?
            if item.mediaType.hasPrefix("image/") {
                // El spine puede apuntar directamente a una imagen.
                imagePath = item.path
            } else if let data = try readFile(item.path) {
                let page = EPUBXMLScanner.scan(data)
                imagePath = page.bodyTextLength <= maximumTextPerImagePage
                    ? page.firstImageReference.flatMap { resolve($0, relativeTo: directory(of: item.path)) }
                    : nil
            } else {
                imagePath = nil
            }

            if let imagePath, encryptedPaths.contains(imagePath) { throw ComicArchiveError.protectedEPUB }

            if let imagePath, ComicPageImage.isSupported(imagePath), fileExists(imagePath) {
                pages.append(imagePath)
            } else {
                nonImagePages += 1
            }
        }

        guard !pages.isEmpty,
              nonImagePages <= maximumNonImagePages(forSpineCount: spine.count) else {
            throw ComicArchiveError.textEPUB
        }
        return EPUBPackage(pageImagePaths: pages)
    }

    // MARK: - Rutas

    /// Convierte una referencia de un documento (`../images/p1.png`,
    /// `p%201.png#top`) en una ruta dentro del ZIP.
    ///
    /// Devuelve `nil` para todo lo que no sea un archivo del propio EPUB:
    /// direcciones web (la 1.0 no usa la red, y un cómic no debería pedir
    /// nada de fuera), datos incrustados, o rutas que intenten salir de la
    /// raíz del ZIP con `../`.
    static func resolve(_ reference: String, relativeTo directory: String) -> String? {
        var value = reference
        if let index = value.firstIndex(where: { $0 == "#" || $0 == "?" }) {
            value = String(value[..<index])
        }
        guard !value.isEmpty, let decoded = value.removingPercentEncoding else { return nil }

        // Un esquema (`https:`, `data:`, `mailto:`...) aparece antes de la primera barra.
        if let colon = decoded.firstIndex(of: ":"), !decoded[..<colon].contains("/") {
            return nil
        }

        var components = decoded.hasPrefix("/") ? [] : directory.split(separator: "/").map(String.init)
        for component in decoded.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(String(component))
            }
        }
        return components.isEmpty ? nil : components.joined(separator: "/")
    }

    /// Carpeta que contiene una ruta: `OEBPS/text/p1.xhtml` → `OEBPS/text`.
    static func directory(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }
}
