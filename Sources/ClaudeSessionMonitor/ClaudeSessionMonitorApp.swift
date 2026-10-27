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
            // Sin cuentas todavía: el logo entero, como icono normal de la app.
            return MenuBarIcon.image(weeklyPercent: 100, text: nil)
        }
        if store.status[account.id] == .needsLogin {
            return MenuBarIcon.image(weeklyPercent: nil, text: "!")
        }
        let snapshot = store.usage[account.id]
        let session = snapshot?.session?.effectivePercent(at: store.now)
        let weekly = snapshot?.weekly?.effectivePercent(at: store.now)

        let text: String?
        switch store.menuBarText {
        case .session:
            text = session.map { "\(Int($0.rounded()))%" } ?? "–"
        case .weekly:
            text = weekly.map { "\(Int($0.rounded()))%" } ?? "–"
        case .sessionAndWeekly:
            text = "\(session.map { "\(Int($0.rounded()))" } ?? "–") · \(weekly.map { "\(Int($0.rounded()))%" } ?? "–")"
        case .none:
            text = nil
        }
        return MenuBarIcon.image(weeklyPercent: weekly, text: text)
    }
}
