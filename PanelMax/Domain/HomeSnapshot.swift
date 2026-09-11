import Foundation
import SwiftData

/// Todo lo que Inicio necesita derivar de la colección, calculado de una vez.
///
/// Lógica pura (sin SwiftUI), igual que `CollectionSnapshot`: las secciones
/// se calculan en memoria sobre las series guardadas, no con predicados de
/// SwiftData, y todo el trabajo se hace UNA vez por evaluación del cuerpo de
/// `HomeView`. Vivir en `Domain/` en vez de `Features/Home/` es lo que
/// permite probarla directamente, sin levantar ninguna vista.
struct HomeSnapshot {

    let collectionSeries: [Series]
    let missingHighlights: [Gap]

    var isEmpty: Bool { collectionSeries.isEmpty }

    init(series: [Series]) {
        var collection: [Series] = []
        var gaps: [Gap] = []

        for serie in series {
            guard !serie.allOwnedIssues.isEmpty else { continue }
            collection.append(serie)

            // Un hueco por serie como máximo: si enseñas los doce que le
            // faltan a alguien, deja de ser una ayuda y es un reproche.
            if let first = serie.missingNumbers.first {
                gaps.append(Gap(series: serie, number: first))
            }
        }

        self.collectionSeries = collection
        self.missingHighlights = gaps
    }

    struct Gap: Identifiable {
        let series: Series
        let number: Int
        /// `persistentModelID` en lugar de `catalogID`: dos series sin id
        /// propio producían la misma clave y SwiftUI reciclaba mal las celdas.
        var id: String { "\(series.persistentModelID.hashValue)-\(number)" }
    }
}
