import SwiftUI

/// Elegir qué archivo importado (sin vincular todavía) corresponde a un número.
///
/// Catalogar y leer son dos flujos separados en la 1.0: el usuario puede
/// anotar que tiene el número 12 en papel sin haber importado nada, y puede
/// importar un CBZ sin haberlo catalogado antes. Esta pantalla es el punto
/// donde ambos flujos se encuentran.
struct LinkFileView: View {

    let issue: Issue
    let candidates: [LocalComicFile]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("No hay archivos sin vincular", systemImage: "link")
                    } description: {
                        Text("Importa un CBZ o PDF desde Biblioteca y vuelve aquí para asociarlo a este número.")
                    }
                } else {
                    List(candidates) { file in
                        Button {
                            link(file)
                        } label: {
                            HStack(spacing: 12) {
                                LocalCoverImage(url: file.thumbnailURL, cornerRadius: 4).frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.displayName).font(.subheadline)
                                    Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        // Sin esto, VoiceOver lee la portada, el nombre y el
                        // tamaño como tres elementos sueltos, y no queda claro
                        // que la fila entera sea el botón.
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Vincula este archivo al número \(issue.number)")
                    }
                }
            }
            .navigationTitle("Vincular a Nº \(issue.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .alert("No se ha podido vincular", isPresented: Binding(
                get: { errorMessage != nil },
                set: { visible in if !visible { errorMessage = nil } }
            )) {
                Button("De acuerdo", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func link(_ file: LocalComicFile) {
        do {
            try CollectionStore(context: context).link(file, to: issue)
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
