import SwiftUI
import SwiftData

/// Contenedor de pestañas.
///
/// Biblioteca importada era antes un `NavigationLink` escondido dentro de
/// Perfil. En una app sin catálogo, importar y leer es la mitad del
/// producto, así que sube a pestaña propia.
struct RootView: View {

    /// Se guarda directamente, no con `@AppStorage`: solo se lee una vez, en
    /// `init`, para decidir si `showsOnboarding` empieza en `true`. Igual que
    /// hacía `SampleLibrarySeeder` con su propia bandera.
    private static let onboardingSeenKey = "panelmax.onboardingSeen"

    @Environment(\.modelContext) private var modelContext

    private let persistenceWarning: String?
    @State private var showsPersistenceWarning: Bool
    @State private var showsOnboarding: Bool

    init(persistenceWarning: String? = nil) {
        self.persistenceWarning = persistenceWarning
        _showsPersistenceWarning = State(initialValue: persistenceWarning != nil)
        _showsOnboarding = State(initialValue: !UserDefaults.standard.bool(forKey: Self.onboardingSeenKey))
    }

    /// Pestaña seleccionada. Se guarda para que la app vuelva donde estabas.
    @AppStorage("selectedTab") private var selection: Tab = .home

    enum Tab: String {
        case home, collection, library, profile
    }

    var body: some View {
        TabView(selection: $selection) {
            LazyTabContent { HomeView() }
                .tabItem { Label("Inicio", systemImage: "house.fill") }
                .tag(Tab.home)

            LazyTabContent { CollectionView() }
                .tabItem { Label("Mi colección", systemImage: "books.vertical.fill") }
                .tag(Tab.collection)

            LazyTabContent { ImportedLibraryView() }
                .tabItem { Label("Biblioteca", systemImage: "square.and.arrow.down.on.square.fill") }
                .tag(Tab.library)

            LazyTabContent { SettingsView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(Theme.accent)
        .task {
            LibraryStore(context: modelContext).removeLegacySampleComicIfNeeded()
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: Self.onboardingSeenKey)
                showsOnboarding = false
            }
        }
        .alert("La colección no está disponible", isPresented: $showsPersistenceWarning) {
            Button("De acuerdo", role: .cancel) {}
        } message: {
            Text("\(AppInfo.displayName) ha arrancado en modo temporal para no modificar tus datos. Cierra la app y vuelve a intentarlo después de actualizarla. Detalle: \(persistenceWarning ?? "")")
        }
    }
}

#Preview {
    RootView(persistenceWarning: nil)
        .modelContainer(PreviewData.container)
}

/// Retrasa la construcción del contenido de una pestaña hasta que aparece de
/// verdad en pantalla.
///
/// `TabView` no es tan perezoso como parece: a arrancar, construye también
/// el `body` de alguna pestaña vecina a la seleccionada (se ha comprobado
/// que pasa con "Mi colección" aunque la pestaña activa sea otra),
/// probablemente para poder deslizar entre pestañas sin tirones. Eso
/// significa que sus `@Query` se disparan y `CollectionSnapshot`/
/// `HomeSnapshot` se calculan sobre TODA la colección aunque el usuario no
/// esté mirando esa pestaña, y con una colección grande ese trabajo de
/// fondo es justo lo que retrasa el primer fotograma. Envolviendo el
/// contenido real en un `Color.clear` hasta el primer `onAppear` de verdad,
/// esa pestaña no hace ningún trabajo hasta que el usuario la visita.
private struct LazyTabContent<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var hasAppeared = false

    var body: some View {
        Group {
            if hasAppeared {
                content()
            } else {
                Color.clear
            }
        }
        .onAppear { hasAppeared = true }
    }
}
