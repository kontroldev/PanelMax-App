import Foundation
import SwiftData

/// Una serie o volumen: "Cuervo Negro Vol. 2".
///
/// Solo se guardan en SwiftData las series que el usuario ha tocado
/// (ha añadido un número, la sigue, o la ha marcado como deseada).
/// El resto del catálogo vive en memoria y se pide a la API cuando hace falta.
@Model
final class Series {

    /// Identificador en el catálogo de origen. No usamos `@Attribute(.unique)`
    /// porque CloudKit no lo admite: la unicidad se garantiza en `SeriesStore.findOrCreate`.
    var catalogID: String = ""

    var title: String = ""
    var publisher: String = ""

    /// Año de inicio. Opcional porque muchas fichas del catálogo no lo traen.
    var startYear: Int?

    var summary: String = ""

    /// URL de la portada representativa. Se guarda como String para evitar
    /// problemas de codificación al sincronizar con CloudKit.
    var coverURLString: String?

    /// Número total de ejemplares publicados, según el catálogo.
    /// Es lo que permite calcular los huecos de la colección.
    var totalIssues: Int = 0

    /// ¿El usuario sigue esta serie? Permite mostrar sus próximos números en Inicio.
    var isFollowed: Bool = false

    var dateAdded: Date = Date()

    /// Números de esta serie que el usuario tiene guardados.
    /// `.cascade`: si se borra la serie, se borran sus números.
    @Relationship(deleteRule: .cascade, inverse: \Issue.series)
    var issues: [Issue]? = []

    init(catalogID: String,
         title: String,
         publisher: String = "",
         startYear: Int? = nil,
         summary: String = "",
         coverURLString: String? = nil,
         totalIssues: Int = 0) {
        self.catalogID = catalogID
        self.title = title
        self.publisher = publisher
        self.startYear = startYear
        self.summary = summary
        self.coverURLString = coverURLString
        self.totalIssues = totalIssues
        self.dateAdded = Date()
    }

    // MARK: - Propiedades calculadas

    var coverURL: URL? {
        guard let coverURLString else { return nil }
        return URL(string: coverURLString)
    }

    /// Título con el año, como se muestra en la lista: "Cuervo Negro (2021)".
    var displayTitle: String {
        guard let startYear else { return title }
        return "\(title) (\(startYear))"
    }

    /// Números que el usuario ya posee, ordenados.
    ///
    /// Incluye todos los números que tienen entrada en la colección EXCEPTO los deseados (.wanted).
    /// Esto permite contar como poseídos tanto los marcados como .owned como los marcados como .read.
    ///
    /// NOTA: Solo incluye números que puedan parsearse como Int. Los especiales como "1/2"
    /// o "Anual" no aparecen aquí, pero sí están en la colección (ver `allOwnedIssues`).
    var ownedNumbers: [Int] {
        (issues ?? [])
            .filter {
                guard let entry = $0.entry else { return false }
                return entry.state != .wanted
            }
            .compactMap { Int($0.number) }
            .sorted()
    }

    /// Todos los números poseídos, incluyendo los especiales (anuales, 1/2, etc.)
    var allOwnedIssues: [Issue] {
        (issues ?? []).filter {
            guard let entry = $0.entry else { return false }
            return entry.state != .wanted
        }
    }

    /// Los huecos de la colección: qué números faltan entre el primero y el último que tienes.
    /// Esta es la función que engancha al coleccionista, así que merece estar bien probada.
    var missingNumbers: [Int] {
        let owned = Set(ownedNumbers)
        guard let first = owned.min(), let last = owned.max(), first < last else { return [] }
        return (first...last).filter { !owned.contains($0) }
    }

    /// Porcentaje de la serie completado, de 0 a 1. Nil si no sabemos cuántos números tiene.
    /// Usa `allOwnedIssues` en lugar de `ownedNumbers` para incluir especiales (anuales, etc.)
    var completion: Double? {
        guard totalIssues > 0 else { return nil }
        return min(Double(allOwnedIssues.count) / Double(totalIssues), 1)
    }
}
