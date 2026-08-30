import Foundation

/// Enlaces legales de la app, en un único sitio para que Perfil (y cualquier
/// pantalla futura) los comparta sin duplicar URLs.
///
/// Vivía dentro de `PaywallView`. Al aparcar el muro de pago para la 1.0 se
/// mudó aquí para que Perfil siguiera compilando sin depender de código que
/// ya no forma parte del target (ver `Parked/README.md`).
enum LegalLinks {

    /// Licencia estándar de Apple. Vale mientras no haya contrato propio.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Documentos públicos del repositorio. Antes de publicar conviene
    /// alojarlos también con GitHub Pages sobre `docs/`, para no depender de
    /// que el repositorio siga público.
    static let privacy = URL(string: "https://github.com/kontroldev/PanelMax-App/blob/main/docs/PRIVACY.md")!
    static let support = URL(string: "https://github.com/kontroldev/PanelMax-App/blob/main/docs/SUPPORT.md")!
}
