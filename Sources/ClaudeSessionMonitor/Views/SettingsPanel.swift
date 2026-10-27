import SwiftUI

struct SettingsPanel: View {
    @Environment(AccountStore.self) private var store
    let onDone: () -> Void

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 14) {
            Text("Ajustes")
                .font(.headline)

            Picker("Actualizar cada", selection: $store.refreshMinutes) {
                ForEach([1, 2, 5, 10, 15, 30], id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }

            if !store.accounts.isEmpty {
                Picker("Cuenta en la barra", selection: Binding(
                    get: { store.menuBarAccount?.id },
                    set: { store.menuBarAccountID = $0 }
                )) {
                    ForEach(store.accounts) { account in
                        Text(account.title).tag(Optional(account.id))
                    }
                }
            }

            Picker("Texto en la barra", selection: $store.menuBarText) {
                ForEach(MenuBarText.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            Toggle("Avisar al llegar al \(AccountStore.notificationThresholds.map { "\($0) %" }.joined(separator: " y "))",
                   isOn: $store.notificationsEnabled)

            Toggle("Abrir al iniciar sesión en el Mac", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))

            Text("Los tokens de cada cuenta se guardan en el llavero de macOS. Las cuentas que añadas aquí no afectan a la sesión de Claude Code.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Hecho", action: onDone)
            }
        }
        .padding(14)
    }
}
