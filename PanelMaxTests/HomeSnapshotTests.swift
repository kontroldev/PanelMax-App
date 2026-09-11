import Foundation
import SwiftData
import Testing
@testable import PanelMax

/// Qué series y qué huecos llegan a Inicio.
///
/// `HomeSnapshot` vivía como `private struct` dentro de `HomeView` hasta que
/// se sacó a `Domain/`: hasta entonces no había forma de probar esta lógica
/// sin levantar la vista entera.
@Suite("Snapshot de Inicio")
@MainActor
struct HomeSnapshotTests {

    @Test("Una serie sin ningún número poseído no aparece")
    func seriesWithoutOwnedIssuesIsExcluded() throws {
        let context = ModelContext(try makeTestContainer())
        // Solo "deseados": `allOwnedIssues` los excluye a propósito.
        let series = makeSeries(in: context, numbers: ["1", "2"], state: .wanted)

        let snapshot = HomeSnapshot(series: [series])

        #expect(snapshot.isEmpty)
        #expect(snapshot.collectionSeries.isEmpty)
    }

    @Test("Una serie con números poseídos y sin huecos aparece sin destacado")
    func seriesWithoutGapsHasNoHighlight() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "2", "3"])

        let snapshot = HomeSnapshot(series: [series])

        #expect(snapshot.collectionSeries.count == 1)
        #expect(snapshot.missingHighlights.isEmpty)
    }

    @Test("El primer hueco de una serie se destaca")
    func firstGapIsHighlighted() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "3"])

        let snapshot = HomeSnapshot(series: [series])

        #expect(snapshot.missingHighlights.count == 1)
        #expect(snapshot.missingHighlights.first?.number == 2)
    }

    @Test("Una serie con varios huecos solo destaca uno: enseñarlos todos deja de ayudar")
    func onlyFirstGapSurfacesWithMultipleMissing() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "4", "7"])

        let snapshot = HomeSnapshot(series: [series])

        #expect(snapshot.missingHighlights.count == 1)
        #expect(snapshot.missingHighlights.first?.number == 2)
    }
}
