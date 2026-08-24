import Foundation
import SwiftData

/// Operaciones sobre la colección del usuario.
///
/// Las vistas NO tocan el `ModelContext` directamente. Todo pasa por aquí.
/// Motivo práctico: la unicidad de `catalogID` hay que garantizarla a mano
/// (CloudKit prohíbe `@Attribute(.unique)`), y si eso está repartido por las vistas
/// acabas con series duplicadas el día que el usuario toque dos veces el mismo botón.
@MainActor
struct CollectionStore {

    let context: ModelContext

    // MARK: - Lecturas

    /// Cuántos números hay guardados. Es el número que se compara con el límite gratuito.
    func entryCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<CollectionEntry>())) ?? 0
    }

    func importedFileCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<LocalComicFile>())) ?? 0
    }

    func followedSeriesCount() -> Int {
        let descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.isFollowed })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Escrituras

    /// Busca una serie por su id de catálogo o la crea si no existe.
    /// Este es el punto único donde nacen las series: no crees `Series(...)` en ninguna vista.
    func findOrCreate(_ summary: SeriesSummary) throws -> Series {
        let id = summary.id
        let descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.catalogID == id })

        if let existing = try context.fetch(descriptor).first {
            existing.title = summary.title
            existing.publisher = summary.publisher
            existing.startYear = summary.startYear
            existing.summary = summary.summary
            existing.coverURLString = summary.coverURL?.absoluteString
            existing.totalIssues = summary.issueCount
            return existing
        }

        let series = summary.makeModel()
        context.insert(series)
        return series
    }

    /// Busca un número dentro de una serie, o lo crea.
    func findOrCreate(_ summary: IssueSummary, in series: Series) throws -> Issue {
        if let existing = (series.issues ?? []).first(where: { $0.catalogID == summary.id }) {
            existing.number = summary.number
            existing.title = summary.title
            existing.coverDate = summary.coverDate
            existing.coverURLString = summary.coverURL?.absoluteString
            existing.pageCount = summary.pageCount
            return existing
        }

        let issue = summary.makeModel()
        issue.series = series
        context.insert(issue)
        return issue
    }

    /// Añade un número a la colección con el estado indicado.
    ///
    /// Ojo: comprobar el límite del plan gratuito NO es responsabilidad de este método.
    /// Eso lo hace `PremiumGate` antes de llamar aquí, porque el muro necesita saber
    /// el motivo exacto para explicárselo al usuario.
    @discardableResult
    func add(_ issueSummary: IssueSummary,
             of seriesSummary: SeriesSummary,
             state: CollectionState = .owned,
             format: CollectionFormat = .physical) throws -> Issue {

        let series = try findOrCreate(seriesSummary)
        let issue = try findOrCreate(issueSummary, in: series)

        if let entry = issue.entry {
            entry.state = state      // ya estaba: solo se actualiza
            entry.format = format
        } else {
            let entry = CollectionEntry(state: state, format: format)
            entry.issue = issue
            context.insert(entry)
        }

        try context.save()
        return issue
    }

    /// Quita un número de la colección sin borrar la ficha del catálogo.
    func remove(_ issue: Issue) throws {
        if let entry = issue.entry {
            context.delete(entry)
        }
        try context.save()
    }

    /// Cambia el estado de un número que ya está en la colección.
    ///
    /// No pasa por `add` a propósito: cambiar de «lo tengo» a «lo quiero» no
    /// crea nada nuevo y por tanto NO debe consultar el límite del plan gratuito.
    func setState(_ state: CollectionState, for issue: Issue) throws {
        guard let entry = issue.entry else { return }
        entry.state = state
        try context.save()
    }

    /// Cambia el formato (papel o digital) de un número ya guardado.
    func setFormat(_ format: CollectionFormat, for issue: Issue) throws {
        guard let entry = issue.entry else { return }
        entry.format = format
        try context.save()
    }

    /// Marca o desmarca una serie como seguida.
    func setFollowed(_ series: Series, _ followed: Bool) throws {
        series.isFollowed = followed
        try context.save()
    }

    /// Guarda el progreso de lectura al salir del lector.
    func saveProgress(for issue: Issue, page: Int, totalPages: Int) throws {
        // Sin páginas no hay progreso que guardar. Sin este guard, un archivo
        // corrupto (0 páginas) se marcaría como terminado con page >= -1.
        guard totalPages > 0 else { return }
        let clampedPage = min(max(page, 0), totalPages - 1)

        if let progress = issue.progress {
            progress.currentPage = clampedPage
            progress.totalPages = totalPages
            progress.lastReadAt = .now
            progress.isFinished = clampedPage >= totalPages - 1
        } else {
            let progress = ReadingProgress(currentPage: clampedPage, totalPages: totalPages)
            progress.isFinished = clampedPage >= totalPages - 1
            progress.issue = issue
            context.insert(progress)
        }
        try context.save()
    }
}
