import SwiftUI
import SwiftData

/// Pantalla de inicio.
///
/// Las series seguidas y sus próximos números aparecen antes de la colección.
/// Así «seguir» tiene una utilidad visible incluso cuando todavía no se posee
/// ningún número de esa serie.
///
/// Nota de rendimiento: las secciones se calculan en memoria sobre las series
/// guardadas, no con predicados de SwiftData. Todo el trabajo se hace UNA vez
/// por evaluación del cuerpo, en `HomeSnapshot`. La versión anterior recorría
/// la colección entera cinco o seis veces por render, porque cada propiedad
/// calculada (`collectionSeries`, `missingHighlights`, `inProgress`…) se volvía
/// a evaluar en cada sitio donde se usaba.
struct HomeView: View {

    @Query(sort: \Series.dateAdded, order: .reverse) private var series: [Series]

    /// Lecturas empezadas y sin terminar. Se consulta sobre `LocalComicFile`
    /// porque solo se puede leer aquello de lo que hay archivo: así el archivo
    /// importado suelto aparece igual que el vinculado a un número del catálogo.
    @Query(filter: #Predicate<LocalComicFile> { $0.lastReadAt != nil && !$0.isFinished },
           sort: \LocalComicFile.lastReadAt,
           order: .reverse)
    private var unfinishedFiles: [LocalComicFile]

    @Environment(SubscriptionStore.self) private var store
    @Environment(\.catalog) private var catalog

    @State private var paywall: PaywallReason?
    @State private var upcomingIssues: [IssueSummary] = []
    @State private var isLoadingUpcoming = false
    @State private var upcomingError: String?

    var body: some View {
        NavigationStack {
            // Una única pasada sobre la colección para todo el cuerpo.
            let snapshot = HomeSnapshot(series: series)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if snapshot.isEmpty && unfinishedFiles.isEmpty {
                        emptyState
                    } else {
                        followedSeriesSection(snapshot)
                        upcomingSection(snapshot)
                        continueReading

                        if !snapshot.collectionSeries.isEmpty {
                            heroCard(snapshot)
                            collectionGaps(snapshot)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("PanelMax")
            .toolbar {
                if !store.isPremium {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { paywall = .general } label: { PremiumBadge(text: "PANELMAX+") }
                    }
                }
            }
            .paywall($paywall)
            .task(id: snapshot.followedCatalogIDs) {
                await loadUpcoming(for: snapshot.followedCatalogIDs)
            }
        }
    }

    // MARK: - Estado vacío

    /// Una pantalla vacía es una invitación a actuar, no un cartel de "no hay nada".
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Tu estantería está vacía", systemImage: "books.vertical")
        } description: {
            Text("Busca una serie y añade el primer número. También puedes importar un CBZ que ya tengas.")
        }
        .padding(.top, 60)
    }

    // MARK: - Series seguidas

    @ViewBuilder
    private func followedSeriesSection(_ snapshot: HomeSnapshot) -> some View {
        if !snapshot.followedSeries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Theme.sectionLabel("Series que sigues")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(snapshot.followedSeries) { item in
                            NavigationLink {
                                SeriesDetailView(summary: item.catalogSummary)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    CoverImage(url: item.coverURL)
                                    Text(item.title)
                                        .font(.caption2.weight(.semibold))
                                        .lineLimit(2)
                                }
                                .frame(width: 88)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Abre la serie")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func upcomingSection(_ snapshot: HomeSnapshot) -> some View {
        if !snapshot.followedSeries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Theme.sectionLabel("Próximamente")

                if isLoadingUpcoming {
                    ProgressView("Buscando próximos números…")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else if let upcomingError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(upcomingError)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Button("Volver a intentar") {
                            Task { await loadUpcoming(for: snapshot.followedCatalogIDs) }
                        }
                        .font(.caption.weight(.semibold))
                    }
                } else if upcomingIssues.isEmpty {
                    Text("No hay próximos números anunciados para las series que sigues.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(upcomingIssues) { issue in
                                UpcomingIssueCard(issue: issue)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Destacado

    /// El primer hueco de una serie seguida. Si no hay huecos, la serie más reciente.
    @ViewBuilder
    private func heroCard(_ snapshot: HomeSnapshot) -> some View {
        if let highlight = snapshot.missingHighlights.first {
            heroBody(kicker: "TE FALTA EN LA COLECCIÓN",
                     title: highlight.series.title,
                     detail: "Nº \(highlight.number) · \(highlight.series.publisher)")
        } else if let recent = snapshot.collectionSeries.first {
            heroBody(kicker: "EN TU COLECCIÓN",
                     title: recent.title,
                     detail: "\(recent.allOwnedIssues.count) números · \(recent.publisher)")
        }
    }

    private func heroBody(kicker: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.accent)

            Text(title)
                .font(.largeTitle.weight(.heavy))
                .lineLimit(2)

            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panelGlass(cornerRadius: 14,
                    tint: Theme.accent.opacity(0.35),
                    fallbackFill: Theme.placeholder)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Continuar leyendo

    /// Una única sección para toda lectura en curso, venga de un número del
    /// catálogo o de un archivo importado sin vincular. Antes se leía de
    /// `Issue.progress`, así que un CBZ suelto que estabas leyendo no aparecía
    /// nunca aunque el lector sí guardaba su posición.
    @ViewBuilder
    private var continueReading: some View {
        if !unfinishedFiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Theme.sectionLabel("Continuar leyendo")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(unfinishedFiles) { file in
                            NavigationLink {
                                ReaderView(file: file)
                            } label: {
                                ReadingCard(file: file)
                                    .frame(width: 96)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Huecos

    @ViewBuilder
    private func collectionGaps(_ snapshot: HomeSnapshot) -> some View {
        if !snapshot.missingHighlights.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Theme.sectionLabel("Huecos en tus series")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(snapshot.missingHighlights) { gap in
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    CoverImage(url: gap.series.coverURL)
                                    Text("FALTA")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4).padding(.vertical, 2)
                                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 3))
                                        .foregroundStyle(.white)
                                        .padding(4)
                                }
                                Text(gap.series.title)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                Text("Nº \(gap.number)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .frame(width: 96)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Novedades

    private func loadUpcoming(for seriesIDs: [String]) async {
        guard !seriesIDs.isEmpty else {
            upcomingIssues = []
            upcomingError = nil
            isLoadingUpcoming = false
            return
        }

        isLoadingUpcoming = true
        upcomingError = nil

        do {
            let loaded = try await catalog.upcoming(seriesIDs: seriesIDs)
            guard !Task.isCancelled else { return }
            upcomingIssues = loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            upcomingIssues = []
            upcomingError = (error as? CatalogError)?.errorDescription ?? error.localizedDescription
        }

        isLoadingUpcoming = false
    }
}

// MARK: - Cálculo de secciones

/// Todo lo que Inicio necesita derivar de la colección, calculado de una vez.
private struct HomeSnapshot {

    let collectionSeries: [Series]
    let followedSeries: [Series]
    let followedCatalogIDs: [String]
    let missingHighlights: [Gap]

    var isEmpty: Bool { collectionSeries.isEmpty && followedSeries.isEmpty }

    init(series: [Series]) {
        var collection: [Series] = []
        var followed: [Series] = []
        var gaps: [Gap] = []

        for serie in series {
            // Una serie seguida pero sin números no convierte Inicio en una
            // pantalla aparentemente rota ni hace desaparecer el estado vacío.
            if !serie.allOwnedIssues.isEmpty {
                collection.append(serie)

                // Un hueco por serie como máximo: si enseñas los doce que le
                // faltan a alguien, deja de ser una ayuda y es un reproche.
                if let first = serie.missingNumbers.first {
                    gaps.append(Gap(series: serie, number: first))
                }
            }
            if serie.isFollowed {
                followed.append(serie)
            }
        }

        followed.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        self.collectionSeries = collection
        self.followedSeries = followed
        self.followedCatalogIDs = followed.map(\.catalogID).filter { !$0.isEmpty }
        self.missingHighlights = gaps
    }

    struct Gap: Identifiable {
        let series: Series
        let number: Int
        /// `persistentModelID` en lugar de `catalogID`: dos series sin id de
        /// catálogo producían la misma clave y SwiftUI reciclaba mal las celdas.
        var id: String { "\(series.persistentModelID.hashValue)-\(number)" }
    }
}

// MARK: - Tarjetas

private struct UpcomingIssueCard: View {
    let issue: IssueSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverImage(url: issue.coverURL)
            Text(issue.seriesTitle.isEmpty ? "Serie seguida" : issue.seriesTitle)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text("Nº \(issue.number)")
                .font(.system(size: 9))
                .foregroundStyle(Theme.secondaryText)
            if let date = issue.coverDate {
                Text(date, format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: 88)
        .accessibilityElement(children: .combine)
    }
}

/// Lectura en curso. Usa la portada del número si el archivo está vinculado
/// al catálogo y, si no, el marcador de posición con el nombre del archivo.
private struct ReadingCard: View {
    let file: LocalComicFile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                CoverImage(url: file.issue?.coverURL)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.25))
                        Capsule().fill(Theme.accent)
                            .frame(width: geometry.size.width * file.progressFraction)
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 5)
                    .offset(y: geometry.size.height - 8)
                }
            }

            Text(file.issue?.series?.title ?? file.displayName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)

            Text(file.progressDescription ?? "Sin empezar")
                .font(.system(size: 9))
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(file.issue?.series?.title ?? file.displayName)
        .accessibilityValue(file.progressDescription ?? "Sin empezar")
    }
}

private extension Series {
    var catalogSummary: SeriesSummary {
        SeriesSummary(id: catalogID,
                      title: title,
                      publisher: publisher,
                      startYear: startYear,
                      summary: summary,
                      coverURL: coverURL,
                      issueCount: totalIssues)
    }
}

#Preview {
    HomeView()
        .environment(SubscriptionStore())
        .modelContainer(PreviewData.container)
}
