import SwiftUI

/// Presentación de bienvenida del primer arranque.
///
/// Sustituye al antiguo `SampleLibrarySeeder`, que copiaba un CBZ de ejemplo
/// en la Biblioteca para que la app no se viera vacía (ni siquiera para un
/// revisor de App Store en un dispositivo limpio). Esto cumple el mismo
/// papel explicando en unas pocas pantallas qué hace Viñe antes de que el
/// usuario haya importado nada, sin dejar un cómic falso en su biblioteca.
struct OnboardingView: View {

    /// Se llama al terminar la última pantalla o al saltar con la X. Quien
    /// presenta esta vista (`RootView`) decide qué hacer con eso: marcar la
    /// bandera de «ya visto» y cerrar el `fullScreenCover`.
    let onFinish: () -> Void

    @State private var page = 0

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Bienvenido a \(AppInfo.displayName)",
            subtitle: "Tu lector de cómics privado: importa, organiza y lee, todo en tu dispositivo.",
            content: .logo
        ),
        OnboardingPage(
            title: "Importa tus cómics",
            subtitle: "Añade tus CBZ o PDF desde Archivos o iCloud Drive. \(AppInfo.displayName) guarda una copia privada para que sigan abriéndose aunque el original desaparezca.",
            content: .library
        ),
        OnboardingPage(
            title: "Organiza tu colección",
            subtitle: "Crea series, añade los números que tienes y descubre de un vistazo los huecos que te faltan.",
            content: .collection
        ),
        OnboardingPage(
            title: "Lee a tu ritmo",
            subtitle: "Pasa página, haz zoom o lee a doble página en iPad. Viñe recuerda dónde lo dejaste.",
            content: .reader
        ),
        OnboardingPage(
            title: "Sin nube. Sin cuenta.",
            subtitle: "Nada de lo que importes o leas sale de tu iPhone o iPad.",
            content: .icon("lock.shield.fill")
        )
    ]

    var body: some View {
        ZStack {
            Theme.groupedBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onFinish) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(10)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Saltar la introducción")
                }
                .padding([.top, .horizontal])

                TabView(selection: $page) {
                    ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 6) {
                    ForEach(Self.pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.accent : Theme.hairline)
                            .frame(width: index == page ? 20 : 6, height: 6)
                    }
                }
                .animation(.default, value: page)
                .padding(.bottom, 20)

                HStack(spacing: 12) {
                    if page > 0 {
                        Button("Atrás") { page -= 1 }
                            .buttonStyle(.bordered)
                    }

                    Button(page == Self.pages.count - 1 ? "Empezar" : "Siguiente") {
                        if page == Self.pages.count - 1 {
                            onFinish()
                        } else {
                            page += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }
}

private enum OnboardingContent {
    case icon(String)
    case logo
    case library
    case collection
    case reader
}

private struct OnboardingPage {
    let title: String
    let subtitle: String
    let content: OnboardingContent
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 260, height: 260)

                content
            }

            VStack(spacing: 10) {
                Text(page.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var content: some View {
        switch page.content {
        case .icon(let symbol):
            Image(systemName: symbol)
                .font(.system(size: 88, weight: .regular))
                .foregroundStyle(Theme.accent)
        case .logo:
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        case .library:
            // Vista previa no interactiva de tamaño fijo, como una captura de
            // pantalla: se limita a `.large` para que el texto no se recorte
            // dentro de la tarjeta a tamaños de accesibilidad grandes. El
            // texto real de la app (título y subtítulo de esta misma
            // pantalla) sigue escalando sin límite.
            LibraryMockupCard()
                .dynamicTypeSize(...DynamicTypeSize.large)
        case .collection:
            CollectionMockupCard()
                .dynamicTypeSize(...DynamicTypeSize.large)
        case .reader:
            ReaderMockupCard()
                .dynamicTypeSize(...DynamicTypeSize.large)
        }
    }
}

// MARK: - Mockups

/// Vista previa no interactiva de `ImportedLibraryView`: solo para ilustrar
/// la pantalla de importación en la presentación de bienvenida.
private struct LibraryMockupCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Biblioteca")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
            }

            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.accent.opacity(0.18 + Double(index) * 0.08))
                        .frame(width: 30, height: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.hairline)
                            .frame(width: 120, height: 8)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.hairline.opacity(0.6))
                            .frame(width: 70, height: 6)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(width: 240)
        .panelGlass()
    }
}

/// Vista previa no interactiva de `CollectionView`/`SeriesDetailView`: series
/// con su barra de progreso, como aparecerían tras catalogar unos números.
private struct CollectionMockupCard: View {
    /// Títulos inventados a propósito: con series reales (Marvel, DC...) esta
    /// pantalla, que suele salir en las capturas de la App Store, se expone a
    /// un rechazo por propiedad intelectual (guía 5.2.1).
    private let series: [(name: String, progress: Double)] = [
        ("Cuervo Negro", 0.8),
        ("La Liga del Faro", 0.45)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mi colección")
                .font(.subheadline.weight(.semibold))

            ForEach(series, id: \.name) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.name)
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text("\(Int(item.progress * 100)) %")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ProgressView(value: item.progress)
                        .tint(Theme.accent)
                }
            }
        }
        .padding(16)
        .frame(width: 240)
        .panelGlass()
    }
}

/// Vista previa no interactiva de `ReaderView`: una página cualquiera con su
/// indicador de posición, para anticipar el gesto de lectura.
private struct ReaderMockupCard: View {
    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.accent.opacity(0.15))
                .frame(width: 150, height: 200)
                .overlay {
                    Image(systemName: "book.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent)
                }

            HStack(spacing: 16) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Theme.secondaryText)
                Text("Pág. 12 / 24")
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(16)
        .panelGlass()
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
