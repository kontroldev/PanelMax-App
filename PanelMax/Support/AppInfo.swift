import Foundation

/// Datos de identidad de la app, en un único sitio.
///
/// Existe por un motivo concreto: al renombrar la app a **Viñe** se cambió
/// `INFOPLIST_KEY_CFBundleDisplayName` en el proyecto, pero quedaron nueve
/// cadenas visibles en el código diciendo todavía «PanelMax». El usuario
/// instalaba «Viñe» y la pantalla de Inicio le daba la bienvenida con otro
/// nombre.
///
/// Leyendo el nombre del propio bundle en vez de repetirlo como literal, ese
/// fallo no puede repetirse: renombrar vuelve a ser cambiar un solo ajuste de
/// build.
///
/// El nombre interno del proyecto de Xcode sigue siendo `PanelMax` a
/// propósito (ver README). Aquí solo se resuelve lo que ve el usuario.
enum AppInfo {

    /// Nombre visible de la app: «Viñe».
    ///
    /// `nonisolated` es obligatorio, no decorativo. El proyecto compila con
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, así que un `static let`
    /// normal quedaría aislado al actor principal. Esta propiedad se lee desde
    /// `errorDescription` de dos `LocalizedError`, que es un requisito de
    /// protocolo de Foundation y NO está aislado: sin `nonisolated`, Swift 6
    /// rechaza el acceso en tiempo de compilación.
    ///
    /// Es seguro: `String` es `Sendable` y el valor es inmutable.
    nonisolated static let displayName: String = {
        let info = Bundle.main.infoDictionary

        // `CFBundleDisplayName` es el nombre que iOS pinta bajo el icono.
        if let name = info?["CFBundleDisplayName"] as? String, !name.isEmpty {
            return name
        }

        // `CFBundleName` es el respaldo cuando no se define el anterior.
        if let name = info?["CFBundleName"] as? String, !name.isEmpty {
            return name
        }

        // Último recurso: en tests unitarios el bundle principal es el del
        // runner, no el de la app, y ninguna de las dos claves existe.
        return "Viñe"
    }()
}
