import Foundation

/// Los límites del plan gratuito, en un solo sitio.
///
/// Cambiar aquí un número cambia la app entera. Si estos valores estuvieran
/// repartidos por las vistas, tocarlos sería una tarde de trabajo.
enum FreeLimits {
    /// Números que se pueden guardar en la colección sin pagar.
    static let collectionEntries = 50

    /// Archivos CBZ/PDF que se pueden importar sin pagar.
    static let importedFiles = 3

    /// Series que se pueden seguir en el plan gratuito.
    static let followedSeries = 2
}

/// Motivos por los que aparece el muro de pago.
/// Sirven para que el muro explique QUÉ acaba de intentar hacer el usuario,
/// que es lo que hace que convierta.
enum PaywallReason: Identifiable, Hashable {
    case collectionFull
    case importLimit
    case followLimit
    case general

    var id: Self { self }

    var headline: String {
        switch self {
        case .collectionFull:  return "Has llegado a \(FreeLimits.collectionEntries) números"
        case .importLimit:     return "Has importado \(FreeLimits.importedFiles) cómics"
        case .followLimit:     return "Sigues ya \(FreeLimits.followedSeries) series"
        case .general:         return "Tu colección sin límites"
        }
    }

    var detail: String {
        switch self {
        case .collectionFull:
            return "Con PanelMax+ guardas todos los que quieras y no pierdes nada de lo que ya tienes."
        case .importLimit:
            return "Con PanelMax+ importas todos los archivos que quieras desde Archivos o iCloud Drive."
        case .followLimit:
            return "Con PanelMax+ sigues todas las series que quieras."
        case .general:
            return "Guarda todos los números que quieras e importa tus archivos CBZ y PDF sin límites."
        }
    }
}

/// Comprueba si una acción está permitida con el plan actual.
///
/// Se usa así en las vistas:
/// ```
/// if let reason = gate.check(.addToCollection, currentCount: count) {
///     paywallReason = reason   // enseña el muro
/// } else {
///     añadirDeVerdad()
/// }
/// ```
@MainActor
struct PremiumGate {

    let isPremium: Bool

    enum Action {
        case addToCollection(current: Int)
        case importFile(current: Int)
        case followSeries(current: Int)
    }

    /// Devuelve nil si la acción se puede hacer. Si no, el motivo del muro.
    func check(_ action: Action) -> PaywallReason? {
        guard !isPremium else { return nil } // premium no tiene límites

        switch action {
        case .addToCollection(let current):
            return current >= FreeLimits.collectionEntries ? .collectionFull : nil
        case .importFile(let current):
            return current >= FreeLimits.importedFiles ? .importLimit : nil
        case .followSeries(let current):
            return current >= FreeLimits.followedSeries ? .followLimit : nil
        }
    }
}
