import Foundation
import SwiftData
@testable import PanelMax

/// Contenedor en memoria con el esquema real de la app.
///
/// Usa `Schema.panelMax` a propósito: si algún día se añade un modelo y se
/// olvida en el esquema, los tests fallan igual que la app en lugar de pasar
/// contra un esquema de mentira.
@MainActor
func makeTestContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(schema: .panelMax, isStoredInMemoryOnly: true)
    return try ModelContainer(for: .panelMax, configurations: [configuration])
}

/// Crea una serie con los números indicados ya metidos en la colección.
///
/// - Parameters:
///   - numbers: números tal y como los devuelve el catálogo, en texto.
///   - state: estado con el que se guardan todos ellos.
///   - totalIssues: total publicado según el catálogo, para `completion`.
@MainActor
@discardableResult
func makeSeries(in context: ModelContext,
                catalogID: String = "s1",
                numbers: [String],
                state: CollectionState = .owned,
                totalIssues: Int = 0) -> Series {

    let series = Series(catalogID: catalogID, title: "Serie", totalIssues: totalIssues)
    context.insert(series)

    for number in numbers {
        let issue = Issue(catalogID: "\(catalogID)-\(number)", number: number)
        issue.series = series
        context.insert(issue)

        let entry = CollectionEntry(state: state)
        entry.issue = issue
        context.insert(entry)
    }

    return series
}
