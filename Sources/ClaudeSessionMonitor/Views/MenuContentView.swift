import SwiftUI

struct MenuContentView: View {
    @Environment(AccountStore.self) private var store
    @State private var showingSettings = false
    /// Altura real de las tarjetas, medida tras cada maquetación. Se recuerda la última para que el panel
    /// no se abra vacío antes de la primera medición.
    @State private var cardsHeight = MenuContentView.lastCardsHeight
    private static var lastCardsHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if store.isLoginActive {
                    AddAccountPanel()
                } else if showingSettings {
                    SettingsPanel { showingSettings = false }
                } else {
                    accountList
                }
            }
            Divider()
            footer
        }
        .frame(width: 360)
        // Monocromo: que casillas, foco y demás controles no usen el color de acento del sistema.
        .tint(.gray)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(.secondary)
            Text("Uso de Claude")
                .font(.headline)
            Spacer()
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await store.refreshAll(manual: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.accounts.isEmpty || store.isRefreshing)
            .help("Actualizar ahora")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var accountList: some View {
        if store.accounts.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Añade tus cuentas de Claude")
                    .font(.headline)
                Text("Inicia sesión con cada cuenta para ver el uso de la sesión actual, el semanal y cuándo se reinician.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Añadir cuenta") { store.beginLogin() }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        } else {
            let list = VStack(spacing: 10) {
                if let email = store.lastAddedEmail {
                    addedBanner(email)
                }
                ForEach(store.accounts) { account in
                    AccountCard(account: account)
                }
            }
            .padding(12)

            WeeklySummary()
            Divider()
            ScrollView {
                list.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    cardsHeight = height
                    Self.lastCardsHeight = height
                }
            }
            .frame(height: min(cardsHeight, maxCardsHeight))
        }
    }

    /// Las tarjetas ocupan lo que necesiten hasta que el panel llenaría la pantalla; a partir de ahí hacen scroll
    /// y el resumen semanal queda fijo arriba.
    private var maxCardsHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let summaryHeight = 40 + CGFloat(store.accounts.count) * 25
        return max(240, screenHeight - summaryHeight - 140)
    }

    private func addedBanner(_ email: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
            Text("Cuenta añadida: \(email)")
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                store.dismissAddedBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                showingSettings = false
                store.beginLogin()
            } label: {
                Label("Añadir cuenta", systemImage: "plus")
            }
            .disabled(store.isLoginActive)
            Spacer()
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: showingSettings ? "gearshape.fill" : "gearshape")
            }
            .help("Ajustes")
            .disabled(store.isLoginActive)
            Button("Salir") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
