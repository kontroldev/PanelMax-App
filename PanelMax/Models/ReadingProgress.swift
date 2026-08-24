import Foundation
import SwiftData

/// Por dónde va el usuario en un cómic.
/// Se actualiza al salir del lector, no en cada página, para no castigar la batería.
@Model
final class ReadingProgress {

    /// Página actual, empezando en 0.
    var currentPage: Int = 0

    var totalPages: Int = 0
    var lastReadAt: Date = Date()

    /// Se marca como terminado al llegar a la última página.
    var isFinished: Bool = false

    var issue: Issue?

    init(currentPage: Int = 0, totalPages: Int = 0) {
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.lastReadAt = Date()
    }

    /// Fracción leída, de 0 a 1. Se usa en la barra roja de las portadas del Home.
    var fraction: Double {
        guard totalPages > 0 else { return 0 }
        return min(Double(currentPage + 1) / Double(totalPages), 1)
    }

    /// "Pág. 14 / 32", el texto de la cabecera del lector.
    var displayPosition: String {
        "Pág. \(currentPage + 1) / \(max(totalPages, 1))"
    }
}
