import SwiftUI

@main
struct ClaudeSessionMonitorApp: App {
    @State private var store = AccountStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let store: AccountStore

    var body: some View {
        Image(nsImage: icon)
    }

    private var icon: NSImage {
        guard let account = store.menuBarAccount else {
            // Sin cuentas todavía: el logo entero, como icono normal de la app. Con todas desactivadas: translúcido.
            return MenuBarIcon.image(weeklyPercent: store.accounts.isEmpty ? 100 : nil, text: nil)
        }
        if store.status[account.id] == .needsLogin {
            return MenuBarIcon.image(weeklyPercent: nil, text: "!")
        }
        let snapshot = store.usage[account.id]
        let session = snapshot?.session?.effectivePercent(at: store.now)
        let weekly = snapshot?.weekly?.effectivePercent(at: store.now)

        // Los planes sin ventana de 5 h (Ultra) no tienen sesión: en esos casos se muestra el semanal.
        let weeklyText = weekly.map { "\(Int($0.rounded()))%" } ?? "–"
        let text: String?
        switch store.menuBarText {
        case .session:
            text = session.map { "\(Int($0.rounded()))%" } ?? weeklyText
        case .weekly:
            text = weeklyText
        case .sessionAndWeekly:
            text = session.map { "\(Int($0.rounded())) · \(weeklyText)" } ?? weeklyText
        case .none:
            text = nil
        }
        return MenuBarIcon.image(weeklyPercent: weekly, text: text)
    }
}
