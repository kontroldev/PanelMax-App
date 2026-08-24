import Foundation

/// Configuración de la fuente remota sin secretos dentro de la aplicación.
///
/// En una distribución de App Store, `baseURL` debe apuntar a un proxy controlado
/// por PanelMax. Ese proxy es quien guarda la credencial del proveedor. La URL del
/// proxy no es secreta y se inyecta mediante `PANELMAX_CATALOG_BASE_URL`.
struct CatalogConfiguration: Sendable {
    let baseURL: URL
    let authorization: MetronCatalogSource.Authorization

    /// Configuración apta para distribuir. Nunca lee usuarios, contraseñas o tokens
    /// del Info.plist porque cualquier valor de ese fichero puede extraerse del IPA.
    static func bundled(in bundle: Bundle = .main) -> CatalogConfiguration? {
        guard
            let value = bundle.object(forInfoDictionaryKey: "PANELMAX_CATALOG_BASE_URL") as? String,
            let baseURL = validatedURL(value)
        else { return nil }

        return CatalogConfiguration(baseURL: baseURL, authorization: .none)
    }

    #if DEBUG
    /// Acceso directo a Metron únicamente para desarrollo local. Las credenciales
    /// se añaden como variables del Scheme y no quedan guardadas en el repositorio.
    static func local(environment: [String: String] = ProcessInfo.processInfo.environment) -> CatalogConfiguration? {
        if let value = environment["PANELMAX_CATALOG_BASE_URL"],
           let baseURL = validatedURL(value) {
            return CatalogConfiguration(baseURL: baseURL, authorization: .none)
        }

        let baseURL = URL(string: "https://metron.cloud/api/")!

        if let token = nonEmpty(environment["METRON_API_TOKEN"]) {
            return CatalogConfiguration(baseURL: baseURL, authorization: .bearer(token))
        }

        if let username = nonEmpty(environment["METRON_USER"]),
           let password = nonEmpty(environment["METRON_PASSWORD"]) {
            return CatalogConfiguration(baseURL: baseURL,
                                        authorization: .basic(username: username, password: password))
        }

        return nil
    }
    #endif

    private static func validatedURL(_ rawValue: String) -> URL? {
        guard
            let value = nonEmpty(rawValue),
            !value.contains("$("),
            let url = URL(string: value),
            url.scheme?.lowercased() == "https",
            url.host != nil,
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil
        else { return nil }

        return url
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum CatalogSourceFactory {
    static func make() -> any CatalogSource {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["PANELMAX_USE_LIVE_CATALOG"] == "1" else {
            return MockCatalogSource()
        }

        guard let configuration = CatalogConfiguration.local(environment: environment) else {
            return UnavailableCatalogSource()
        }
        #else
        guard let configuration = CatalogConfiguration.bundled() else {
            return UnavailableCatalogSource()
        }
        #endif

        return MetronCatalogSource(configuration: configuration)
    }
}

/// Fuente explícita para builds sin backend configurado. Evita tanto datos ficticios
/// en producción como un fallo opaco por credenciales ausentes.
struct UnavailableCatalogSource: CatalogSource {
    let attribution = CatalogAttribution(
        name: "Catálogo no configurado",
        url: URL(string: "https://github.com/kontroldev/PanelMax-App")!,
        licenseNote: "El catálogo remoto no está disponible en esta compilación."
    )

    func searchSeries(query: String) async throws -> [SeriesSummary] {
        throw CatalogError.unavailable
    }

    func series(id: String) async throws -> SeriesSummary {
        throw CatalogError.unavailable
    }

    func issues(seriesID: String) async throws -> [IssueSummary] {
        throw CatalogError.unavailable
    }

    func upcoming(seriesIDs: [String]) async throws -> [IssueSummary] {
        throw CatalogError.unavailable
    }

    func issue(barcode: String) async throws -> IssueSummary? {
        throw CatalogError.unavailable
    }
}
