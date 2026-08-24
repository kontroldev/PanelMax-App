import Foundation
import SwiftUI

/// Contrato de cualquier fuente de catálogo.
///
/// Toda la app habla con este protocolo, nunca con una API concreta.
/// Gracias a esto puedes cambiar de proveedor (Metron, un proxy propio,
/// datos falsos para las previsualizaciones) sin tocar ni una vista.
protocol CatalogSource: Sendable {

    /// Busca series por texto libre.
    func searchSeries(query: String) async throws -> [SeriesSummary]

    /// Ficha completa de una serie.
    func series(id: String) async throws -> SeriesSummary

    /// Todos los números publicados de una serie, ordenados.
    func issues(seriesID: String) async throws -> [IssueSummary]

    /// Novedades de las próximas semanas, para la sección «Próximamente».
    func upcoming(seriesIDs: [String]) async throws -> [IssueSummary]

    /// Busca un número por su código de barras (EAN-13 de la portada).
    /// Devuelve nil si el catálogo no lo reconoce.
    func issue(barcode: String) async throws -> IssueSummary?

    /// Texto de atribución del proveedor configurado, que se muestra en Ajustes.
    /// Antes de distribuir, deben verificarse sus condiciones y requisitos reales.
    var attribution: CatalogAttribution { get }
}

/// Crédito de la fuente de datos. Obligatorio mostrarlo, no es decorativo.
struct CatalogAttribution: Sendable {
    let name: String
    let url: URL
    let licenseNote: String
}

/// Errores que puede devolver una fuente de catálogo.
enum CatalogError: LocalizedError {
    case unavailable
    case unauthorized
    case rateLimited
    case notFound
    case invalidResponse
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "El catálogo no está disponible en esta versión. Consulta Soporte para obtener ayuda."
        case .unauthorized:
            return "El servicio de catálogo ha rechazado la configuración de acceso."
        case .rateLimited:
            return "El catálogo ha limitado las peticiones. Inténtalo en unos minutos."
        case .notFound:
            return "No se ha encontrado ese cómic."
        case .invalidResponse:
            return "El catálogo ha devuelto una respuesta no válida."
        case .network:
            return "No hay conexión con el catálogo."
        case .decoding:
            return "El catálogo ha devuelto datos que no se han podido leer."
        }
    }
}

// MARK: - Inyección por Environment

/// Clave de entorno para la fuente de catálogo.
/// Por defecto, datos falsos: así ninguna previsualización rompe por falta de red.
private struct CatalogSourceKey: EnvironmentKey {
    static let defaultValue: any CatalogSource = MockCatalogSource()
}

extension EnvironmentValues {
    var catalog: any CatalogSource {
        get { self[CatalogSourceKey.self] }
        set { self[CatalogSourceKey.self] = newValue }
    }
}
