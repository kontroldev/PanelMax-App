import SwiftUI
import SwiftData
import PhotosUI

/// Alta o edición de una serie catalogada a mano.
///
/// Sin catálogo remoto, esto sustituye a lo que antes era una búsqueda: el
/// usuario escribe él mismo el título, la editorial y cuántos números tiene
/// publicados la serie. Ese último dato es el que permite calcular huecos y
/// porcentaje más adelante.
struct SeriesFormView: View {

    /// `nil` al crear una serie nueva; con valor al editar una existente.
    var series: Series?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var publisher: String
    @State private var startYearText: String
    @State private var totalIssuesText: String
    @State private var errorMessage: String?

    /// Portada en curso en este formulario. Puede no coincidir con la que
    /// tiene la serie en disco: mientras el usuario no pulse "Guardar", solo
    /// vive aquí. Ver `initialCoverImageFilename` y `discardPendingCoverIfNeeded()`
    /// para cómo se evita dejar archivos huérfanos en `Documents/Covers`.
    @State private var coverImageFilename: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPickingCover = false
    @State private var pendingCoverTask: Task<Void, Never>?
    @State private var didSave = false

    /// Portada con la que arrancó el formulario (`nil` al crear, o la que ya
    /// tenía la serie al editar). Es la única que sigue siendo válida borrar
    /// si el usuario cancela: cualquier otra la ha escrito esta sesión y
    /// nadie más la referencia todavía.
    private let initialCoverImageFilename: String?

    init(series: Series? = nil) {
        self.series = series
        _title = State(initialValue: series?.title ?? "")
        _publisher = State(initialValue: series?.publisher ?? "")
        _startYearText = State(initialValue: series?.startYear.map(String.init) ?? "")
        _totalIssuesText = State(initialValue: (series?.totalIssues).flatMap { $0 > 0 ? String($0) : nil } ?? "")
        _coverImageFilename = State(initialValue: series?.coverImageFilename)
        initialCoverImageFilename = series?.coverImageFilename
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var store: CollectionStore { CollectionStore(context: context) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Portada (opcional)") {
                    HStack(spacing: 12) {
                        LocalCoverImage(url: coverImageURL, cornerRadius: 6)
                            .frame(width: 64)
                            .accessibilityHidden(true) // decorativa: los botones de al lado ya explican el estado

                        VStack(alignment: .leading, spacing: 8) {
                            // Calculado FUERA del closure de `PhotosPicker`: su
                            // `label` lo tipa PhotosUI como `@Sendable`, y una
                            // propiedad `@State` no se puede leer directamente
                            // desde ahí. Un `String` local, capturado por valor,
                            // no tiene ese problema.
                            let pickerLabel = coverImageFilename == nil ? "Elegir imagen" : "Cambiar imagen"
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Text(pickerLabel)
                            }
                            .disabled(isPickingCover)

                            if coverImageFilename != nil {
                                Button("Quitar imagen", role: .destructive) {
                                    replaceCoverImageFilename(with: nil)
                                }
                                .disabled(isPickingCover)
                            }
                        }
                        Spacer()
                    }
                }

                Section("Serie") {
                    TextField("Título", text: $title)
                    TextField("Editorial (opcional)", text: $publisher)
                    TextField("Año de inicio (opcional)", text: $startYearText)
                        .keyboardType(.numberPad)
                }

                Section {
                    TextField("Números publicados en total", text: $totalIssuesText)
                        .keyboardType(.numberPad)
                        // La explicación de abajo es un pie de sección: VoiceOver
                        // no la asocia al campo, así que se repite como pista
                        // para quien navega campo a campo y nunca llega a oírla.
                        .accessibilityHint("Se usa para calcular el porcentaje de la serie y detectar huecos. Puedes dejarlo en blanco.")
                } footer: {
                    Text("Se usa para calcular el porcentaje de la serie y detectar huecos. Puedes dejarlo en blanco y añadirlo más tarde editando la serie.")
                }
            }
            .navigationTitle(series == nil ? "Nueva serie" : "Editar serie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }.disabled(!isValid)
                }
            }
            .alert("No se ha podido guardar", isPresented: Binding(
                get: { errorMessage != nil },
                set: { visible in if !visible { errorMessage = nil } }
            )) {
                Button("De acuerdo", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            // `PhotosPickerItem` solo entrega un identificador: la carga y
            // el guardado en disco son asíncronos, así que van en `.onChange`.
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                isPickingCover = true
                // Si había una carga anterior en curso (elegir foto A y,
                // antes de que termine de procesarse, foto B), se cancela:
                // sin esto podría terminar después y pisar el resultado de B.
                pendingCoverTask?.cancel()
                pendingCoverTask = Task {
                    defer {
                        selectedPhotoItem = nil // permite volver a elegir la misma foto más tarde
                        isPickingCover = false
                    }
                    guard !Task.isCancelled,
                          let data = try? await newItem.loadTransferable(type: Data.self),
                          !Task.isCancelled,
                          let image = UIImage(data: data),
                          let resized = ImageResizer.jpegData(from: image),
                          let filename = try? ThumbnailStore.save(resized) else {
                        // La portada es opcional: un fallo aquí (formato no
                        // soportado, archivo corrupto...) no debe bloquear
                        // el resto del formulario.
                        return
                    }
                    replaceCoverImageFilename(with: filename)
                }
            }
            .onDisappear {
                // Cubre tanto "Cancelar" como cerrar el formulario deslizando
                // hacia abajo, que no pasa por el botón.
                pendingCoverTask?.cancel()
                guard !didSave else { return }
                discardPendingCoverIfNeeded()
            }
        }
    }

    /// URL de la portada tal y como está en este momento del formulario, ya
    /// sea la que traía la serie o la que se acaba de elegir y aún no se ha
    /// guardado.
    private var coverImageURL: URL? {
        guard let coverImageFilename else { return nil }
        return try? LocalComicFile.coverStorageURL(for: coverImageFilename)
    }

    /// Sustituye la portada en curso, borrando en el acto el archivo que esta
    /// misma sesión del formulario haya podido crear y que deja de usarse.
    /// Nunca borra `initialCoverImageFilename`: esa es la portada que ya
    /// pertenece a la serie, y solo se limpia al guardar (ver `save()`), para
    /// no perderla si el usuario acaba cancelando.
    private func replaceCoverImageFilename(with newFilename: String?) {
        if coverImageFilename != initialCoverImageFilename, let toDiscard = coverImageFilename {
            ThumbnailStore.delete(toDiscard)
        }
        coverImageFilename = newFilename
    }

    /// Se llama al cerrar el formulario sin guardar. Si en esta sesión se
    /// llegó a elegir o quitar una portada, el archivo que quedó a medio
    /// camino (escrito en disco pero nunca asociado a la serie) se borra
    /// aquí para no dejarlo huérfano en `Documents/Covers`.
    private func discardPendingCoverIfNeeded() {
        guard coverImageFilename != initialCoverImageFilename, let pending = coverImageFilename else { return }
        ThumbnailStore.delete(pending)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPublisher = publisher.trimmingCharacters(in: .whitespacesAndNewlines)
        let startYear = Int(startYearText)
        let totalIssues = max(Int(totalIssuesText) ?? 0, 0)

        do {
            if let series {
                try store.updateSeries(series,
                                       title: trimmedTitle,
                                       publisher: trimmedPublisher,
                                       startYear: startYear,
                                       totalIssues: totalIssues,
                                       coverImageFilename: coverImageFilename)
            } else {
                try store.createSeries(title: trimmedTitle,
                                       publisher: trimmedPublisher,
                                       startYear: startYear,
                                       totalIssues: totalIssues,
                                       coverImageFilename: coverImageFilename)
            }
            // Solo se borra la portada anterior una vez el guardado ha
            // tenido éxito: si `save()` fallara antes de este punto, el
            // modelo (revertido por el `catch`) sigue apuntando a ella.
            if initialCoverImageFilename != coverImageFilename, let old = initialCoverImageFilename {
                ThumbnailStore.delete(old)
            }
            didSave = true
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SeriesFormView()
        .modelContainer(PreviewData.container)
}
