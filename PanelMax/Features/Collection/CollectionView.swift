import SwiftUI
import SwiftData

/// Mi colección: lo que el usuario ya tiene, catalogado a mano.
///
/// Es la pantalla que crea dependencia. Cuanto más tiempo lleva alguien
/// catalogando aquí, menos se va a otra app, porque sus datos están aquí.
struct CollectionView: View {

    @Query(sort: \Series.title) private var series: [Series]
    @Environment(\.modelContext) private var context

    @State private var filter: CollectionState = .owned
    @State private var query = ""
    @State private var showsNewSeries = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            // Una sola pasada. `issues(of:)` no se evalúa por separado en
            // cada fila: todo el filtrado (estado + búsqueda) sale de aquí.
            let snapshot = CollectionSnapshot(series: series, filter: filter, query: query)

            Group {
                if series.isEmpty {
                    emptyState
                } else if snapshot.groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(snapshot.groups) { group in
                            Section {
                                ForEach(group.issues) { issue in
                                    row(for: issue)
                                }
                                .onDelete { offsets in delete(offsets, from: group.issues) }
                            } header: {
                                NavigationLink {
                                    SeriesDetailView(series: group.series)
                                } label: {
                                    header(for: group.series)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Mi colección")
            .searchable(text: $query, prompt: "Serie o número")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Filtro", selection: $filter) {
                        ForEach(CollectionState.allCases) { state in
                            Label(state.label, systemImage: state.systemImage).tag(state)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Filtrar por estado")
                    .accessibilityValue(filter.label)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsNewSeries = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Nueva serie")
                }
            }
            .sheet(isPresented: $showsNewSeries) {
                SeriesFormView()
            }
            .alert("No se ha podido actualizar la colección", isPresented: Binding(
                get: { errorMessage != nil },
                set: { visible in if !visible { errorMessage = nil } }
            )) {
                Button("De acuerdo", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aún no has catalogado nada", systemImage: "books.vertical")
        } description: {
            Text("Crea tu primera serie y añade los números que tengas.")
        } actions: {
            Button("Crear serie") { showsNewSeries = true }
        }
    }

    // MARK: - Filas

    private func header(for serie: Series) -> some View {
        HStack {
            Text(serie.displayTitle)
            Spacer()
            if let completion = serie.completion {
                Text("\(Int(completion * 100)) %")
                    .foregroundStyle(serie.missingNumbers.isEmpty ? .green : Theme.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        // El porcentaje suelto ("72 %") no dice nada fuera de contexto, y el
        // chevron es decorativo: se agrupa todo en una sola frase.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(serie.displayTitle)
        .accessibilityValue(seriesAccessibilityValue(serie))
        .accessibilityHint("Abre la ficha de la serie")
    }

    private func seriesAccessibilityValue(_ serie: Series) -> String {
        guard let completion = serie.completion else { return "" }
        let percent = Int(completion * 100)
        let missing = serie.missingNumbers.count
        if missing == 0 { return "Completa, \(percent) por ciento" }
        return "\(percent) por ciento, te faltan \(missing) números"
    }

    private func row(for issue: Issue) -> some View {
        HStack(spacing: 12) {
            LocalCoverImage(url: issue.file?.thumbnailURL, cornerRadius: 4)
                .frame(width: 38)
                .accessibilityHidden(true) // decorativa: el número ya se anuncia

            VStack(alignment: .leading, spacing: 2) {
                Text(issue.displayName).font(.subheadline)

                HStack(spacing: 6) {
                    if let entry = issue.entry {
                        Text(entry.format.label)
                    }
                    if let position = issue.file?.progressDescription,
                       issue.file?.isFinished == false {
                        Text("· \(position)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
            }
            // Se agrupa solo el bloque de texto: el botón de leer queda fuera
            // a propósito, para que siga siendo un elemento accionable propio.
            .accessibilityElement(children: .combine)

            Spacer()

            if issue.isReadable {
                NavigationLink { ReaderView(issue: issue) } label: {
                    Image(systemName: "book.fill").foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Leer \(issue.displayName)")
            }
        }
    }

    // MARK: - Datos

    private func delete(_ offsets: IndexSet, from list: [Issue]) {
        let collection = CollectionStore(context: context)
        for index in offsets where list.indices.contains(index) {
            do {
                try collection.remove(list[index])
            } catch {
                context.rollback()
                errorMessage = error.localizedDescription
                break
            }
        }
    }
}

// MARK: - Cálculo

/// Series visibles con sus números ya filtrados y ordenados, según el estado
/// elegido y el texto de búsqueda.
private struct CollectionSnapshot {

    struct Group: Identifiable {
        let series: Series
        let issues: [Issue]
        var id: PersistentIdentifier { series.persistentModelID }
    }

    let groups: [Group]

    init(series: [Series], filter: CollectionState, query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var groups: [Group] = []

        for serie in series {
            var matching: [Issue] = []

            for issue in serie.issues ?? [] {
                guard let state = issue.entry?.state else { continue }
                // «Lo tengo» incluye también lo leído: si lo has leído, lo tienes.
                if state == filter || (filter == .owned && state == .read) {
                    matching.append(issue)
                }
            }

            guard !matching.isEmpty else { continue }

            // Orden natural: el "1/2" y los anuales van al final, no al principio.
            matching.sort { ComicNumber.areInIncreasingOrder($0.number, $1.number) }

            if !normalizedQuery.isEmpty {
                let seriesMatches = serie.title.lowercased().contains(normalizedQuery)
                if !seriesMatches {
                    matching = matching.filter {
                        $0.number.lowercased().contains(normalizedQuery)
                            || $0.title.lowercased().contains(normalizedQuery)
                    }
                }
                guard !matching.isEmpty else { continue }
            }

            groups.append(Group(series: serie, issues: matching))
        }

        self.groups = groups
    }
}

#Preview {
    CollectionView()
        .modelContainer(PreviewData.container)
}
