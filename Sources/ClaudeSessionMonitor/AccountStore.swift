import AppKit
import Foundation
import Observation
import ServiceManagement
import UserNotifications

enum LoginPhase: Equatable {
    case idle
    case preparing
    case waiting
    case exchanging
    case failed(String)
}

struct PendingLogin {
    let pkce: ClaudeAPI.PKCE
    let redirectURI: String
    let url: URL
    let isManual: Bool
}

@Observable
final class AccountStore {
    private(set) var accounts: [Account] = []
    private(set) var usage: [UUID: UsageSnapshot] = [:]
    private(set) var status: [UUID: AccountStatus] = [:]
    private(set) var loginPhase: LoginPhase = .idle
    private(set) var pendingLogin: PendingLogin?
    private(set) var lastAddedEmail: String?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Reloj que avanza cada 30 s para que las cuentas atrás de la interfaz se actualicen.
    private(set) var now = Date()

    var refreshMinutes: Int {
        didSet {
            defaults.set(refreshMinutes, forKey: Keys.refreshMinutes)
            startPolling()
        }
    }

    var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: Keys.notifications)
            if notificationsEnabled { requestNotificationPermission() }
        }
    }

    var menuBarAccountID: UUID? {
        didSet { defaults.set(menuBarAccountID?.uuidString, forKey: Keys.menuBarAccount) }
    }

    var menuBarText: MenuBarText {
        didSet { defaults.set(menuBarText.rawValue, forKey: Keys.menuBarText) }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let callbackServer = OAuthCallbackServer()
    @ObservationIgnored private var tokens: [UUID: OAuthTokens] = [:]
    @ObservationIgnored private var inFlight: Set<UUID> = []
    @ObservationIgnored private var blockedUntil: [UUID: Date] = [:]
    @ObservationIgnored private var notified: [String: Int]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private let notificationPresenter = NotificationPresenter()

    private enum Keys {
        static let accounts = "accounts"
        static let usage = "usageCache"
        static let notified = "notifiedThresholds"
        static let refreshMinutes = "refreshMinutes"
        static let notifications = "notificationsEnabled"
        static let menuBarAccount = "menuBarAccountID"
        static let menuBarText = "menuBarText"
    }

    static let notificationThresholds = [80, 95]

    init() {
        let defaults = UserDefaults.standard
        refreshMinutes = defaults.object(forKey: Keys.refreshMinutes) as? Int ?? 5
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        menuBarAccountID = defaults.string(forKey: Keys.menuBarAccount).flatMap(UUID.init(uuidString:))
        menuBarText = defaults.string(forKey: Keys.menuBarText).flatMap(MenuBarText.init(rawValue:)) ?? .session
        notified = defaults.dictionary(forKey: Keys.notified) as? [String: Int] ?? [:]

        if let data = defaults.data(forKey: Keys.accounts),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        }
        if let data = defaults.data(forKey: Keys.usage),
           let saved = try? JSONDecoder().decode([String: UsageSnapshot].self, from: data) {
            usage = Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        }

        if Self.canUseNotifications {
            UNUserNotificationCenter.current().delegate = notificationPresenter
            if notificationsEnabled { requestNotificationPermission() }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                await self?.refreshAll()
            }
        }

        startPolling()
        startClock()
    }

    var menuBarAccount: Account? {
        accounts.first { $0.id == menuBarAccountID } ?? accounts.first
    }

    var isRefreshing: Bool {
        status.values.contains(.loading)
    }

    var isLoginActive: Bool { loginPhase != .idle }

    // MARK: - Refresco

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                let minutes = self?.refreshMinutes ?? 5
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    /// Avanza `now` y, si alguna ventana se ha reiniciado desde la última consulta, vuelve a consultar esa cuenta.
    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.now = Date()
                for account in self.accounts {
                    guard let snapshot = self.usage[account.id] else { continue }
                    let crossedReset = snapshot.limits.contains { limit in
                        guard let resetsAt = limit.resetsAt else { return false }
                        return resetsAt > snapshot.fetchedAt && resetsAt.addingTimeInterval(10) < self.now
                    }
                    if crossedReset { await self.refresh(account.id) }
                }
            }
        }
    }

    func refreshAll(manual: Bool = false) async {
        now = Date()
        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { await self.refresh(account.id, manual: manual) }
            }
        }
    }

    func refresh(_ id: UUID, manual: Bool = false) async {
        guard let account = accounts.first(where: { $0.id == id }), !inFlight.contains(id) else { return }
        if !manual, let until = blockedUntil[id], until > Date() { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }

        status[id] = .loading
        do {
            let snapshot = try await withValidToken(id) { try await ClaudeAPI.fetchUsage(accessToken: $0) }
            guard accounts.contains(where: { $0.id == id }) else { return }
            usage[id] = snapshot
            status[id] = .idle
            blockedUntil[id] = nil
            saveUsage()
            notifyIfNeeded(account, snapshot)
        } catch ClaudeAPI.APIError.unauthorized, ClaudeAPI.APIError.tokenRejected {
            status[id] = .needsLogin
        } catch ClaudeAPI.APIError.rateLimited(let retryAfter) {
            blockedUntil[id] = Date().addingTimeInterval(max(retryAfter ?? 300, 60))
            status[id] = .error(ClaudeAPI.APIError.rateLimited(retryAfter: retryAfter).localizedDescription)
        } catch {
            status[id] = .error(error.localizedDescription)
        }
    }

    private func withValidToken<T>(_ id: UUID, _ operation: (String) async throws -> T) async throws -> T {
        guard var current = tokens[id] ?? Keychain.load(id) else { throw ClaudeAPI.APIError.unauthorized }
        tokens[id] = current
        if current.needsRefresh {
            current = try await refreshTokens(id, current)
        }
        do {
            return try await operation(current.accessToken)
        } catch ClaudeAPI.APIError.unauthorized {
            current = try await refreshTokens(id, current)
            return try await operation(current.accessToken)
        }
    }

    private func refreshTokens(_ id: UUID, _ old: OAuthTokens) async throws -> OAuthTokens {
        let response = try await ClaudeAPI.refresh(old.refreshToken)
        let renewed = OAuthTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token ?? old.refreshToken,
            expiresAt: response.expiresAt
        )
        tokens[id] = renewed
        try Keychain.save(renewed, for: id)
        return renewed
    }

    // MARK: - Inicio de sesión

    func beginLogin(manual: Bool = false) {
        Task { await startLogin(manual: manual) }
    }

    private func startLogin(manual: Bool) async {
        callbackServer.stop()
        lastAddedEmail = nil
        loginPhase = .preparing
        let pkce = ClaudeAPI.PKCE()
        let redirectURI: String
        if manual {
            redirectURI = ClaudeAPI.manualRedirectURI
        } else {
            do {
                let port = try await callbackServer.start { [weak self] components in
                    await self?.handleCallback(components)
                        ?? OAuthCallbackServer.Page(success: false, message: "La aplicación ya no está esperando.")
                }
                redirectURI = "http://localhost:\(port)/callback"
            } catch {
                loginPhase = .failed("No se pudo abrir el puerto local: \(error.localizedDescription)")
                return
            }
        }
        pendingLogin = PendingLogin(
            pkce: pkce,
            redirectURI: redirectURI,
            url: ClaudeAPI.authorizationURL(pkce: pkce, redirectURI: redirectURI),
            isManual: manual
        )
        loginPhase = .waiting
    }

    func openLoginInBrowser() {
        guard let url = pendingLogin?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func copyLoginURL() {
        guard let url = pendingLogin?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func cancelLogin() {
        callbackServer.stop()
        pendingLogin = nil
        loginPhase = .idle
    }

    func dismissAddedBanner() {
        lastAddedEmail = nil
    }

    private func handleCallback(_ components: URLComponents) async -> OAuthCallbackServer.Page {
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        guard let pending = pendingLogin, loginPhase == .waiting else {
            return .init(success: false, message: "Este enlace ya se usó o se canceló. Vuelve a empezar desde la app.")
        }
        if let error = query["error"] {
            let message = query["error_description"] ?? error
            loginPhase = .failed(message)
            return .init(success: false, message: message)
        }
        guard query["state"] == pending.pkce.state, let code = query["code"], !code.isEmpty else {
            return .init(success: false, message: "La respuesta no corresponde a este inicio de sesión.")
        }
        return await completeLogin(code: code, pending: pending)
    }

    /// En el flujo manual, la página de Claude muestra un texto `código#estado` que el usuario pega en la app.
    func submitManualCode(_ text: String) {
        guard let pending = pendingLogin else { return }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", maxSplits: 1).map(String.init)
        guard let code = parts.first, !code.isEmpty else { return }
        if parts.count > 1, parts[1] != pending.pkce.state {
            loginPhase = .failed("El código no corresponde a este inicio de sesión. Vuelve a generar el enlace.")
            return
        }
        Task { await completeLogin(code: code, pending: pending) }
    }

    @discardableResult
    private func completeLogin(code: String, pending: PendingLogin) async -> OAuthCallbackServer.Page {
        loginPhase = .exchanging
        do {
            let response = try await ClaudeAPI.exchangeCode(code, pkce: pending.pkce, redirectURI: pending.redirectURI)
            let newTokens = OAuthTokens(
                accessToken: response.access_token,
                refreshToken: response.refresh_token ?? "",
                expiresAt: response.expiresAt
            )
            let profile = try? await ClaudeAPI.fetchProfile(accessToken: newTokens.accessToken)
            guard let accountUUID = profile?.account.uuid ?? response.account?.uuid else {
                throw ClaudeAPI.APIError.http(0, "No se pudo identificar la cuenta.")
            }
            let email = profile?.email ?? response.account?.email_address ?? "Cuenta de Claude"

            let id: UUID
            if let index = accounts.firstIndex(where: { $0.accountUUID == accountUUID }) {
                id = accounts[index].id
                accounts[index].email = email
                accounts[index].displayName = profile?.account.display_name ?? accounts[index].displayName
                accounts[index].organizationName = profile?.organization?.name ?? accounts[index].organizationName
                accounts[index].plan = profile?.planName ?? accounts[index].plan
            } else {
                id = UUID()
                accounts.append(Account(
                    id: id,
                    accountUUID: accountUUID,
                    email: email,
                    displayName: profile?.account.display_name,
                    organizationName: profile?.organization?.name,
                    plan: profile?.planName
                ))
            }
            try Keychain.save(newTokens, for: id)
            tokens[id] = newTokens
            blockedUntil[id] = nil
            saveAccounts()

            callbackServer.stop()
            pendingLogin = nil
            loginPhase = .idle
            lastAddedEmail = email
            Task { await refresh(id, manual: true) }
            return .init(success: true, message: "\(email) ya aparece en Claude Session Monitor.")
        } catch {
            let message = error.localizedDescription
            loginPhase = .failed(message)
            return .init(success: false, message: message)
        }
    }

    // MARK: - Gestión de cuentas

    func rename(_ id: UUID, to name: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].customName = trimmed.isEmpty ? nil : trimmed
        saveAccounts()
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard accounts.indices.contains(target) else { return }
        accounts.swapAt(index, target)
        saveAccounts()
    }

    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        usage[id] = nil
        status[id] = nil
        tokens[id] = nil
        blockedUntil[id] = nil
        if menuBarAccountID == id { menuBarAccountID = nil }
        Keychain.delete(id)
        saveAccounts()
        saveUsage()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: Keys.accounts)
        }
    }

    private func saveUsage() {
        let byKey = Dictionary(uniqueKeysWithValues: usage.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(byKey) {
            defaults.set(data, forKey: Keys.usage)
        }
    }

    // MARK: - Avisos

    private static var canUseNotifications: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationPermission() {
        guard Self.canUseNotifications else { return }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    private func notifyIfNeeded(_ account: Account, _ snapshot: UsageSnapshot) {
        guard notificationsEnabled, Self.canUseNotifications else { return }
        for limit in snapshot.limits where limit.isPrimary {
            // La hora de reinicio identifica la ventana; se redondea porque la API la devuelve con ligeras variaciones.
            let window = Int(((limit.resetsAt?.timeIntervalSince1970 ?? 0) / 600).rounded())
            let key = "\(account.id.uuidString)|\(limit.kind)|\(window)"
            let reached = Self.notificationThresholds.last { limit.percent >= Double($0) } ?? 0
            guard reached > (notified[key] ?? 0) else { continue }
            notified[key] = reached

            let content = UNMutableNotificationContent()
            content.title = "\(account.title): \(limit.label) al \(Int(limit.percent.rounded())) %"
            content.body = Formatting.resetDescription(for: limit.resetsAt, now: Date()) ?? ""
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        }
        if notified.count > 200 {
            notified = Dictionary(uniqueKeysWithValues: notified.suffix(100).map { ($0.key, $0.value) })
        }
        defaults.set(notified, forKey: Keys.notified)
    }
}

/// Muestra los avisos aunque la app esté en primer plano (el panel de la barra de menús cuenta como primer plano).
nonisolated final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
