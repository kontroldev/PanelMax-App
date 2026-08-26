import SwiftUI
import SwiftData

/// Ficha de una serie con la rejilla de números.
///
/// Es la pantalla donde se decide todo: aquí es donde el usuario toca "lo tengo"
/// cincuenta veces y donde, en el número 51, aparece el muro.
struct SeriesDetailView: View {

    let summary: SeriesSummary

    @Environment(\.catalog) private var catalog
    @Environment(\.modelContext) private var context
    @Environment(SubscriptionStore.self) private var store

    /// Solo la serie que se está mostrando.
    ///
    /// La versión anterior consultaba TODAS las series guardadas y filtraba en
    /// memoria; con una colección grande eso es traer la base de datos entera
    /// para encontrar una fila.
    @Query private var savedSeries: [Series]

    @State private var issues: [IssueSummary] = []
    @State private var isLoading = true
    @State private var paywall: PaywallReason?
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 10)]

    init(summary: SeriesSummary) {
        self.summary = summary
        let catalogID = summary.id
        _savedSeries = Query(filter: #Predicate<Series> { $0.catalogID == catalogID })
    }

    private var saved: Series? { savedSeries.first }

    /// Estado guardado de cada número, indexado por id de catálogo.
    ///
    /// Antes se usaba un `Set` de números poseídos, que dejaba fuera los
    /// marcados como «lo quiero»: la rejilla los pintaba como si no estuvieran
    /// en la colección, pero al tocarlos se borraban en lugar de añadirse.
    private var savedStates: [String: CollectionState] {
        var states: [String: CollectionState] = [:]
        for issue in saved?.issues ?? [] {
            if let entry = issue.entry {
                states[issue.catalogID] = entry.state
            }
        }
        return states
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                progressLine
                numbersGrid
            }
            .padding(16)
        }
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { followButton }
        .task { await loadIssues() }
        .paywall($paywall)
        .alert("No se ha podido completar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { visible in if !visible { errorMessage = nil } }
        )) {
            Button("De acuerdo", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Secciones

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImage(url: summary.coverURL).frame(width: 96)

            VStack(alignment: .leading, spacing: 5) {
                Text(summary.title).font(.title3.weight(.bold))
                Text(summary.publisher).font(.subheadline).foregroundStyle(Theme.secondaryText)
                if let year = summary.startYear {
                    Text(String(year)).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Text(summary.summary).font(.caption).lineLimit(4).padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var progressLine: some View {
        if let saved, let completion = saved.completion {
            let missing = saved.missingNumbers
            VStack(alignment: .leading, spacing: 5) {
                Theme.sectionLabel("Tu progreso")
                ProgressView(value: completion)
                    .tint(Theme.accent)
                Text("\(saved.allOwnedIssues.count) de \(summary.issueCount) números")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)

                if !missing.isEmpty {
                    Text("Te faltan: \(missing.map(String.init).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var numbersGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Theme.sectionLabel("Números")

            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if issues.isEmpty {
                ContentUnavailableView {
                    Label("No hay números disponibles", systemImage: "books.vertical")
                } description: {
                    Text("Comprueba la conexión o la configuración del catálogo.")
                } actions: {
                    Button("Volver a intentar") { Task { await loadIssues() } }
                }
            } else {
                let states = savedStates
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(issues) { issue in
                        let state = states[issue.id]
                        Button { toggle(issue, current: state) } label: {
                            NumberChip(number: issue.number, state: state)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: issue, current: state) }
                    }
                }
            }
        }
    }

    /// Menú contextual con los estados y formatos que el modelo siempre ha
    /// soportado pero que ninguna vista podía producir.
    @ViewBuilder
    private func menu(for issueSummary: IssueSummary, current: CollectionState?) -> some View {
        ForEach(CollectionState.allCases) { state in
            Button {
                apply(state, to: issueSummary, current: current)
            } label: {
                Label(state.label, systemImage: state.systemImage)
            }
            .disabled(state == current)
        }

        if current != nil, let issue = storedIssue(for: issueSummary) {
            Divider()

            ForEach(CollectionFormat.allCases) { format in
                Button {
                    write { try CollectionStore(context: context).setFormat(format, for: issue) }
                } label: {
                    Label(format.label, systemImage: format == .physical ? "book.closed" : "iphone")
                }
                .disabled(issue.entry?.format == format)
            }

            Divider()

            Button(role: .destructive) {
                write { try CollectionStore(context: context).remove(issue) }
            } label: {
                Label("Quitar de la colección", systemImage: "trash")
            }
        }
    }

    private var followButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                follow()
            } label: {
                Image(systemName: saved?.isFollowed == true ? "bell.fill" : "bell")
            }
            .accessibilityLabel(saved?.isFollowed == true ? "Dejar de seguir" : "Seguir serie")
        }
    }

    // MARK: - Acciones

    private func loadIssues() async {
        isLoading = true
        defer { isLoading = false }
        do {
            issues = try await catalog.issues(seriesID: summary.id)
        } catch is CancellationError {
            return
        } catch {
            issues = []
            errorMessage = (error as? CatalogError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func storedIssue(for issueSummary: IssueSummary) -> Issue? {
        (saved?.issues ?? []).first { $0.catalogID == issueSummary.id }
    }

    /// Toque simple sobre el número.
    ///
    /// - Sin ficha: se añade como poseído (aquí sí se comprueba el límite).
    /// - Marcado como «lo quiero»: pasa a poseído, que es lo que espera alguien
    ///   que acaba de comprarlo. Antes lo borraba de la colección.
    /// - Poseído o leído: se quita. Quitar nunca está limitado.
    private func toggle(_ issueSummary: IssueSummary, current: CollectionState?) {
        switch current {
        case .none:
            addOwned(issueSummary)
        case .wanted:
            apply(.owned, to: issueSummary, current: .wanted)
        case .owned, .read:
            guard let issue = storedIssue(for: issueSummary) else { return }
            write { try CollectionStore(context: context).remove(issue) }
        }
    }

    private func apply(_ state: CollectionState, to issueSummary: IssueSummary, current: CollectionState?) {
        guard current != nil, let issue = storedIssue(for: issueSummary) else {
            addOwned(issueSummary, state: state)
            return
        }
        write { try CollectionStore(context: context).setState(state, for: issue) }
    }

    private func addOwned(_ issueSummary: IssueSummary, state: CollectionState = .owned) {
        let collection = CollectionStore(context: context)
        let gate = PremiumGate(isPremium: store.isPremium)

        if let reason = gate.check(.addToCollection(current: collection.entryCount())) {
            paywall = reason
            return
        }

        write { try collection.add(issueSummary, of: summary, state: state) }
    }

    private func follow() {
        let collection = CollectionStore(context: context)
        let gate = PremiumGate(isPremium: store.isPremium)

        if let saved, saved.isFollowed {
            write { try collection.setFollowed(saved, false) }
            return
        }

        if let reason = gate.check(.followSeries(current: collection.followedSeriesCount())) {
            paywall = reason
            return
        }

        write {
            let series = try collection.findOrCreate(summary)
            try collection.setFollowed(series, true)
        }
    }

    /// Un único sitio donde se traduce un error de escritura a mensaje visible.
    private func write(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

/// Cuadrito de número. El color distingue los tres estados que el modelo
/// admite, no solo «lo tienes / no lo tienes».
private struct NumberChip: View {
    let number: String
    let state: CollectionState?

    private var background: Color {
        switch state {
        case .owned, .read: Theme.accent
        case .wanted:       Theme.premiumSoft
        case .none:         Color(.secondarySystemGroupedBackground)
        }
    }

    private var foreground: Color {
        switch state {
        case .owned, .read: .white
        case .wanted:       Theme.premium
        case .none:         .primary
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .owned: "en la colección"
        case .read:  "leído"
        case .wanted: "lo quieres"
        case .none:  "no lo tienes"
        }
    }

    var body: some View {
        Text(number)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(foreground)
            .panelGlass(cornerRadius: 8,
                        tint: state == nil ? nil : background,
                        isInteractive: true,
                        fallbackFill: background,
                        strokeColor: state == nil ? Theme.hairline : .clear)
            .accessibilityLabel("Número \(number)")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Mantén pulsado para cambiar el estado o el formato.")
    }
}

#Preview {
    NavigationStack {
        SeriesDetailView(summary: MockCatalogSource.series[1])
            .environment(SubscriptionStore())
            .modelContainer(PreviewData.container)
    }
}
