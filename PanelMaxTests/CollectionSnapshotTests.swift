import Foundation
import SwiftData
import Testing
@testable import PanelMax

/// Qué series y qué números llegan a la lista de «Mi colección».
///
/// Existe por un fallo real: una serie recién creada no tiene números, el
/// snapshot la descartaba y su cabecera nunca se dibujaba. Como la cabecera es
/// la única puerta a `SeriesDetailView`, la serie quedaba huérfana en la base
/// de datos: no se podía abrir, ni rellenar, ni borrar. Y le pasaba al primer
/// usuario en su primer minuto de uso.
@Suite("Lista de Mi colección")
@MainActor
struct CollectionSnapshotTests {

    @Test("Una serie recién creada aparece aunque no tenga números")
    func newSeriesWithoutIssuesIsVisible() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: [])

        let snapshot = CollectionSnapshot(series: [series], filter: .owned, query: "")

        #expect(snapshot.groups.count == 1)
        #expect(snapshot.groups.first?.issues.isEmpty == true)
    }

    @Test("Una serie cuyos números no casan con el filtro sí se oculta")
    func seriesWithNonMatchingIssuesIsHidden() throws {
        let context = ModelContext(try makeTestContainer())
        // Tiene números, pero todos son «lo quiero» y el filtro pide «lo tengo».
        // Esto NO es el caso de la serie vacía: aquí ocultar es filtrar bien.
        let series = makeSeries(in: context, numbers: ["1", "2"], state: .wanted)

        let snapshot = CollectionSnapshot(series: [series], filter: .owned, query: "")

        #expect(snapshot.groups.isEmpty)
    }

    @Test("La búsqueda encuentra una serie vacía por su título")
    func emptySeriesIsFoundByTitle() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: [])

        let snapshot = CollectionSnapshot(series: [series], filter: .owned, query: "serie")

        #expect(snapshot.groups.count == 1)
    }

    @Test("La búsqueda descarta una serie vacía si el título no casa")
    func emptySeriesIsFilteredOutByQuery() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: [])

        let snapshot = CollectionSnapshot(series: [series], filter: .owned, query: "batman")

        #expect(snapshot.groups.isEmpty)
    }

    @Test("Lo leído cuenta como poseído en el filtro «lo tengo»")
    func readCountsAsOwned() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1"], state: .read)

        let snapshot = CollectionSnapshot(series: [series], filter: .owned, query: "")

        #expect(snapshot.groups.first?.issues.count == 1)
    }
}
