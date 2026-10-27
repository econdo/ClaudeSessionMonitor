import SwiftUI

/// Resumen fijo en lo alto del panel: el uso semanal de cada cuenta, una fila por cuenta.
struct WeeklySummary: View {
    @Environment(AccountStore.self) private var store
    /// Si se indica, cada fila es pulsable (se usa para saltar a la tarjeta de la cuenta cuando la lista hace scroll).
    var onSelect: ((UUID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Uso semanal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(store.accounts) { account in
                if let onSelect {
                    Button { onSelect(account.id) } label: { row(account) }
                        .buttonStyle(.plain)
                } else {
                    row(account)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func row(_ account: Account) -> some View {
        let weekly = store.usage[account.id]?.weekly
        let percent = weekly?.effectivePercent(at: store.now)

        return HStack(spacing: 6) {
            Avatar(text: account.title, size: 18)
            Text(account.title)
                .font(.callout)
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
        .help(Formatting.resetDescription(for: weekly?.resetsAt, now: store.now) ?? "")
    }
}
