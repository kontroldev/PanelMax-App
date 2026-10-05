import SwiftUI
import SwiftData

/// Perfil y ajustes.
///
/// Sin catálogo ni suscripción, esta pantalla se reduce a lo que de verdad
/// es: estadísticas de la colección, exportación y lo legal.
struct SettingsView: View {

    @Query(sort: \Series.title) private var series: [Series]
    @Environment(\.modelContext) private var context

    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showsOnboarding = false

    private var store: CollectionStore { CollectionStore(context: context) }

    var body: some View {
        NavigationStack {
            List {
                statsSection
                exportSection
                legalSection
                aboutSection
            }
            .navigationTitle("Perfil")
            .alert("No se ha podido exportar", isPresented: Binding(
                get: { exportError != nil },
                set: { visible in if !visible { exportError = nil } }
            )) {
                Button("De acuerdo", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .fullScreenCover(isPresented: $showsOnboarding) {
                OnboardingView { showsOnboarding = false }
            }
        }
    }

    // MARK: - Estadísticas

    private var stats: (entries: Int, seriesCount: Int) {
        (store.entryCount(), series.count)
    }

    private var statsSection: some View {
        Section("Tu colección") {
            LabeledContent("Números guardados", value: "\(stats.entries)")
            LabeledContent("Series catalogadas", value: "\(stats.seriesCount)")
        }
    }

    // MARK: - Exportar colección

    /// No se llama «Copia de seguridad» a propósito: la app todavía no puede
    /// volver a importar este archivo, y llamarlo así hacía pensar que basta
    /// con él para recuperar la colección en otro dispositivo.

    private var exportSection: some View {
        Section {
            Button {
                prepareExport()
            } label: {
                Label("Preparar exportación", systemImage: "square.and.arrow.up")
            }
            .accessibilityHint("Genera un archivo con tu colección. Después podrás compartirlo o guardarlo.")

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Compartir archivo", systemImage: "doc.badge.arrow.up")
                }
                // El botón aparece solo después de preparar la exportación.
                // Sin este aviso, con VoiceOver surge de la nada sin que nada
                // indique que la acción anterior ha terminado bien.
                .accessibilityHint("El archivo está listo. Elige dónde guardarlo o con qué app compartirlo.")
            }
        } header: {
            Text("Exportar colección")
        } footer: {
            Text("Genera un archivo JSON con tus series y números: qué tienes y en qué estado. Puedes guardarlo en Archivos o compartirlo para tener tus datos fuera del dispositivo. Por ahora \(AppInfo.displayName) no puede volver a importarlo para restaurar la colección. Los cómics importados no se incluyen.")
        }
    }

    private func prepareExport() {
        do {
            exportURL = try CollectionExporter.makeExportFile(series: series)
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        Section("Legal") {
            Link("Condiciones de uso", destination: LegalLinks.terms)
            Link("Política de privacidad", destination: LegalLinks.privacy)
            Link("Soporte", destination: LegalLinks.support)
        }
        // Los tres abren el navegador. Anunciarlo evita la sorpresa de salir
        // de la app sin previo aviso, que con VoiceOver desorienta bastante.
        .accessibilityHint("Se abre en el navegador")
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Versión", value: Bundle.main.appVersion)

            Button {
                showsOnboarding = true
            } label: {
                Label("Ver introducción", systemImage: "hand.wave")
            }
            .accessibilityHint("Vuelve a enseñar la presentación de bienvenida de \(AppInfo.displayName).")
        } header: {
            Text("Acerca de")
        } footer: {
            Text("\(AppInfo.displayName) funciona sin conexión: no envía ni recibe nada por internet. Todo lo que catalogas y todo lo que importas se queda en tu dispositivo.")
        }
    }
}

extension Bundle {
    /// "1.0 (1)", que es lo que hay que enseñar en Ajustes y pedir en los informes de fallo.
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
