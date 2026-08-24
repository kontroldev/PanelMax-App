import Foundation

/// Resultado de catálogo para una serie.
///
/// Es un tipo aparte de `Series` (el @Model) a propósito: el catálogo trae
/// miles de resultados que no queremos guardar en la base de datos.
/// Solo se convierte en `Series` cuando el usuario guarda algo.
struct SeriesSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let publisher: String
    let startYear: Int?
    let summary: String
    let coverURL: URL?
    let issueCount: Int

    /// Convierte el resultado del catálogo en un modelo persistente.
    func makeModel() -> Series {
        Series(catalogID: id,
               title: title,
               publisher: publisher,
               startYear: startYear,
               summary: summary,
               coverURLString: coverURL?.absoluteString,
               totalIssues: issueCount)
    }
}

/// Resultado de catálogo para un número concreto.
struct IssueSummary: Identifiable, Hashable, Sendable {
    let id: String
    let seriesID: String
    let seriesTitle: String
    let number: String
    let title: String
    let coverDate: Date?
    let coverURL: URL?
    let pageCount: Int

    func makeModel() -> Issue {
        Issue(catalogID: id,
              number: number,
              title: title,
              coverDate: coverDate,
              coverURLString: coverURL?.absoluteString,
              pageCount: pageCount)
    }
}
