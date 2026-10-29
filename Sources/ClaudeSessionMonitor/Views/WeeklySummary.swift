import SwiftUI

/// Resumen fijo en lo alto del panel: el uso semanal de cada cuenta, una fila por cuenta.
/// Con varias cuentas, cada fila sirve también para elegir la cuenta activa (la que se muestra en la barra de menús).
struct WeeklySummary: View {
    @Environment(AccountStore.self) private var store

    var body: some View {
        let selectable = store.accounts.count > 1

        VStack(alignment: .leading, spacing: 7) {
            Text("Uso semanal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(store.accounts) { account in
                if selectable {
                    Button { store.menuBarAccountID = account.id } label: { row(account, selectable: true) }
                        .buttonStyle(.plain)
                        .help("Pulsa para mostrar esta cuenta en la barra de menús")
                } else {
                    row(account, selectable: false)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func row(_ account: Account, selectable: Bool) -> some View {
        let weekly = store.usage[account.id]?.weekly
        let percent = weekly?.effectivePercent(at: store.now)
        let isActive = selectable && store.menuBarAccount?.id == account.id

        return HStack(spacing: 6) {
            if selectable {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? .primary : .tertiary)
                    .frame(width: 18)
                    .accessibilityLabel(isActive ? "Cuenta activa" : "Cuenta no activa")
            } else {
                Avatar(text: account.title, size: 18)
            }
            Text(account.title)
                .font(.callout.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if store.status[account.id] == .needsLogin {
                Label("Sesión caducada", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let percent {
                UsageBar(fraction: percent / 100, height: 5)
                    .frame(width: 44)
                Text(Formatting.percent(percent))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                Text(Formatting.shortReset(weekly?.resetsAt, now: store.now))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 76, alignment: .trailing)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
