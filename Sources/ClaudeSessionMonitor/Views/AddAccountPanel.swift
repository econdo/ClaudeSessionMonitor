import SwiftUI

struct AddAccountPanel: View {
    @Environment(AccountStore.self) private var store
    @State private var manualCode = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Añadir cuenta de Claude")
                .font(.headline)

            switch store.loginPhase {
            case .idle, .preparing:
                ProgressView()
                    .controlSize(.small)
            case .waiting:
                waiting
            case .exchanging:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Verificando la cuenta…")
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Volver a intentarlo") {
                    store.beginLogin(manual: store.pendingLogin?.isManual ?? false)
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") { store.cancelLogin() }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var waiting: some View {
        let isManual = store.pendingLogin?.isManual ?? false

        Text("Inicia sesión en claude.ai con la cuenta que quieres añadir y pulsa «Autorizar».")
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 8) {
            Button("Abrir en el navegador") { store.openLoginInBrowser() }
            Button(copied ? "Enlace copiado" : "Copiar enlace") {
                store.copyLoginURL()
                copied = true
            }
        }

        Text("Si el navegador ya tiene abierta otra cuenta de Claude, pega el enlace en una ventana privada (⇧⌘N) o cierra sesión en claude.ai antes de autorizar.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if isManual {
            Text("Al autorizar, Claude mostrará un código. Pégalo aquí:")
                .font(.callout)
            HStack(spacing: 8) {
                TextField("Código de autorización", text: $manualCode)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.submitManualCode(manualCode) }
                Button("Confirmar") { store.submitManualCode(manualCode) }
                    .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Esperando la autorización…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("¿El navegador no vuelve a la app? Usar un código") {
                copied = false
                store.beginLogin(manual: true)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .underline()
            .foregroundStyle(.secondary)
        }
    }
}
