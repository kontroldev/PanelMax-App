import Foundation
import SwiftData

/// Estado de un número dentro de la colección del usuario.
enum CollectionState: String, Codable, CaseIterable, Identifiable {
    case owned      // lo tengo
    case wanted     // lo quiero
    case read       // lo he leído (puede tenerse o no)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .owned:  return "En la colección"
        case .wanted: return "Lo quiero"
        case .read:   return "Leído"
        }
    }

    var systemImage: String {
        switch self {
        case .owned:  return "checkmark.circle.fill"
        case .wanted: return "heart.fill"
        case .read:   return "book.closed.fill"
        }
    }
}

/// Formato en el que se posee el número. Importa: mucha gente cataloga papel.
enum CollectionFormat: String, Codable, CaseIterable, Identifiable {
    case physical
    case digital

    var id: String { rawValue }

    var label: String {
        switch self {
        case .physical: return "Papel"
        case .digital:  return "Digital"
        }
    }
}

/// Ficha que une un número con la estantería del usuario.
@Model
final class CollectionEntry {

    /// Guardamos el `rawValue` en vez del enum: es más resistente a migraciones.
    var stateRaw: String = CollectionState.owned.rawValue
    var formatRaw: String = CollectionFormat.physical.rawValue

    var dateAdded: Date = Date()

    /// Valoración de 0 a 5. Cero significa "sin valorar".
    var rating: Int = 0

    var notes: String = ""

    var issue: Issue?

    init(state: CollectionState = .owned,
         format: CollectionFormat = .physical,
         rating: Int = 0,
         notes: String = "") {
        self.stateRaw = state.rawValue
        self.formatRaw = format.rawValue
        self.rating = rating
        self.notes = notes
        self.dateAdded = Date()
    }

    // Accesos cómodos al enum sin renunciar a guardar String.
    var state: CollectionState {
        get { CollectionState(rawValue: stateRaw) ?? .owned }
        set { stateRaw = newValue.rawValue }
    }

    var format: CollectionFormat {
        get { CollectionFormat(rawValue: formatRaw) ?? .physical }
        set { formatRaw = newValue.rawValue }
    }
}
