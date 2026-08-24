import SwiftUI
import SwiftData

/// Mi colección: lo que el usuario ya tiene.
///
/// Es la pantalla que crea dependencia. Cuanto más tiempo lleva alguien
/// catalogando aquí, menos se va a otra app, porque sus datos están aquí.
struct CollectionView: View {

    @Query(sort: \Series.title) private var series: [Series]
    @Environment(\.modelContext) private var context
    @Environment(SubscriptionStore.self) private var store

    @State private var filter: CollectionState = .owned
    @State private var paywall: PaywallReason?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            // Una sola pasada. Antes `issues(of:)` se ejecutaba dos veces por
            // serie (una en `visibleSeries` y otra en el `ForEach`) y además se
            // lanzaba un `fetchCount` a SwiftData dentro del cuerpo.
            let snapshot = CollectionSnapshot(series: series, filter: filter)

            Group {
                if snapshot.groups.isEmpty {
                    emptyState
                } else {
                    List {
                        if !store.isPremium { limitSection(used: snapshot.totalEntries) }

                        ForEach(snapshot.groups) { group in
                            Section {
                                ForEach(group.issues) { issue in
                                    row(for: issue)
                                }
                                .onDelete { offsets in delete(offsets, from: group.issues) }
                            } header: {
                                header(for: group.series)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Mi colección")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Filtro", selection: $filter) {
                        ForEach(CollectionState.allCases) { state in
                            Label(state.label, systemImage: state.systemImage).tag(state)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .paywall($paywall)
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
        ContentUnavailableView(
            filter == .owned ? "Aún no has guardado nada" : "No hay resultados",
            systemImage: "books.vertical",
            description: Text(filter == .owned
                              ? "Los números que marques como tuyos aparecerán aquí."
                              : "No tienes números con el estado «\(filter.label)».")
        )
    }

    // MARK: - Aviso de límite

    /// Se enseña el consumo del plan gratuito ANTES de llegar al tope.
    /// Toparse con un muro sin avisar es lo que genera reseñas de una estrella.
    private func limitSection(used: Int) -> some View {
        Section {
            let limit = FreeLimits.collectionEntries

            Button { paywall = .general } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(used) de \(limit) números")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        PremiumBadge(text: "AMPLIAR")
                    }
                    ProgressView(value: Double(min(used, limit)), total: Double(limit))
                        .tint(used >= limit ? Theme.accent : Theme.premium)
                    Text("El plan gratuito guarda hasta \(limit) números.")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Plan gratuito: \(used) de \(limit) números")
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
        }
    }

    private func row(for issue: Issue) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: issue.coverURL, cornerRadius: 4).frame(width: 38)

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

/// Series visibles con sus números ya filtrados y ordenados, más el total de
/// fichas guardadas (el número que se compara con el límite gratuito).
private struct CollectionSnapshot {

    struct Group: Identifiable {
        let series: Series
        let issues: [Issue]
        var id: PersistentIdentifier { series.persistentModelID }
    }

    let groups: [Group]
    let totalEntries: Int

    init(series: [Series], filter: CollectionState) {
        var groups: [Group] = []
        var total = 0

        for serie in series {
            var matching: [Issue] = []

            for issue in serie.issues ?? [] {
                guard let state = issue.entry?.state else { continue }
                total += 1

                // «Lo tengo» incluye también lo leído: si lo has leído, lo tienes.
                if state == filter || (filter == .owned && state == .read) {
                    matching.append(issue)
                }
            }

            guard !matching.isEmpty else { continue }

            // Orden natural: el "1/2" y los anuales van al final, no al principio.
            matching.sort { ComicNumber.areInIncreasingOrder($0.number, $1.number) }
            groups.append(Group(series: serie, issues: matching))
        }

        self.groups = groups
        self.totalEntries = total
    }
}

#Preview {
    CollectionView()
        .environment(SubscriptionStore())
        .modelContainer(PreviewData.container)
}
