import Foundation
import SwiftData
import Testing
@testable import PanelMax

/// La lógica que engancha al coleccionista: qué números faltan y cuánto llevas.
///
/// El propio código la señalaba como la parte que "merece estar bien probada"
/// y no tenía ni un test. Estos cubren los casos límite que se dan en una
/// colección real, no solo el camino feliz.
@Suite("Huecos y progreso de una serie")
@MainActor
struct CollectionMathTests {

    // MARK: - missingNumbers

    @Test("Detecta los huecos entre el primero y el último que tienes")
    func findsGaps() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "2", "3", "5", "6", "8"])

        #expect(series.missingNumbers == [4, 7])
    }

    @Test("Sin huecos no inventa números por encima del último")
    func noGapsWhenConsecutive() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "2", "3"], totalIssues: 10)

        // Le faltan del 4 al 10 según el catálogo, pero `missingNumbers` solo
        // habla de huecos INTERNOS. Los que aún no has comprado no son huecos.
        #expect(series.missingNumbers.isEmpty)
    }

    @Test("Un solo número no produce huecos")
    func singleIssueHasNoGaps() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["7"])

        #expect(series.missingNumbers.isEmpty)
    }

    @Test("Una amplitud desmesurada no rastrea huecos")
    func absurdSpanIsIgnored() throws {
        let context = ModelContext(try makeTestContainer())
        // El caso real: teclear «99999» en vez de «99» en el alta suelta, que
        // no tiene el tope de 2.000 del alta por rango. Sin techo, esto
        // construiría un array de casi cien mil elementos.
        let series = makeSeries(in: context, numbers: ["1", "99999"])

        #expect(series.missingNumbers.isEmpty)
    }

    @Test("Justo en el techo todavía se rastrea")
    func spanAtTheLimitStillWorks() throws {
        let context = ModelContext(try makeTestContainer())
        // La amplitud es exactamente `maximumGapSpan`, así que entra.
        let last = 1 + Series.maximumGapSpan
        let series = makeSeries(in: context, numbers: ["1", String(last)])

        #expect(series.missingNumbers.count == Series.maximumGapSpan - 1)
    }

    @Test("Una serie vacía no produce huecos")
    func emptySeriesHasNoGaps() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: [])

        #expect(series.missingNumbers.isEmpty)
        #expect(series.ownedNumbers.isEmpty)
    }

    @Test("El orden de entrada no altera el resultado")
    func orderDoesNotMatter() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["10", "2", "1"])

        #expect(series.ownedNumbers == [1, 2, 10])
        #expect(series.missingNumbers == Array(3...9))
    }

    @Test("Los especiales no cuentan como huecos ni rompen el rango")
    func specialsDoNotCreateGaps() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "1/2", "3", "Anual 2024"])

        // "1/2" y "Anual 2024" no son enteros: quedan fuera de `ownedNumbers`
        // pero siguen contando como poseídos en `allOwnedIssues`.
        #expect(series.ownedNumbers == [1, 3])
        #expect(series.missingNumbers == [2])
        #expect(series.allOwnedIssues.count == 4)
    }

    @Test("Una serie de solo especiales no produce huecos")
    func onlySpecials() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["Anual 2023", "Anual 2024"])

        #expect(series.ownedNumbers.isEmpty)
        #expect(series.missingNumbers.isEmpty)
        #expect(series.allOwnedIssues.count == 2)
    }

    // MARK: - Estados

    @Test("Lo deseado no cuenta como poseído")
    func wantedIsNotOwned() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "2"], state: .wanted)

        #expect(series.ownedNumbers.isEmpty)
        #expect(series.allOwnedIssues.isEmpty)
    }

    @Test("Lo leído sí cuenta como poseído")
    func readCountsAsOwned() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "2"], state: .read)

        #expect(series.ownedNumbers == [1, 2])
        #expect(series.allOwnedIssues.count == 2)
    }

    @Test("Un hueco marcado como deseado sigue siendo un hueco")
    func wantedIssueStillCountsAsGap() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "3"])

        // El usuario marca el 2 como "lo quiero": no lo tiene todavía.
        let wanted = Issue(catalogID: "s1-2", number: "2")
        wanted.series = series
        context.insert(wanted)
        let entry = CollectionEntry(state: .wanted)
        entry.issue = wanted
        context.insert(entry)

        #expect(series.missingNumbers == [2])
    }

    // MARK: - completion

    @Test("Sin total de catálogo no hay porcentaje que enseñar")
    func completionIsNilWithoutTotal() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "2"], totalIssues: 0)

        #expect(series.completion == nil)
    }

    @Test("El porcentaje se calcula sobre el total del catálogo")
    func completionUsesCatalogTotal() throws {
        let context = ModelContext(try makeTestContainer())
        let series = makeSeries(in: context, numbers: ["1", "2", "3"], totalIssues: 12)

        #expect(series.completion == 0.25)
    }

    @Test("El porcentaje nunca pasa del 100 %")
    func completionIsClamped() throws {
        let context = ModelContext(try makeTestContainer())
        // Catálogo desactualizado: dice 2 números pero el usuario tiene 4.
        let series = makeSeries(in: context, numbers: ["1", "2", "3", "4"], totalIssues: 2)

        #expect(series.completion == 1)
    }

    // MARK: - displayTitle

    @Test("El título muestra el año solo si el catálogo lo trae")
    func displayTitle() throws {
        let withYear = Series(catalogID: "a", title: "Cuervo Negro", startYear: 2021)
        let withoutYear = Series(catalogID: "b", title: "Cuervo Negro")

        #expect(withYear.displayTitle == "Cuervo Negro (2021)")
        #expect(withoutYear.displayTitle == "Cuervo Negro")
    }
}

/// Progreso propio del archivo importado, que es la fuente que usa el lector.
@Suite("Progreso del archivo importado")
@MainActor
struct LocalComicFileProgressTests {

    @Test("Sin páginas no se guarda nada")
    func ignoresEmptyArchive() {
        let file = LocalComicFile(displayName: "Cómic")
        file.updateProgress(page: 5, totalPages: 0)

        #expect(file.currentPage == 0)
        #expect(file.lastReadAt == nil)
        #expect(file.isFinished == false)
    }

    @Test("La página se limita al rango real del archivo")
    func clampsPage() {
        let file = LocalComicFile(displayName: "Cómic")
        file.updateProgress(page: 500, totalPages: 32)

        #expect(file.currentPage == 31)
        #expect(file.pageCount == 32)
        #expect(file.isFinished)
    }

    @Test("Una página negativa no rompe el progreso")
    func clampsNegativePage() {
        let file = LocalComicFile(displayName: "Cómic")
        file.updateProgress(page: -3, totalPages: 32)

        #expect(file.currentPage == 0)
        #expect(file.isFinished == false)
    }

    @Test("Sin haber leído nunca no hay fracción ni texto de posición")
    func noProgressBeforeFirstRead() {
        let file = LocalComicFile(displayName: "Cómic")
        file.pageCount = 32

        #expect(file.progressFraction == 0)
        #expect(file.progressDescription == nil)
    }

    @Test("La fracción se cuenta sobre páginas leídas, no sobre el índice")
    func fractionCountsPagesRead() {
        let file = LocalComicFile(displayName: "Cómic")
        file.updateProgress(page: 15, totalPages: 32)

        #expect(file.progressFraction == 16.0 / 32.0)
        #expect(file.progressDescription == "Pág. 16 / 32")
    }
}
