import SwiftUI

/// Paleta y tipografía de la app, en un único sitio.
///
/// Los colores se definen en código y no en el catálogo de recursos a propósito:
/// así el proyecto compila nada más arrastrarlo a Xcode, sin dependencias de assets.
/// Cuando quieras afinarlos, muévelos a un Color Set y cámbialos aquí por `Color("Accent")`.
enum Theme {

    /// Rojo de la marca. El mismo del logotipo del boceto.
    static let accent = Color(red: 0.847, green: 0.137, blue: 0.165)   // #D8232A

    /// Oro de premium. Solo aparece en lo relacionado con la suscripción,
    /// nunca en la interfaz normal: si el oro está en todas partes, deja de significar "de pago".
    static let premium = Color(red: 0.690, green: 0.537, blue: 0.000)  // #B08900

    static let premiumSoft = Color(red: 1.0, green: 0.969, blue: 0.863) // #FFF7DC

    /// Fondos y separadores que se adaptan solos al modo oscuro.
    static let placeholder = Color(.secondarySystemFill)
    static let secondaryText = Color(.secondaryLabel)
    static let hairline = Color(.separator)
    static let groupedBackground = Color(.systemGroupedBackground)

    // MARK: - Tipografía

    /// Título de sección del Home: pequeño, en mayúsculas y muy espaciado.
    /// Es lo que da el aire de "portada de cómic" sin necesidad de fuentes de pago.
    static func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.6)
            .foregroundStyle(secondaryText)
    }
}

/// Insignia de premium reutilizable.
struct PremiumBadge: View {
    var text: String = "PREMIUM"

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.premiumSoft, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Theme.premium)
            .overlay {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.premium, lineWidth: 0.5)
            }
    }
}
