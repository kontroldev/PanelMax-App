import SwiftUI
import SwiftData

/// Pantalla de inicio.
///
/// Nota de rendimiento: las secciones se calculan en memoria sobre las series
/// guardadas, no con predicados de SwiftData. Todo el trabajo se hace UNA vez
/// por evaluación del cuerpo, en `HomeSnapshot`.
struct HomeView: View {

    @Query(sort: \Series.dateAdded, order: .reverse) private var series: [Series]

    /// Lecturas empezadas y sin terminar. Se consulta sobre `LocalComicFile`
    /// porque solo se puede leer aquello de lo que hay archivo: así el archivo
    /// importado suelto aparece igual que el vinculado a un número catalogado.
    @Query(filter: #Predicate<LocalComicFile> { $0.lastReadAt != nil && !$0.isFinished },
           sort: \LocalComicFile.lastReadAt,
           order: .reverse)
    private var unfinishedFiles: [LocalComicFile]

    /// Ancho de las tarjetas de las tiras horizontales. Escala con el tamaño
    /// de texto: con Dynamic Type grande, 96 puntos fijos dejaban los títulos
    /// recortados a media palabra.
    @ScaledMetric(relativeTo: .caption2) private var cardWidth: CGFloat = 96

    @State private var presentedFile: LocalComicFile?

    var body: some View {
        NavigationStack {
            // Una única pasada sobre la colección para todo el cuerpo.
            let snapshot = HomeSnapshot(series: series)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if snapshot.isEmpty && unfinishedFiles.isEmpty {
                        emptyState
                    } else {
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
            .navigationTitle(AppInfo.displayName)
            .fullScreenCover(item: $presentedFile) { file in
                ReaderView(file: file)
            }
        }
    }

    // MARK: - Estado vacío

    /// Una pantalla vacía es una invitación a actuar, no un cartel de "no hay nada".
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Tu estantería está vacía", systemImage: "books.vertical")
        } description: {
            Text("Crea tu primera serie desde Mi colección, o importa un cómic desde Biblioteca para empezar a leer.")
        }
        .padding(.top, 60)
    }

    // MARK: - Destacado

    /// El primer hueco de una serie con huecos. Si no hay huecos, la serie más reciente.
    @ViewBuilder
    private func heroCard(_ snapshot: HomeSnapshot) -> some View {
        if let highlight = snapshot.missingHighlights.first {
            NavigationLink {
                SeriesDetailView(series: highlight.series)
            } label: {
                heroBody(kicker: "TE FALTA EN LA COLECCIÓN",
                        title: highlight.series.title,
                        detail: "Nº \(highlight.number) · \(highlight.series.publisher)")
            }
            .buttonStyle(.plain)
        } else if let recent = snapshot.collectionSeries.first {
            NavigationLink {
                SeriesDetailView(series: recent)
            } label: {
                heroBody(kicker: "EN TU COLECCIÓN",
                        title: recent.title,
                        detail: "\(recent.allOwnedIssues.count) números · \(recent.publisher)")
            }
            .buttonStyle(.plain)
        }
    }

    private func heroBody(kicker: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(.caption2.weight(.bold))
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

    /// Una única sección para toda lectura en curso, venga de un número
    /// catalogado o de un archivo importado sin vincular. Antes se leía de
    /// `Issue.progress`, así que un CBZ suelto que estabas leyendo no
    /// aparecía nunca aunque el lector sí guardaba su posición.
    @ViewBuilder
    private var continueReading: some View {
        if !unfinishedFiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Theme.sectionLabel("Continuar leyendo")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(unfinishedFiles) { file in
                            Button {
                                presentedFile = file
                            } label: {
                                ReadingCard(file: file, coverWidth: cardWidth)
                                    .frame(width: cardWidth)
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
                            NavigationLink {
                                SeriesDetailView(series: gap.series)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    ZStack(alignment: .topTrailing) {
                                        LocalCoverImage(url: nil, width: cardWidth)
                                            .accessibilityHidden(true)
                                        Text("FALTA")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 4).padding(.vertical, 2)
                                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 3))
                                            .foregroundStyle(.white)
                                            .padding(4)
                                    }
                                    Text(gap.series.title)
                                        .font(.caption2.weight(.semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text("Nº \(gap.number)")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                .frame(width: cardWidth)
                                .accessibilityElement(children: .combine)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Tarjetas

/// Lectura en curso. La portada sale del propio archivo importado, esté o no
/// vinculado a un número catalogado.
private struct ReadingCard: View {
    let file: LocalComicFile
    let coverWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                LocalCoverImage(url: file.thumbnailURL, width: coverWidth)

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
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(file.issue?.series?.title ?? file.displayName)
        .accessibilityValue(file.progressDescription ?? "Sin empezar")
    }
}

#Preview {
    HomeView()
        .modelContainer(PreviewData.container)
}
