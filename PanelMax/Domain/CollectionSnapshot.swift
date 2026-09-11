import Foundation
import SwiftData

/// Series visibles con sus números ya filtrados y ordenados, según el estado
/// elegido y el texto de búsqueda.
///
/// Vive en `Domain/`, no en `Features/Collection/`, a propósito: es lógica de
/// negocio pura (no importa SwiftUI) que decide QUÉ se enseña en «Mi
/// colección», independiente de CÓMO se pinta. Eso es lo que permite
/// probarla directamente (`CollectionSnapshotTests`) sin levantar ninguna vista.
struct CollectionSnapshot {

    struct Group: Identifiable {
        let series: Series
        let issues: [Issue]
        /// Porcentaje y huecos calculados UNA vez, aquí. Ambos recorren los
        /// números de la serie, así que no deben pedirse desde el cuerpo.
        let completion: Double?
        let missingCount: Int
        var id: PersistentIdentifier { series.persistentModelID }
    }

    let groups: [Group]

    init(series: [Series], filter: CollectionState, query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var groups: [Group] = []

        for serie in series {
            let allIssues = serie.issues ?? []

            // Una serie recién creada todavía no tiene ningún número. Debe
            // aparecer igual: su cabecera es la ÚNICA puerta a la ficha donde
            // se añaden. Sin esto queda huérfana en la base de datos, sin forma
            // de abrirla, rellenarla ni borrarla.
            let isNewlyCreated = allIssues.isEmpty

            var matching = allIssues.filter { issue in
                guard let state = issue.entry?.state else { return false }
                // «Lo tengo» incluye también lo leído: si lo has leído, lo tienes.
                return state == filter || (filter == .owned && state == .read)
            }

            // Ojo a la diferencia: una serie SIN números se muestra; una serie
            // cuyos números no casan con el filtro se oculta, que es filtrar bien.
            guard !matching.isEmpty || isNewlyCreated else { continue }

            // Orden natural: el "1/2" y los anuales van al final, no al principio.
            matching.sort { ComicNumber.areInIncreasingOrder($0.number, $1.number) }

            if !normalizedQuery.isEmpty {
                let seriesMatches = serie.title.lowercased().contains(normalizedQuery)
                if !seriesMatches {
                    matching = matching.filter {
                        $0.number.lowercased().contains(normalizedQuery)
                            || $0.title.lowercased().contains(normalizedQuery)
                    }
                    // Si el título no casa, hace falta al menos un número que sí.
                    // Una serie vacía no tiene ninguno, así que aquí sí se va.
                    guard !matching.isEmpty else { continue }
                }
            }

            groups.append(Group(series: serie,
                                issues: matching,
                                completion: serie.completion,
                                missingCount: serie.missingNumbers.count))
        }

        self.groups = groups
    }
}
