import Foundation

/// Carpeta raíz de los archivos propios de la app (`Comics/` y `Covers/`).
///
/// Existe para que los tests unitarios no toquen los datos reales. Los tests
/// se ejecutan DENTRO de la app (que hace de anfitriona), así que sin esto
/// importaban, borraban y limpiaban cómics en la misma carpeta `Documents`
/// que usa la app en el simulador: si un test se interrumpía a medias, dejaba
/// archivos en tu biblioteca, y la limpieza de la papelera interna podía
/// afectar a copias que no eran suyas.
///
/// Cuando el proceso es el anfitrión de los tests (Xcode define
/// `XCTestConfigurationFilePath`), la raíz pasa a ser una carpeta temporal
/// nueva para cada ejecución. En una ejecución normal es siempre `Documents`.
enum StorageLocation {

    /// `nonisolated` porque se lee desde el código de archivos que corre en
    /// segundo plano. Es una constante (`let`) de un tipo `Sendable`: segura.
    nonisolated static let root: URL = {
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] != nil else {
            return URL.documentsDirectory
        }
        return FileManager.default.temporaryDirectory
            .appending(path: "PanelMaxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }()
}
