import Testing
@testable import PanelMax

@Suite("Pliegos del lector")
@MainActor
struct SpreadLayoutTests {

    // MARK: - Página única

    @Test("Sin doble página, cada página es su propio pliego")
    func singleModeMapsOneToOne() {
        let layout = SpreadLayout(pageCount: 5, isDouble: false)

        #expect(layout.count == 5)
        #expect(layout.spreads == [.single(0), .single(1), .single(2), .single(3), .single(4)])
    }

    // MARK: - Doble página

    @Test("La portada va sola y el resto se empareja a partir de la página 2")
    func coverIsAlone() {
        let layout = SpreadLayout(pageCount: 7, isDouble: true)

        // 0 sola · (1,2) · (3,4) · (5,6)
        #expect(layout.spreads == [
            .single(0),
            .double(left: 1, right: 2),
            .double(left: 3, right: 4),
            .double(left: 5, right: 6)
        ])
    }

    @Test("Con total par, la última página también queda sola")
    func evenCountLeavesLastAlone() {
        let layout = SpreadLayout(pageCount: 6, isDouble: true)

        // 0 sola · (1,2) · (3,4) · 5 sola
        #expect(layout.spreads == [
            .single(0),
            .double(left: 1, right: 2),
            .double(left: 3, right: 4),
            .single(5)
        ])
    }

    @Test("Un cómic de una sola página no se empareja con nada")
    func singlePageComic() {
        let layout = SpreadLayout(pageCount: 1, isDouble: true)
        #expect(layout.spreads == [.single(0)])
    }

    @Test("Un archivo sin páginas produce un diseño vacío")
    func emptyArchive() {
        let layout = SpreadLayout(pageCount: 0, isDouble: true)
        #expect(layout.isEmpty)
        // No debe reventar al consultarlo.
        #expect(layout.spreadIndex(containing: 3) == 0)
        #expect(layout.firstPage(ofSpreadAt: 2) == 0)
    }

    // MARK: - Conservar la posición al rotar

    @Test("Girar el dispositivo mantiene la página que se estaba leyendo")
    func rotationKeepsPage() {
        let portrait = SpreadLayout(pageCount: 12, isDouble: false)
        let landscape = SpreadLayout(pageCount: 12, isDouble: true)

        // Leyendo la página 7 en vertical…
        let page = 7
        #expect(portrait.spreadIndex(containing: page) == 7)

        // …al girar, la 7 vive en el pliego (7,8), que es el cuarto.
        let landscapeSpread = landscape.spreadIndex(containing: page)
        #expect(landscape[landscapeSpread] == .double(left: 7, right: 8))

        // Y al volver a vertical se aterriza en la 7, no en otra.
        let backToPage = landscape.firstPage(ofSpreadAt: landscapeSpread)
        #expect(portrait.spreadIndex(containing: backToPage) == 7)
    }

    @Test("La página derecha de un pliego se resuelve a ese mismo pliego")
    func rightPageResolvesToItsSpread() {
        let layout = SpreadLayout(pageCount: 10, isDouble: true)

        // La 8 es la mitad derecha de (7,8): ambas dan el mismo índice.
        #expect(layout.spreadIndex(containing: 8) == layout.spreadIndex(containing: 7))
    }

    // MARK: - Casos límite de índices

    @Test("Una página fuera de rango se acota en lugar de romper")
    func outOfRangePageIsClamped() {
        let layout = SpreadLayout(pageCount: 6, isDouble: true)

        #expect(layout.spreadIndex(containing: -5) == 0)
        #expect(layout.spreadIndex(containing: 999) == layout.count - 1)
    }

    @Test("Un índice de pliego fuera de rango se acota")
    func outOfRangeSpreadIsClamped() {
        let layout = SpreadLayout(pageCount: 6, isDouble: true)

        #expect(layout.firstPage(ofSpreadAt: -3) == 0)
        #expect(layout.firstPage(ofSpreadAt: 99) == 5)
    }

    @Test("El deslizador puede saltar a cualquier página y caer en el pliego correcto")
    func everyPageBelongsToExactlyOneSpread() {
        let layout = SpreadLayout(pageCount: 25, isDouble: true)

        for page in 0..<25 {
            let index = layout.spreadIndex(containing: page)
            #expect(layout[index]?.contains(page) == true)
        }
    }
}
