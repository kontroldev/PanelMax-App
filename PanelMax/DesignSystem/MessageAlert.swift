import SwiftUI

extension View {
    /// Alerta con un único botón «De acuerdo» que aparece cuando `message`
    /// tiene texto y se cierra devolviéndolo a `nil`.
    ///
    /// Sustituye al mismo `Binding(get:set:)` que se repetía en nueve
    /// pantallas para avisar de errores. Así el puente entre «hay un mensaje»
    /// y «la alerta está visible» se escribe una sola vez, aquí.
    func messageAlert(_ title: LocalizedStringKey, message: Binding<String?>) -> some View {
        modifier(MessageAlert(title: title, message: message))
    }
}

private struct MessageAlert: ViewModifier {
    let title: LocalizedStringKey
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(title, isPresented: isPresented) {
            Button("De acuerdo", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    /// Visible mientras haya mensaje; al cerrarla se borra el mensaje.
    private var isPresented: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { visible in if !visible { message = nil } }
        )
    }
}
