import Foundation

/// Fuente de catálogo compatible con la API REST de Metron.
///
/// La app distribuida no debe conectarse a Metron con una credencial incrustada.
/// En Release, esta fuente recibe la URL HTTPS de un proxy propio que guarda el
/// secreto en el servidor. El acceso directo solo se habilita localmente desde el
/// Scheme de Xcode; consulta `CatalogConfiguration` y el README.
final class MetronCatalogSource: CatalogSource {

    enum Authorization: Sendable, Equatable {
        case none
        case bearer(String)
        case basic(username: String, password: String)

        fileprivate var headerValue: String? {
            switch self {
            case .none:
                return nil
            case .bearer(let token):
                return "Bearer \(token)"
            case .basic(let username, let password):
                let rawValue = "\(username):\(password)"
                return "Basic \(Data(rawValue.utf8).base64EncodedString())"
            }
        }
    }

    private let baseURL: URL
    private let authorization: Authorization
    private let session: URLSession
    private let maximumPageCount = 100
    private let upcomingCache = UpcomingCache()

    let attribution = CatalogAttribution(
        name: "Metron",
        url: URL(string: "https://metron.cloud")!,
        licenseNote: "Datos de series y números cortesía de Metron."
    )

    convenience init(configuration: CatalogConfiguration) {
        self.init(baseURL: configuration.baseURL,
                  authorization: configuration.authorization)
    }

    /// Inicializador inyectable para pruebas y para herramientas de desarrollo.
    init(baseURL: URL,
         authorization: Authorization = .none,
         session: URLSession? = nil) {
        self.baseURL = baseURL
        self.authorization = authorization

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.urlCache = URLCache(memoryCapacity: 20_000_000,
                                              diskCapacity: 200_000_000)
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - CatalogSource

    func searchSeries(query: String) async throws -> [SeriesSummary] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Una búsqueda vacía sirve como escaparate inicial. Descargar el catálogo
        // completo aquí sería lento y agotaría innecesariamente el rate limit.
        if normalized.isEmpty {
            let page: Paginated<MetronSeries> = try await getPage("series/")
            return page.results.map(\.asSummary)
        }

        let items: [MetronSeries] = try await getAllPages("series/", query: ["name": normalized])
        return items.map(\.asSummary)
    }

    func series(id: String) async throws -> SeriesSummary {
        let item: MetronSeries = try await get(makeURL("series/\(id)/"))
        return item.asSummary
    }

    func issues(seriesID: String) async throws -> [IssueSummary] {
        let items: [MetronIssue] = try await getAllPages(
            "issue/",
            query: ["series_id": seriesID]
        )
        return ComicNumber.sorted(items.map(\.asSummary)) { $0.number }
    }

    func upcoming(seriesIDs: [String]) async throws -> [IssueSummary] {
        let followed = Set(seriesIDs.filter { !$0.isEmpty })
        guard !followed.isEmpty else { return [] }

        let today = Date()
        let endDate = Calendar(identifier: .gregorian)
            .date(byAdding: .weekOfYear, value: 12, to: today) ?? today
        let dateFormatter = Self.makeDateFormatter()

        // Consultar cada serie evita descargar todas las novedades globales y filtrar
        // después, que además podía omitir series seguidas fuera de la primera página.
        var issuesByID: [String: IssueSummary] = [:]
        for seriesID in followed.sorted() {
            try Task.checkCancellation()

            // Las novedades cambian como mucho una vez por semana. Sin caché,
            // seguir diez series consumía diez peticiones cada vez que aparecía
            // Inicio y agotaba el límite de 30/minuto de Metron en dos pasadas.
            if let cached = await upcomingCache.issues(for: seriesID) {
                for issue in cached { issuesByID[issue.id] = issue }
                continue
            }

            let items: [MetronIssue] = try await getAllPages(
                "issue/",
                query: [
                    "series_id": seriesID,
                    "store_date_range_after": dateFormatter.string(from: today),
                    "store_date_range_before": dateFormatter.string(from: endDate)
                ]
            )
            let summaries = items.map(\.asUpcomingSummary)
            await upcomingCache.store(summaries, for: seriesID)
            for issue in summaries {
                issuesByID[issue.id] = issue
            }
        }

        return issuesByID.values.sorted(by: Self.upcomingOrder)
    }

    func issue(barcode: String) async throws -> IssueSummary? {
        let normalized = barcode.filter(\.isNumber)
        guard !normalized.isEmpty else { return nil }

        let upcFilter = normalized.count == 12 ? "upc_starts_with" : "upc"
        let upcPage: Paginated<MetronIssue> = try await getPage(
            "issue/",
            query: [upcFilter: normalized]
        )
        if let match = upcPage.results.first {
            return match.asSummary
        }

        // Algunos tomos usan ISBN/EAN-13 en lugar de UPC.
        guard normalized.count == 13 else { return nil }
        let isbnPage: Paginated<MetronIssue> = try await getPage(
            "issue/",
            query: ["isbn": normalized]
        )
        return isbnPage.results.first?.asSummary
    }

    // MARK: - Paginación

    private func getPage<T: Decodable>(
        _ path: String,
        query: [String: String] = [:]
    ) async throws -> Paginated<T> {
        try await get(makeURL(path, query: query))
    }

    private func getAllPages<T: Decodable>(
        _ path: String,
        query: [String: String] = [:]
    ) async throws -> [T] {
        var nextURL: URL? = makeURL(path, query: query)
        var visitedURLs = Set<String>()
        var results: [T] = []
        var pageCount = 0

        while let pageURL = nextURL {
            try Task.checkCancellation()

            guard visitedURLs.insert(pageURL.absoluteString).inserted else {
                throw CatalogError.invalidResponse
            }

            pageCount += 1
            guard pageCount <= maximumPageCount else {
                throw CatalogError.invalidResponse
            }

            let page: Paginated<T> = try await get(pageURL)
            results.append(contentsOf: page.results)
            nextURL = try validatedNextURL(page.next, relativeTo: pageURL)
        }

        return results
    }

    /// Solo se siguen enlaces de paginación del mismo servicio y dentro de su ruta
    /// base. Así una respuesta comprometida no puede redirigir el cliente a otro host.
    private func validatedNextURL(_ value: String?, relativeTo currentURL: URL) throws -> URL? {
        guard let value else { return nil }
        guard
            let candidate = URL(string: value, relativeTo: currentURL)?.absoluteURL,
            Self.sameOrigin(candidate, baseURL),
            Self.isInsideBasePath(candidate, baseURL)
        else {
            throw CatalogError.invalidResponse
        }
        return candidate
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    private static func isInsideBasePath(_ candidate: URL, _ baseURL: URL) -> Bool {
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        return candidate.path == baseURL.path || candidate.path.hasPrefix(basePath)
    }

    // MARK: - Cliente HTTP

    private func makeURL(_ path: String, query: [String: String] = [:]) -> URL {
        var url = baseURL
        let pathComponents = path.split(separator: "/")
        for (index, component) in pathComponents.enumerated() {
            let isLastDirectory = index == pathComponents.count - 1 && path.hasSuffix("/")
            url.append(
                path: String(component),
                directoryHint: isLastDirectory ? .isDirectory : .notDirectory
            )
        }

        guard !query.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        if let headerValue = authorization.headerValue {
            request.setValue(headerValue, forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CatalogError.invalidResponse
            }

            switch http.statusCode {
            case 200...299:
                break
            case 401, 403:
                throw CatalogError.unauthorized
            case 404:
                throw CatalogError.notFound
            case 429:
                throw CatalogError.rateLimited
            default:
                throw CatalogError.network(URLError(.badServerResponse))
            }

            do {
                // JSONDecoder no se comparte entre llamadas concurrentes.
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .formatted(Self.makeDateFormatter())
                return try decoder.decode(T.self, from: data)
            } catch {
                throw CatalogError.decoding(error)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as CatalogError {
            throw error
        } catch {
            throw CatalogError.network(error)
        }
    }

    private static func upcomingOrder(_ lhs: IssueSummary, _ rhs: IssueSummary) -> Bool {
        switch (lhs.coverDate, rhs.coverDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            if lhs.seriesTitle != rhs.seriesTitle {
                return lhs.seriesTitle.localizedStandardCompare(rhs.seriesTitle) == .orderedAscending
            }
            return ComicNumber.areInIncreasingOrder(lhs.number, rhs.number)
        }
    }

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

// MARK: - Caché de novedades

/// Caché en memoria con caducidad, por serie.
///
/// Es un actor y no un diccionario protegido por candado porque `upcoming`
/// ya es asíncrono y así el aislamiento lo garantiza el compilador.
private actor UpcomingCache {

    private struct Entry {
        let issues: [IssueSummary]
        let storedAt: Date
    }

    /// Media hora. Suficiente para varias visitas seguidas a Inicio sin
    /// quedarse con datos viejos si el usuario deja la app abierta un día.
    private let lifetime: TimeInterval = 30 * 60
    private var entries: [String: Entry] = [:]

    func issues(for seriesID: String) -> [IssueSummary]? {
        guard let entry = entries[seriesID],
              Date().timeIntervalSince(entry.storedAt) < lifetime else {
            entries[seriesID] = nil
            return nil
        }
        return entry.issues
    }

    func store(_ issues: [IssueSummary], for seriesID: String) {
        entries[seriesID] = Entry(issues: issues, storedAt: Date())
    }
}

// MARK: - Respuestas de la API

private struct Paginated<T: Decodable>: Decodable {
    let count: Int
    let next: String?
    let results: [T]
}

private struct MetronSeries: Decodable {
    let id: Int
    let name: String
    let yearBegan: Int?
    let issueCount: Int?
    let publisher: MetronNamed?
    let desc: String?
    let image: URL?

    private enum CodingKeys: String, CodingKey {
        case id, name, series, yearBegan, issueCount, publisher, desc, image
    }

    /// La API actual llama `series` al título mostrado; versiones anteriores y
    /// algunos proxies usaban `name`. Se aceptan ambos contratos para que una
    /// actualización del backend no rompa toda la búsqueda.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)

        if let currentTitle = try container.decodeIfPresent(String.self, forKey: .series) {
            name = currentTitle
        } else {
            name = try container.decode(String.self, forKey: .name)
        }

        yearBegan = try container.decodeIfPresent(Int.self, forKey: .yearBegan)
        issueCount = try container.decodeIfPresent(Int.self, forKey: .issueCount)
        publisher = try? container.decode(MetronNamed.self, forKey: .publisher)
        desc = try container.decodeIfPresent(String.self, forKey: .desc)
        image = try container.decodeIfPresent(URL.self, forKey: .image)
    }

    var asSummary: SeriesSummary {
        SeriesSummary(id: String(id),
                      title: cleanedTitle,
                      publisher: publisher?.name ?? "",
                      startYear: yearBegan,
                      summary: desc ?? "",
                      coverURL: image,
                      issueCount: issueCount ?? 0)
    }

    /// `series` suele venir como «Título (2024)». El año ya se presenta por
    /// separado en la interfaz, por lo que se elimina únicamente ese sufijo exacto.
    private var cleanedTitle: String {
        guard let yearBegan else { return name }
        let suffix = " (\(yearBegan))"
        return name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
    }
}

private struct MetronIssue: Decodable {
    let id: Int
    let series: MetronNamed?
    let number: String
    let coverDate: Date?
    let storeDate: Date?
    let image: URL?
    let pageCount: Int?

    /// Con `convertFromSnakeCase` las claves llegan ya en camelCase, por lo que
    /// los rawValue de abajo son los nombres convertidos.
    private enum CodingKeys: String, CodingKey {
        case id, series, number, coverDate, storeDate, image
        case pageCount          // proxies que normalizan a `page_count`
        case page               // nombre real del campo en la API de Metron
    }

    /// El número de páginas viaja como `page` en Metron. Aceptar también
    /// `page_count` permite que un proxy propio normalice el nombre sin que
    /// el campo se pierda en silencio (antes siempre se decodificaba a nil).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        series = try container.decodeIfPresent(MetronNamed.self, forKey: .series)
        number = try container.decodeIfPresent(String.self, forKey: .number) ?? ""
        coverDate = try container.decodeIfPresent(Date.self, forKey: .coverDate)
        storeDate = try container.decodeIfPresent(Date.self, forKey: .storeDate)
        image = try container.decodeIfPresent(URL.self, forKey: .image)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
            ?? container.decodeIfPresent(Int.self, forKey: .page)
    }

    var asSummary: IssueSummary {
        summary(displayDate: coverDate)
    }

    /// Para «Próximamente» importa la fecha de llegada a tienda. La API filtra
    /// precisamente por `store_date`, que puede no coincidir con la fecha de portada.
    var asUpcomingSummary: IssueSummary {
        summary(displayDate: storeDate ?? coverDate)
    }

    private func summary(displayDate: Date?) -> IssueSummary {
        IssueSummary(id: String(id),
                     seriesID: series.map { String($0.id) } ?? "",
                     seriesTitle: series?.name ?? "",
                     number: number,
                     title: "",
                     coverDate: displayDate,
                     coverURL: image,
                     pageCount: pageCount ?? 0)
    }
}

private struct MetronNamed: Decodable {
    let id: Int
    let name: String
}
