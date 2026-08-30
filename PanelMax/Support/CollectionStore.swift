import Foundation
import SwiftData

/// Operaciones sobre la colección del usuario.
///
/// Las vistas NO tocan el `ModelContext` directamente. Todo pasa por aquí.
/// Sin catálogo remoto, series y números se crean a mano: `catalogID` sigue
/// existiendo en el modelo (para cuando la 1.1 traiga un catálogo real) pero
/// aquí se rellena con un UUID que solo sirve para garantizar unicidad.
@MainActor
struct CollectionStore {

    let context: ModelContext

    // MARK: - Lecturas

    /// Cuántos números hay guardados en total. Ya no se compara con ningún
    /// límite (la 1.0 es gratis y sin topes), pero sigue siendo útil para
    /// estadísticas y para la exportación.
    func entryCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<CollectionEntry>())) ?? 0
    }

    func importedFileCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<LocalComicFile>())) ?? 0
    }

    // MARK: - Series

    /// Crea una serie nueva a partir de lo que el usuario ha escrito a mano.
    @discardableResult
    func createSeries(title: String,
                       publisher: String = "",
                       startYear: Int? = nil,
                       totalIssues: Int = 0) throws -> Series {
        let series = Series(catalogID: UUID().uuidString,
                            title: title,
                            publisher: publisher,
                            startYear: startYear,
                            totalIssues: totalIssues)
        context.insert(series)
        try context.save()
        return series
    }

    func updateSeries(_ series: Series,
                       title: String,
                       publisher: String,
                       startYear: Int?,
                       totalIssues: Int) throws {
        series.title = title
        series.publisher = publisher
        series.startYear = startYear
        series.totalIssues = totalIssues
        try context.save()
    }

    /// Borra la serie y sus números (regla `.cascade` del modelo). Los
    /// archivos importados vinculados NO se borran: la relación es
    /// `.nullify`, así que siguen disponibles en Biblioteca importada.
    func deleteSeries(_ series: Series) throws {
        context.delete(series)
        try context.save()
    }

    // MARK: - Números

    /// Añade un número suelto. Si ya existía en la serie pero sin ficha de
    /// colección (un hueco marcado, por ejemplo), lo convierte en poseído en
    /// lugar de duplicarlo.
    @discardableResult
    func addIssue(number: String,
                  title: String = "",
                  to series: Series,
                  state: CollectionState = .owned,
                  format: CollectionFormat = .physical) throws -> Issue {
        let issue = insertIssue(number: number, title: title, into: series, state: state, format: format)
        try context.save()
        return issue
    }

    /// Añade todo un rango de una vez ("del 1 al 40"). Es lo que hace viable
    /// catalogar a mano una colección real: sin esto, cuarenta números son
    /// cuarenta altas sueltas.
    @discardableResult
    func addIssueRange(from: Int,
                        through: Int,
                        to series: Series,
                        state: CollectionState = .owned,
                        format: CollectionFormat = .physical) throws -> [Issue] {
        guard from <= through else { return [] }
        let issues = (from...through).map {
            insertIssue(number: String($0), title: "", into: series, state: state, format: format)
        }
        try context.save()
        return issues
    }

    /// Núcleo sin guardar, compartido por el alta suelta y el alta por rango:
    /// añadir doce números debe ser un único `save()`, no doce.
    private func insertIssue(number: String,
                              title: String,
                              into series: Series,
                              state: CollectionState,
                              format: CollectionFormat) -> Issue {
        if let existing = (series.issues ?? []).first(where: { $0.number == number }) {
            if existing.entry == nil {
                let entry = CollectionEntry(state: state, format: format)
                entry.issue = existing
                context.insert(entry)
            }
            return existing
        }

        let issue = Issue(catalogID: UUID().uuidString, number: number, title: title)
        issue.series = series
        context.insert(issue)

        let entry = CollectionEntry(state: state, format: format)
        entry.issue = issue
        context.insert(entry)
        return issue
    }

    /// Quita un número de la colección sin borrar la ficha (vuelve a quedar
    /// como un hueco, en vez de desaparecer del todo).
    func remove(_ issue: Issue) throws {
        if let entry = issue.entry {
            context.delete(entry)
        }
        try context.save()
    }

    func setState(_ state: CollectionState, for issue: Issue) throws {
        guard let entry = issue.entry else { return }
        entry.state = state
        try context.save()
    }

    func setFormat(_ format: CollectionFormat, for issue: Issue) throws {
        guard let entry = issue.entry else { return }
        entry.format = format
        try context.save()
    }

    // MARK: - Vincular archivos importados

    /// Asocia un cómic ya importado a un número concreto, para poder leerlo
    /// desde la ficha de la serie.
    func link(_ file: LocalComicFile, to issue: Issue) throws {
        file.issue = issue
        try context.save()
    }

    func unlink(_ file: LocalComicFile) throws {
        file.issue = nil
        try context.save()
    }

    // MARK: - Lectura

    /// Guarda el progreso de lectura al salir del lector.
    func saveProgress(for issue: Issue, page: Int, totalPages: Int) throws {
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
