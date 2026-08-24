import SwiftUI
import SwiftData

/// Búsqueda en el catálogo.
///
/// La búsqueda es contra la fuente de catálogo (protocolo `CatalogSource`),
/// no contra SwiftData: aquí se busca lo que existe en el mundo, no lo que ya tienes.
struct SearchView: View {

    @Environment(\.catalog) private var catalog

    @State private var query = ""
    @State private var results: [SeriesSummary] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    /// Tarea de búsqueda en curso. Se cancela al teclear otra letra
    /// para no lanzar una petición por pulsación.
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("No se ha podido buscar", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Volver a intentar") { schedule(query) }
                    }
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(results) { summary in
                            NavigationLink {
                                SeriesDetailView(summary: summary)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    CoverImage(url: summary.coverURL)
                                    Text(summary.title)
                                        .font(.caption2.weight(.semibold))
                                        .lineLimit(2)
                                    Text(summary.publisher)
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .overlay { if isSearching && results.isEmpty { ProgressView() } }
            .navigationTitle("Buscar")
            .searchable(text: $query, prompt: "Serie, personaje o editorial")
            .onChange(of: query) { _, newValue in schedule(newValue) }
            .task { schedule("") }   // al abrir, enseña el catálogo destacado
        }
    }

    /// Rebote de 300 ms: sin esto, escribir "Batman" son seis peticiones.
    private func schedule(_ text: String) {
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search(text.trimmingCharacters(in: .whitespacesAndNewlines), generation: generation)
        }
    }

    private func search(_ text: String, generation: Int) async {
        isSearching = true

        do {
            let newResults = try await catalog.searchSeries(query: text)
            guard generation == searchGeneration, !Task.isCancelled else { return }
            results = newResults
            errorMessage = nil
        } catch is CancellationError {
            // Búsqueda reemplazada por otra más reciente. No es un error que mostrar.
        } catch {
            guard generation == searchGeneration, !Task.isCancelled else { return }
            errorMessage = (error as? CatalogError)?.errorDescription ?? error.localizedDescription
        }

        if generation == searchGeneration { isSearching = false }
    }
}

#Preview {
    SearchView().modelContainer(PreviewData.container)
}
