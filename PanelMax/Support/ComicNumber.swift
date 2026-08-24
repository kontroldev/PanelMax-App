import Foundation

/// Orden natural de números de cómic.
///
/// El problema: los números son texto ("0", "1/2", "Anual 2024"), y ordenarlos
/// con `Int(number) ?? 0` manda los especiales al PRINCIPIO de la lista,
/// que es justo donde no van. La regla correcta:
///
/// 1. Los enteros, por valor: 0, 1, 2, 10 (no 0, 1, 10, 2).
/// 2. Los no enteros, al final, en orden natural entre ellos.
///
/// Está separado en su propio tipo por dos motivos: lo usan dos sitios
/// (la lista de la colección y la fuente de catálogo), y es lógica pura,
/// perfecta para probar con tests sin levantar ni SwiftData ni la interfaz.
enum ComicNumber {

    nonisolated static func areInIncreasingOrder(_ lhs: String, _ rhs: String) -> Bool {
        switch (Int(lhs), Int(rhs)) {
        case let (left?, right?):
            return left < right
        case (.some, .none):
            return true          // enteros antes que especiales
        case (.none, .some):
            return false
        case (.none, .none):
            // "Anual 2023" antes que "Anual 2024", "1/2" antes que "3/4"...
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    /// Azúcar para ordenar colecciones de cosas que tienen número.
    nonisolated static func sorted<T>(_ items: [T], by number: (T) -> String) -> [T] {
        items.sorted { areInIncreasingOrder(number($0), number($1)) }
    }
}
