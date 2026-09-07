import Foundation
import SwiftData

/// Copia el cómic de bienvenida en el primer arranque.
///
/// Sin esto, alguien que abre PanelMax por primera vez (incluido un revisor
/// de App Store en un dispositivo limpio) ve una app vacía con un botón de
/// importar y ningún archivo que importar. Un CBZ de cuatro páginas dentro
/// del propio bundle resuelve ese primer minuto.
enum SampleLibrarySeeder {

    private static let seededKey = "panelmax.sampleComicSeeded"
    private static let resourceName = "Bienvenido"
    private static let resourceExtension = "cbz"
    private static let storedFilename = "bienvenido-a-panelmax.cbz"

    @MainActor
    static func seedIfNeeded(context: ModelContext,
                              defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seededKey) else { return }
        // Se marca ANTES de intentar copiar: si el cómic de ejemplo no se
        // puede copiar por lo que sea, la app no debe volver a intentarlo en
        // cada arranque. Sigue siendo una app perfectamente usable sin él.
        defaults.set(true, forKey: seededKey)

        guard let bundledURL = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            return
        }

        do {
            let destination = try LocalComicFile.prepareComicsDirectory()
            let target = destination.appending(path: storedFilename, directoryHint: .notDirectory)
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.copyItem(at: bundledURL, to: target)
            }

            let file = LocalComicFile(displayName: "Bienvenido a \(AppInfo.displayName)", localFilename: storedFilename)
            file.pageCount = (try? ComicArchiveFactory.pageCount(at: target)) ?? 0

            context.insert(file)
            try context.save()

            // La miniatura se genera aparte y en segundo plano: no debe
            // retrasar el primer arranque de la app.
            Task {
                guard let data = await ThumbnailGenerator.makeThumbnail(for: target),
                      let filename = try? ThumbnailStore.save(data) else { return }
                file.thumbnailFilename = filename
                try? context.save()
            }
        } catch {
            // Silencioso a propósito: sembrar el ejemplo es una cortesía, no
            // un requisito. La app arranca igual de bien sin él.
        }
    }
}
