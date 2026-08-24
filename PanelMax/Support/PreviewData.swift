import Foundation
import SwiftData

/// Contenedor en memoria con datos de ejemplo, solo para las previsualizaciones.
///
/// `isStoredInMemoryOnly: true` es la clave: cada previsualización arranca limpia
/// y nunca toca la base de datos real del simulador.
@MainActor
enum PreviewData {

    static let container: ModelContainer = {
        let schema = Schema.panelMax
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            seed(container.mainContext)
            return container
        } catch {
            fatalError("No se pudo crear el contenedor de previsualización: \(error)")
        }
    }()

    /// Rellena con tres series: una a medio leer, una con huecos y una completa.
    /// Los tres casos que hay que ver al diseñar el Home.
    private static func seed(_ context: ModelContext) {
        // Serie en curso, con lectura empezada.
        let ronin = Series(catalogID: "2", title: "Ronin Neón", publisher: "Kaiju Press",
                           startYear: 2023, summary: "Tokio 2098.", totalIssues: 12)
        context.insert(ronin)

        for number in 1...5 {
            let issue = Issue(catalogID: "2-\(number)", number: String(number), pageCount: 32)
            issue.series = ronin
            context.insert(issue)

            let entry = CollectionEntry(state: .owned, format: .digital)
            entry.issue = issue
            context.insert(entry)
        }

        if let last = ronin.issues?.last {
            let progress = ReadingProgress(currentPage: 13, totalPages: 32)
            progress.issue = last
            context.insert(progress)

            // El archivo importado es la fuente de "Continuar leyendo".
            let file = LocalComicFile(displayName: "Ronin Neón 5", localFilename: "preview-ronin-5.cbz")
            file.issue = last
            file.updateProgress(page: 13, totalPages: 32)
            file.fileSize = 42_000_000
            context.insert(file)
        }

        // Serie con huecos: faltan el 4 y el 7.
        let dragon = Series(catalogID: "5", title: "Dragón de Hierro", publisher: "Kaiju Press",
                            startYear: 2020, summary: "Artes marciales.", totalIssues: 30)
        dragon.isFollowed = true
        context.insert(dragon)

        for number in [1, 2, 3, 5, 6, 8] {
            let issue = Issue(catalogID: "5-\(number)", number: String(number), pageCount: 32)
            issue.series = dragon
            context.insert(issue)

            let entry = CollectionEntry(state: .owned, format: .physical)
            entry.issue = issue
            context.insert(entry)
        }

        try? context.save()
    }
}
