import SwiftUI
import SwiftData

/// Perfil y ajustes.
///
/// Sin catálogo ni suscripción, esta pantalla se reduce a lo que de verdad
/// es: estadísticas de la colección, copia de seguridad y lo legal.
struct SettingsView: View {

    @Query(sort: \Series.title) private var series: [Series]
    @Environment(\.modelContext) private var context

    @State private var exportURL: URL?
    @State private var exportError: String?

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
        }
    }

    // MARK: - Estadísticas

    private var stats: (entries: Int, seriesCount: Int) {
        (CollectionStore(context: context).entryCount(), series.count)
    }

    private var statsSection: some View {
        Section("Tu colección") {
            LabeledContent("Números guardados", value: "\(stats.entries)")
            LabeledContent("Series catalogadas", value: "\(stats.seriesCount)")
        }
    }

    // MARK: - Copia de seguridad

    private var exportSection: some View {
        Section {
            Button {
                prepareExport()
            } label: {
                Label("Preparar exportación", systemImage: "square.and.arrow.up")
            }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Compartir archivo", systemImage: "doc.badge.arrow.up")
                }
            }
        } header: {
            Text("Copia de seguridad")
        } footer: {
            Text("PanelMax no usa iCloud ni cuenta: esta exportación es tu única copia de la colección catalogada a mano. Los archivos importados no se incluyen, solo los datos de qué tienes y en qué estado.")
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
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Versión", value: Bundle.main.appVersion)
        } header: {
            Text("Acerca de")
        } footer: {
            Text("PanelMax funciona sin conexión: no envía ni recibe nada por internet. Todo lo que catalogas y todo lo que importas se queda en tu dispositivo.")
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
