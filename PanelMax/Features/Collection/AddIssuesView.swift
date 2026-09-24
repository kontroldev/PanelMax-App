import SwiftUI
import SwiftData

/// Alta de números: por rango o sueltos.
///
/// El alta por rango es lo que hace viable catalogar a mano una colección
/// real. Sin ella, meter "del 1 al 40" son cuarenta toques uno a uno.
struct AddIssuesView: View {

    let series: Series

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .range
    @State private var singleNumber = ""
    @State private var rangeStartText = "1"
    @State private var rangeEndText = ""
    @State private var state: CollectionState = .owned
    @State private var format: CollectionFormat = .physical
    @State private var errorMessage: String?

    private var store: CollectionStore { CollectionStore(context: context) }

    enum Mode: String, CaseIterable, Identifiable {
        case range = "Rango"
        case single = "Número suelto"
        var id: String { rawValue }
    }

    /// Límite defensivo: evita que un rango escrito por error (o con las
    /// cifras cambiadas) intente crear cientos de miles de filas de golpe.
    private static let maximumRangeSize = 2000

    var body: some View {
        NavigationStack {
            Form {
                Picker("Modo", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                switch mode {
                case .range:
                    Section {
                        // En iPad, `.numberPad` se muestra como un teclado compacto
                        // flotante que puede tapar el propio campo. `.numbersAndPunctuation`
                        // es de ancho completo y se acopla abajo como el teclado normal.
                        TextField("Desde", text: $rangeStartText)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Desde el número")
                        TextField("Hasta", text: $rangeEndText)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Hasta el número")
                    } header: {
                        Text("Del número… al número…")
                    } footer: {
                        Text("Los números que ya tuvieras en esta serie no se duplican.")
                    }
                case .single:
                    Section {
                        TextField("Ej. 1/2, Anual 2024, 12", text: $singleNumber)
                            .accessibilityLabel("Número")
                            .accessibilityHint("Admite especiales, como 1/2 o Anual 2024.")
                    } header: {
                        Text("Número")
                    } footer: {
                        Text("Sirve para especiales que no encajan en un rango numérico.")
                    }
                }

                Section("Cómo lo tienes") {
                    Picker("Estado", selection: $state) {
                        ForEach(CollectionState.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Formato", selection: $format) {
                        ForEach(CollectionFormat.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle("Añadir números")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir") { add() }.disabled(!isValid)
                }
            }
            .alert("No se ha podido añadir", isPresented: Binding(
                get: { errorMessage != nil },
                set: { visible in if !visible { errorMessage = nil } }
            )) {
                Button("De acuerdo", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isValid: Bool {
        switch mode {
        case .range:
            guard let start = Int(rangeStartText), let end = Int(rangeEndText) else { return false }
            return start <= end && (end - start) < Self.maximumRangeSize
        case .single:
            return !singleNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func add() {
        do {
            switch mode {
            case .range:
                guard let start = Int(rangeStartText), let end = Int(rangeEndText) else { return }
                try store.addIssueRange(from: start, through: end, to: series, state: state, format: format)
            case .single:
                let number = singleNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                try store.addIssue(number: number, to: series, state: state, format: format)
            }
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddIssuesView(series: Series(catalogID: "preview", title: "Serie de ejemplo"))
        .modelContainer(PreviewData.container)
}
