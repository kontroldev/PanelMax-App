import Foundation

/// Cómic corto de ejemplo, con dibujos propios generados por
/// `scripts/make_review_comic.swift` (sin arte ni marcas de terceros).
///
/// Sirve para que el usuario, y sobre todo el revisor de App Store en un
/// dispositivo limpio, puedan probar el lector sin importar nada antes.
///
/// A diferencia del antiguo `SampleLibrarySeeder`, NO se copia a la
/// Biblioteca: se abre directamente desde el paquete de la app, en solo
/// lectura y sin guardar progreso. Así no aparece un cómic que el usuario
/// no ha importado.
enum SampleComic {

    static let title = "Cómic de ejemplo"

    /// `nil` solo si el recurso no se ha empaquetado; en ese caso la interfaz
    /// esconde el botón en vez de ofrecer algo que no se puede abrir.
    static var url: URL? {
        Bundle.main.url(forResource: "Sample-Comic", withExtension: "cbz")
    }
}
