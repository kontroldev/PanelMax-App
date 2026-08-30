import SwiftUI
import SwiftData

/// Contenedor de pestañas.
///
/// Biblioteca importada era antes un `NavigationLink` escondido dentro de
/// Perfil. En una app sin catálogo, importar y leer es la mitad del
/// producto, así que sube a pestaña propia.
struct RootView: View {

    private let persistenceWarning: String?
    @State private var showsPersistenceWarning: Bool

    init(persistenceWarning: String? = nil) {
        self.persistenceWarning = persistenceWarning
        _showsPersistenceWarning = State(initialValue: persistenceWarning != nil)
    }

    /// Pestaña seleccionada. Se guarda para que la app vuelva donde estabas.
    @AppStorage("selectedTab") private var selection: Tab = .home

    enum Tab: String {
        case home, collection, library, profile
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Inicio", systemImage: "house.fill") }
                .tag(Tab.home)

            CollectionView()
                .tabItem { Label("Mi colección", systemImage: "books.vertical.fill") }
                .tag(Tab.collection)

            ImportedLibraryView()
                .tabItem { Label("Biblioteca", systemImage: "square.and.arrow.down.on.square.fill") }
                .tag(Tab.library)

            SettingsView()
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(Theme.accent)
        .alert("La colección no está disponible", isPresented: $showsPersistenceWarning) {
            Button("De acuerdo", role: .cancel) {}
        } message: {
            Text("PanelMax ha arrancado en modo temporal para no modificar tus datos. Cierra la app y vuelve a intentarlo después de actualizarla. Detalle: \(persistenceWarning ?? "")")
        }
    }
}

#Preview {
    RootView(persistenceWarning: nil)
        .modelContainer(PreviewData.container)
}
