import Foundation

/// Enlaces legales de la app, en un único sitio para que Perfil (y cualquier
/// pantalla futura) los comparta sin duplicar URLs.
///
/// Vivía dentro de `PaywallView`. Al aparcar el muro de pago para la 1.0 se
/// mudó aquí para que Perfil siguiera compilando sin depender de código que
/// ya no forma parte del target (ver `Parked/README.md`).
enum LegalLinks {

    /// Condiciones de uso publicadas en la web de Viñe.
    static let terms = URL(string: "https://kontroldesignstudio.com/vine/terms")!

    /// Política de privacidad publicada en la web de Viñe.
    static let privacy = URL(string: "https://kontroldesignstudio.com/vine/privacy")!

    /// Soporte publicado en la web de Viñe.
    static let support = URL(string: "https://kontroldesignstudio.com/vine/support")!
}
