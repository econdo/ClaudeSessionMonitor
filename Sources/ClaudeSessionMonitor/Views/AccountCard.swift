import SwiftUI

struct AccountCard: View {
    let account: Account
    @Environment(AccountStore.self) private var store
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var confirmingDelete = false
    @FocusState private var nameFieldFocused: Bool

    private var status: AccountStatus { store.status[account.id] ?? .idle }
    private var snapshot: UsageSnapshot? { store.usage[account.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            statusMessage
            if confirmingDelete {
                deleteConfirmation
            }
            if let snapshot {
                let primary = snapshot.limits.filter(\.isPrimary)
                let secondary = snapshot.limits.filter { !$0.isPrimary }
                ForEach(primary) { limit in
                    LimitRow(limit: limit, now: store.now, compact: false)
                }
                if !secondary.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(secondary) { limit in
                            LimitRow(limit: limit, now: store.now, compact: true)
                        }
                    }
                    .padding(.top, 2)
                }
                Text(Formatting.updatedDescription(snapshot.fetchedAt, now: store.now))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if status == .loading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Consultando…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Avatar(text: account.title)
            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    TextField(account.email, text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { isRenaming = false }
                } else {
                    Text(account.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !account.subtitle.isEmpty {
                    Text(account.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            if isRenaming {
                Button("OK", action: commitRename)
                    .controlSize(.small)
            } else {
                if store.accounts.count > 1, store.menuBarAccount?.id == account.id {
                    Image(systemName: "menubar.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Esta cuenta es la que se muestra en la barra de menús")
                }
                actionsMenu
            }
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch status {
        case .needsLogin:
            HStack(spacing: 8) {
                Label("La sesión ha caducado", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                Spacer()
                Button("Iniciar sesión") { store.beginLogin() }
                    .controlSize(.small)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .idle, .loading:
            EmptyView()
        }
    }

    private var deleteConfirmation: some View {
        HStack(spacing: 8) {
            Text("¿Quitar esta cuenta del monitor?")
                .font(.callout)
            Spacer()
            Button("Cancelar") { confirmingDelete = false }
                .controlSize(.small)
            Button("Quitar") { store.remove(account.id) }
                .controlSize(.small)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var actionsMenu: some View {
        Menu {
            Button("Actualizar") {
                Task { await store.refresh(account.id, manual: true) }
            }
            Button("Mostrar en la barra de menús") {
                store.menuBarAccountID = account.id
            }
            Button("Renombrar…") {
                draftName = account.customName ?? ""
                isRenaming = true
                nameFieldFocused = true
            }
            Button("Volver a iniciar sesión") {
                store.beginLogin()
            }
            if store.accounts.count > 1 {
                Divider()
                Button("Subir") { store.move(account.id, by: -1) }
                    .disabled(store.accounts.first?.id == account.id)
                Button("Bajar") { store.move(account.id, by: 1) }
                    .disabled(store.accounts.last?.id == account.id)
            }
            Divider()
            Button("Quitar cuenta…") {
                confirmingDelete = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func commitRename() {
        store.rename(account.id, to: draftName)
        isRenaming = false
    }
}

struct LimitRow: View {
    let limit: UsageLimit
    let now: Date
    let compact: Bool

    private var percent: Double { limit.effectivePercent(at: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.label)
                    .font(compact ? .caption : .system(size: 12, weight: .medium))
                    .foregroundStyle(compact ? .secondary : .primary)
                Spacer()
                Text(Formatting.percent(percent))
                    .font(compact ? .caption.weight(.medium) : .system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            UsageBar(fraction: percent / 100, height: compact ? 4 : 7)
            if !compact || percent > 0, let reset = Formatting.resetDescription(for: limit.resetsAt, now: now) {
                Text(reset)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct UsageBar: View {
    let fraction: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(.primary)
                    .frame(width: fraction > 0 ? max(height, proxy.size.width * min(fraction, 1)) : 0)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

struct Avatar: View {
    let text: String
    var size: CGFloat = 28

    var body: some View {
        let initial = text.first.map { String($0).uppercased() } ?? "?"
        Circle()
            .fill(.primary.opacity(0.12))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.46, weight: .semibold))
            }
    }
}
