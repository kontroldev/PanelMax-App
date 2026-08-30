import Foundation

/// Cómo se agrupan las páginas de un cómic en pliegos.
///
/// En papel, un cómic abierto enseña dos páginas a la vez, pero la portada va
/// sola: es la cara derecha del primer pliego. Si se emparejan las páginas
/// desde la primera (0-1, 2-3…) el resultado queda desfasado y las viñetas a
/// doble página aparecen partidas entre dos pliegos distintos, que es
/// exactamente lo que hay que evitar.
///
/// La regla correcta es: portada sola, y a partir de ahí (1,2), (3,4), (5,6)…
/// Si el total es par, la última página también queda sola.
///
/// Está en su propio tipo, sin SwiftUI ni UIKit, porque es lógica pura: se
/// puede probar entera sin levantar una vista ni abrir un archivo.
struct SpreadLayout: Equatable {

    enum Spread: Equatable, Identifiable {
        case single(Int)
        case double(left: Int, right: Int)

        var id: Int { firstPage }

        /// Página con la que empieza el pliego. Es la que se guarda como
        /// progreso de lectura y la que ancla la posición al rotar.
        var firstPage: Int {
            switch self {
            case .single(let page):          return page
            case .double(let left, _):       return left
            }
        }

        var pages: [Int] {
            switch self {
            case .single(let page):              return [page]
            case .double(let left, let right):   return [left, right]
            }
        }

        func contains(_ page: Int) -> Bool {
            pages.contains(page)
        }
    }

    let spreads: [Spread]

    var count: Int { spreads.count }
    var isEmpty: Bool { spreads.isEmpty }

    /// - Parameters:
    ///   - pageCount: total de páginas del archivo.
    ///   - isDouble: `false` produce un pliego por página, que es el modo de
    ///     iPhone y el de iPad en vertical.
    init(pageCount: Int, isDouble: Bool) {
        guard pageCount > 0 else {
            spreads = []
            return
        }

        guard isDouble, pageCount > 1 else {
            spreads = (0..<pageCount).map { .single($0) }
            return
        }

        var result: [Spread] = [.single(0)]   // portada sola
        var page = 1
        while page < pageCount {
            if page + 1 < pageCount {
                result.append(.double(left: page, right: page + 1))
                page += 2
            } else {
                result.append(.single(page))  // contraportada suelta
                page += 1
            }
        }
        spreads = result
    }

    /// Índice del pliego que contiene una página.
    ///
    /// Es lo que permite conservar la posición al girar el iPad: la página
    /// leída no cambia, solo cambia el pliego en el que aparece.
    func spreadIndex(containing page: Int) -> Int {
        guard !spreads.isEmpty else { return 0 }
        let clamped = min(max(page, 0), (spreads.last?.pages.last ?? 0))
        return spreads.firstIndex { $0.contains(clamped) } ?? 0
    }

    /// Primera página de un pliego, acotada a un índice válido.
    func firstPage(ofSpreadAt index: Int) -> Int {
        guard !spreads.isEmpty else { return 0 }
        let clamped = min(max(index, 0), spreads.count - 1)
        return spreads[clamped].firstPage
    }

    subscript(index: Int) -> Spread? {
        spreads.indices.contains(index) ? spreads[index] : nil
    }
}
