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

    /// Un único punto de acceso a la colección para toda la vista, en vez de
    /// instanciar `CollectionStore(context: context)` suelto en cada acción.
    private var store: CollectionStore { CollectionStore(context: context) }

    var body: some View {
        NavigationStack {
            // Una sola pasada. `issues(of:)` no se evalúa por separado en
            // cada fila: todo el filtrado (estado + búsqueda) sale de aquí.
            let snapshot = CollectionSnapshot(series: series, filter: filter, query: query)

            Group {
                if series.isEmpty {
                    emptyState
                } else if snapshot.groups.isEmpty {
                    if query.isEmpty {
                        // Sin búsqueda activa, lo que esconde todo es el filtro.
                        // `.search(text: "")` decía «sin resultados para ""».
                        ContentUnavailableView(
                            "Nada en «\(filter.label)»",
                            systemImage: filter.systemImage,
                            description: Text("Cambia el filtro para ver el resto de tu colección.")
                        )
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                } else {
                    List {
                        ForEach(snapshot.groups) { group in
                            Section {
                                if group.issues.isEmpty {
                                    // Serie recién creada: sin esto la sección
                                    // quedaría como una cabecera suelta sin
                                    // explicar por qué está vacía.
                                    Text("Aún no has añadido números. Toca la serie para empezar.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                } else {
                                    ForEach(group.issues) { issue in
                                        row(for: issue)
                                    }
                                    .onDelete { offsets in delete(offsets, from: group.issues) }
                                }
                            } header: {
                                NavigationLink {
                                    SeriesDetailView(series: group.series)
                                } label: {
                                    header(for: group)
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

    /// Recibe el grupo, no la serie: el porcentaje y los huecos ya vienen
    /// calculados del snapshot. Antes se pedían `completion` y `missingNumbers`
    /// aquí y otra vez en la accesibilidad — cuatro recorridos por serie y por
    /// render, justo lo que el snapshot existe para evitar.
    private func header(for group: CollectionSnapshot.Group) -> some View {
        HStack {
            LocalCoverImage(url: group.series.coverImageURL, width: 28, cornerRadius: 4)
                .accessibilityHidden(true) // decorativa: el título ya se anuncia

            Text(group.series.displayTitle)
            Spacer()
            if let completion = group.completion {
                Text("\(Int(completion * 100)) %")
                    .foregroundStyle(group.missingCount == 0 ? .green : Theme.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        // El porcentaje suelto ("72 %") no dice nada fuera de contexto, y el
        // chevron es decorativo: se agrupa todo en una sola frase.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.series.displayTitle)
        .accessibilityValue(seriesAccessibilityValue(group))
        .accessibilityHint("Abre la ficha de la serie")
    }

    private func seriesAccessibilityValue(_ group: CollectionSnapshot.Group) -> String {
        guard let completion = group.completion else { return "" }
        let percent = Int(completion * 100)
        if group.missingCount == 0 { return "Completa, \(percent) por ciento" }
        return "\(percent) por ciento, te faltan \(group.missingCount) números"
    }

    private func row(for issue: Issue) -> some View {
        HStack(spacing: 12) {
            LocalCoverImage(url: issue.file?.thumbnailURL, width: 38, cornerRadius: 4)
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
        for index in offsets where list.indices.contains(index) {
            do {
                try store.remove(list[index])
            } catch {
                context.rollback()
                errorMessage = error.localizedDescription
                break
            }
        }
    }
}

#Preview {
    CollectionView()
        .modelContainer(PreviewData.container)
}
 
