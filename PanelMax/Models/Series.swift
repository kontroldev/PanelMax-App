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
    ///
    /// Resto del diseño con catálogo remoto: ninguna vista lo lee hoy. En
    /// v1.0, sin red, la portada real es `coverImageFilename`.
    var coverURLString: String?

    /// Nombre del archivo de portada que el usuario ha elegido a mano desde
    /// la Fototeca, guardado en `Documents/Covers` (mismo sitio y mismas
    /// reglas de nombre seguro que usa `LocalComicFile.thumbnailFilename`).
    /// `nil` si no ha elegido ninguna: la portada es opcional.
    var coverImageFilename: String?

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
         coverImageFilename: String? = nil,
         totalIssues: Int = 0) {
        self.catalogID = catalogID
        self.title = title
        self.publisher = publisher
        self.startYear = startYear
        self.summary = summary
        self.coverURLString = coverURLString
        self.coverImageFilename = coverImageFilename
        self.totalIssues = totalIssues
        self.dateAdded = Date()
    }

    // MARK: - Propiedades calculadas

    var coverURL: URL? {
        guard let coverURLString else { return nil }
        return URL(string: coverURLString)
    }

    /// URL local de la portada elegida a mano, si el nombre de archivo
    /// guardado sigue siendo válido. Nunca lanza: igual que
    /// `LocalComicFile.thumbnailURL`, una portada es una mejora visual, no
    /// algo que deba interrumpir el resto de la pantalla si falla.
    var coverImageURL: URL? {
        guard let coverImageFilename else { return nil }
        return try? LocalComicFile.coverStorageURL(for: coverImageFilename)
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

    /// Amplitud máxima que se rastrea en busca de huecos.
    ///
    /// Ninguna colección real llega aquí: Action Comics, de las series más
    /// largas que existen, ronda los 1.100 números. El techo protege del caso
    /// patológico. El alta por rango ya limita a 2.000 números de golpe, pero
    /// el alta suelta es un campo de texto libre: quien teclee «99999» en vez
    /// de «99» dejaría a `missingNumbers` construyendo un array de cien mil
    /// elementos, y `CollectionView` lo pide dos veces por serie y por render.
    static let maximumGapSpan = 5_000

    /// Números poseídos como conjunto.
    ///
    /// No reutiliza `ownedNumbers` a propósito: allí se paga un `sorted()`
    /// que aquí se tira, porque buscar huecos solo necesita pertenencia.
    private var ownedNumbersSet: Set<Int> {
        Set(allOwnedIssues.compactMap { Int($0.number) })
    }

    /// Los huecos de la colección: qué números faltan entre el primero y el último que tienes.
    /// Esta es la función que engancha al coleccionista, así que merece estar bien probada.
    var missingNumbers: [Int] {
        let owned = ownedNumbersSet
        guard let first = owned.min(), let last = owned.max(), first < last else { return [] }
        // Amplitud imposible en una colección real: casi con seguridad es un
        // número mal tecleado. Se prefiere no enseñar huecos a congelar la lista.
        guard last - first <= Self.maximumGapSpan else { return [] }
        return (first...last).filter { !owned.contains($0) }
    }

    /// Porcentaje de la serie completado, de 0 a 1. Nil si no sabemos cuántos números tiene.
    /// Usa `allOwnedIssues` en lugar de `ownedNumbers` para incluir especiales (anuales, etc.)
    var completion: Double? {
        guard totalIssues > 0 else { return nil }
        return min(Double(allOwnedIssues.count) / Double(totalIssues), 1)
    }
}
