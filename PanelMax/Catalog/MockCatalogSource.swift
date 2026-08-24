import Foundation

/// Catálogo falso, con los cómics inventados del boceto.
///
/// Sirve para tres cosas:
/// 1. Que las previsualizaciones de SwiftUI funcionen siempre.
/// 2. Que puedas desarrollar sin credenciales ni conexión.
/// 3. Que las capturas de la App Store tengan portadas que sí puedes usar.
struct MockCatalogSource: CatalogSource {

    let attribution = CatalogAttribution(
        name: "Datos de ejemplo",
        url: URL(string: "https://example.com")!,
        licenseNote: "Contenido ficticio para desarrollo."
    )

    static let series: [SeriesSummary] = [
        SeriesSummary(id: "1", title: "Cuervo Negro", publisher: "Nocturna",
                      startYear: 2021, summary: "Un detective sin sombra recorre una ciudad que olvidó su nombre.",
                      coverURL: nil, issueCount: 18),
        SeriesSummary(id: "2", title: "Ronin Neón", publisher: "Kaiju Press",
                      startYear: 2023, summary: "Tokio 2098. Una espada, una deuda y treinta y dos horas.",
                      coverURL: nil, issueCount: 12),
        SeriesSummary(id: "3", title: "Ecos de Acero", publisher: "Nocturna",
                      startYear: 2019, summary: "La última fundición humana despierta.",
                      coverURL: nil, issueCount: 24),
        SeriesSummary(id: "4", title: "Astra-9", publisher: "Órbita",
                      startYear: 2024, summary: "Nueve tripulantes, ocho literas.",
                      coverURL: nil, issueCount: 6),
        SeriesSummary(id: "5", title: "Dragón de Hierro", publisher: "Kaiju Press",
                      startYear: 2020, summary: "Artes marciales y metalurgia.",
                      coverURL: nil, issueCount: 30),
        SeriesSummary(id: "6", title: "Némesis", publisher: "Órbita",
                      startYear: 2022, summary: "El villano cuenta su versión.",
                      coverURL: nil, issueCount: 15),
        SeriesSummary(id: "7", title: "Sombra Gris", publisher: "Nocturna",
                      startYear: 2018, summary: "Serie limitada de seis números.",
                      coverURL: nil, issueCount: 6)
    ]

    func searchSeries(query: String) async throws -> [SeriesSummary] {
        try await Task.sleep(for: .milliseconds(250)) // simula latencia de red
        guard !query.isEmpty else { return Self.series }
        return Self.series.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.publisher.localizedCaseInsensitiveContains(query)
        }
    }

    func series(id: String) async throws -> SeriesSummary {
        guard let match = Self.series.first(where: { $0.id == id }) else {
            throw CatalogError.notFound
        }
        return match
    }

    func issues(seriesID: String) async throws -> [IssueSummary] {
        let parent = try await series(id: seriesID)
        return (1...max(parent.issueCount, 1)).map { number in
            IssueSummary(id: "\(seriesID)-\(number)",
                         seriesID: seriesID,
                         seriesTitle: parent.title,
                         number: String(number),
                         title: "",
                         coverDate: Calendar.current.date(byAdding: .month, value: number, to: .now),
                         coverURL: nil,
                         pageCount: 32)
        }
    }

    func upcoming(seriesIDs: [String]) async throws -> [IssueSummary] {
        var results: [IssueSummary] = []
        for seriesID in Set(seriesIDs).sorted() {
            let parent = try await series(id: seriesID)
            for offset in 1...2 {
                results.append(IssueSummary(
                    id: "\(seriesID)-upcoming-\(offset)",
                    seriesID: seriesID,
                    seriesTitle: parent.title,
                    number: String(parent.issueCount + offset),
                    title: "",
                    coverDate: Calendar.current.date(byAdding: .weekOfYear,
                                                     value: offset * 2,
                                                     to: .now),
                    coverURL: parent.coverURL,
                    pageCount: 32
                ))
            }
        }
        return results.sorted { ($0.coverDate ?? .distantFuture) < ($1.coverDate ?? .distantFuture) }
    }

    func issue(barcode: String) async throws -> IssueSummary? {
        try await issues(seriesID: "1").first
    }
}
