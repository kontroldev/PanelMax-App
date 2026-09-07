import Foundation
import SwiftData

/// Exporta la colección a JSON. Es la única copia de seguridad posible sin
/// iCloud ni cuenta: si el usuario pierde el dispositivo, pierde la colección
/// que catalogó a mano a menos que la haya exportado antes.
enum CollectionExporter {

    struct ExportedIssue: Codable {
        let number: String
        let title: String
        let state: String
        let format: String
        let hasImportedFile: Bool
    }

    struct ExportedSeries: Codable {
        let title: String
        let publisher: String
        let startYear: Int?
        let totalIssues: Int
        let issues: [ExportedIssue]
    }

    struct Export: Codable {
        let generatedAt: Date
        let series: [ExportedSeries]
    }

    @MainActor
    static func makeJSON(series: [Series]) throws -> Data {
        let exportedSeries = series.map { serie -> ExportedSeries in
            let issues = ComicNumber.sorted(serie.issues ?? [], by: \.number)
                .compactMap { issue -> ExportedIssue? in
                    guard let entry = issue.entry else { return nil }
                    return ExportedIssue(number: issue.number,
                                         title: issue.title,
                                         state: entry.state.label,
                                         format: entry.format.label,
                                         hasImportedFile: issue.file != nil)
                }
            return ExportedSeries(title: serie.title,
                                  publisher: serie.publisher,
                                  startYear: serie.startYear,
                                  totalIssues: serie.totalIssues,
                                  issues: issues)
        }

        let export = Export(generatedAt: .now, series: exportedSeries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// Escribe el JSON en un archivo temporal listo para `ShareLink`.
    @MainActor
    static func makeExportFile(series: [Series]) throws -> URL {
        let data = try makeJSON(series: series)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "\(AppInfo.displayName)-\(formatter.string(from: .now)).json"
        let url = FileManager.default.temporaryDirectory.appending(path: filename, directoryHint: .notDirectory)
        try data.write(to: url, options: .atomic)
        return url
    }
}
