import SwiftUI
import SwiftData

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

    init(series: Series? = nil) {
        self.series = series
        _title = State(initialValue: series?.title ?? "")
        _publisher = State(initialValue: series?.publisher ?? "")
        _startYearText = State(initialValue: series?.startYear.map(String.init) ?? "")
        _totalIssuesText = State(initialValue: (series?.totalIssues).flatMap { $0 > 0 ? String($0) : nil } ?? "")
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
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
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPublisher = publisher.trimmingCharacters(in: .whitespacesAndNewlines)
        let startYear = Int(startYearText)
        let totalIssues = max(Int(totalIssuesText) ?? 0, 0)

        do {
            let store = CollectionStore(context: context)
            if let series {
                try store.updateSeries(series,
                                       title: trimmedTitle,
                                       publisher: trimmedPublisher,
                                       startYear: startYear,
                                       totalIssues: totalIssues)
            } else {
                try store.createSeries(title: trimmedTitle,
                                       publisher: trimmedPublisher,
                                       startYear: startYear,
                                       totalIssues: totalIssues)
            }
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
