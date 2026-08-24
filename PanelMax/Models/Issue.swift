import Foundation
import SwiftData

/// Un número concreto de una serie.
@Model
final class Issue {

    var catalogID: String = ""

    /// Número en texto, no en entero: existen el "0", el "1/2" y los anuales.
    var number: String = ""

    var title: String = ""
    var coverDate: Date?
    var coverURLString: String?
    var pageCount: Int = 0

    /// Serie a la que pertenece. Opcional por exigencia de CloudKit.
    var series: Series?

    /// Ficha de colección: si es nil, el número está en el catálogo pero no en tu estantería.
    @Relationship(deleteRule: .cascade, inverse: \CollectionEntry.issue)
    var entry: CollectionEntry?

    /// Progreso de lectura, si se ha empezado a leer.
    @Relationship(deleteRule: .cascade, inverse: \ReadingProgress.issue)
    var progress: ReadingProgress?

    /// Archivo local asociado, si el usuario ha importado el CBZ de este número.
    @Relationship(deleteRule: .nullify, inverse: \LocalComicFile.issue)
    var file: LocalComicFile?

    init(catalogID: String,
         number: String,
         title: String = "",
         coverDate: Date? = nil,
         coverURLString: String? = nil,
         pageCount: Int = 0) {
        self.catalogID = catalogID
        self.number = number
        self.title = title
        self.coverDate = coverDate
        self.coverURLString = coverURLString
        self.pageCount = pageCount
    }

    var coverURL: URL? {
        guard let coverURLString else { return nil }
        return URL(string: coverURLString)
    }

    /// "Nº 12" o "Nº 12 · La caída", según haya título.
    var displayName: String {
        title.isEmpty ? "Nº \(number)" : "Nº \(number) · \(title)"
    }

    /// ¿Se puede leer? Solo si hay un archivo importado detrás.
    var isReadable: Bool { file != nil }
}
