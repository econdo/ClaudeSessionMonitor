import Foundation

/// Tokens OAuth de una cuenta. Se guardan en el llavero, nunca en UserDefaults.
struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    /// Renovamos con 5 minutos de margen para no usar un token a punto de caducar.
    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 300 }
}

struct Account: Codable, Identifiable, Hashable {
    let id: UUID
    var accountUUID: String
    var email: String
    var displayName: String?
    var organizationName: String?
    var plan: String?
    var customName: String?

    var title: String {
        if let customName, !customName.isEmpty { return customName }
        return email
    }

    var subtitle: String {
        let hasCustomName = !(customName ?? "").isEmpty
        return [hasCustomName ? email : nil, plan].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Un límite de uso tal y como lo devuelve `/api/oauth/usage` (sesión de 5 h, semanal, semanal por modelo…).
struct UsageLimit: Codable, Identifiable, Hashable {
    var id: String
    var kind: String
    var label: String
    var percent: Double
    var resetsAt: Date?

    var isPrimary: Bool { kind == "session" || kind == "weekly_all" }

    /// Si la hora de reinicio ya pasó, el uso real es 0 aunque aún no hayamos vuelto a consultar.
    func effectivePercent(at now: Date) -> Double {
        if let resetsAt, resetsAt <= now { return 0 }
        return percent
    }
}

struct UsageSnapshot: Codable {
    var limits: [UsageLimit]
    var fetchedAt: Date

    var session: UsageLimit? { limits.first { $0.kind == "session" } }
    var weekly: UsageLimit? { limits.first { $0.kind == "weekly_all" } }
}

enum AccountStatus: Equatable {
    case idle
    case loading
    case needsLogin
    case error(String)
}

enum MenuBarText: String, CaseIterable, Identifiable {
    case session
    case weekly
    case sessionAndWeekly
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: "Sesión actual"
        case .weekly: "Semanal"
        case .sessionAndWeekly: "Sesión y semanal"
        case .none: "Solo icono"
        }
    }
}
