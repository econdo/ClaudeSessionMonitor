import CryptoKit
import Foundation
import Security

/// Cliente de los endpoints OAuth de Claude que usa Claude Code para `/usage`.
enum ClaudeAPI {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = "https://claude.com/cai/oauth/authorize"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let manualRedirectURI = "https://platform.claude.com/oauth/code/callback"
    static let scopes = "user:profile user:inference"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    static let userAgent = "ClaudeSessionMonitor/1.0"

    enum APIError: LocalizedError {
        case unauthorized
        case tokenRejected(String)
        case rateLimited(retryAfter: TimeInterval?)
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "La sesión ha caducado."
            case .tokenRejected(let message): "Claude rechazó la autorización: \(message)"
            case .rateLimited: "Demasiadas consultas; se reintentará en unos minutos."
            case .http(let code, let message): "Error \(code): \(message)"
            }
        }
    }

    // MARK: - OAuth

    struct PKCE {
        let verifier: String
        let challenge: String
        let state: String

        init() {
            verifier = Self.randomURLSafeString()
            challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
            state = Self.randomURLSafeString()
        }

        private static func randomURLSafeString() -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            return Data(bytes).base64URLEncoded()
        }
    }

    static func authorizationURL(pkce: PKCE, redirectURI: String) -> URL {
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return components.url!
    }

    struct TokenResponse: Decodable {
        struct TokenAccount: Decodable {
            let uuid: String?
            let email_address: String?
        }

        let access_token: String
        let refresh_token: String?
        let expires_in: Double?
        let account: TokenAccount?

        var expiresAt: Date { Date().addingTimeInterval(expires_in ?? 3600) }
    }

    static func exchangeCode(_ code: String, pkce: PKCE, redirectURI: String) async throws -> TokenResponse {
        try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": pkce.verifier,
            "state": pkce.state,
        ])
    }

    static func refresh(_ refreshToken: String) async throws -> TokenResponse {
        try await postToken([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": scopes,
        ])
    }

    private static func postToken(_ body: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: tokenURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        case 400, 401, 403:
            throw APIError.tokenRejected(errorMessage(from: data))
        case 429:
            throw APIError.rateLimited(retryAfter: retryAfter(response))
        default:
            throw APIError.http(status, errorMessage(from: data))
        }
    }

    // MARK: - Perfil y uso

    struct Profile: Decodable {
        struct ProfileAccount: Decodable {
            let uuid: String
            let email: String?
            let email_address: String?
            let display_name: String?
        }

        struct ProfileOrganization: Decodable {
            let name: String?
            let organization_type: String?
            let rate_limit_tier: String?
        }

        let account: ProfileAccount
        let organization: ProfileOrganization?

        var email: String? { account.email ?? account.email_address }

        var planName: String? {
            let tier = organization?.rate_limit_tier ?? ""
            let type = organization?.organization_type ?? ""
            if tier.contains("max_20x") { return "Max 20x" }
            if tier.contains("max_5x") { return "Max 5x" }
            if type.contains("max") { return "Max" }
            if type.contains("pro") { return "Pro" }
            if type.contains("team") { return "Team" }
            if type.contains("enterprise") { return "Enterprise" }
            return type.isEmpty ? nil : type.capitalized
        }
    }

    static func fetchProfile(accessToken: String) async throws -> Profile {
        try JSONDecoder().decode(Profile.self, from: try await get(profileURL, accessToken: accessToken))
    }

    static func fetchUsage(accessToken: String) async throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(UsageResponse.self, from: try await get(usageURL, accessToken: accessToken))
        return UsageSnapshot(limits: response.normalizedLimits(), fetchedAt: Date())
    }

    private static func get(_ url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401: throw APIError.unauthorized
        case 429: throw APIError.rateLimited(retryAfter: retryAfter(response))
        default: throw APIError.http(status, errorMessage(from: data))
        }
    }

    private static func retryAfter(_ response: URLResponse) -> TimeInterval? {
        ((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
    }

    private static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
            if let description = json["error_description"] as? String { return description }
            if let error = json["error"] as? String { return error }
        }
        return String(data: data.prefix(200), encoding: .utf8) ?? "respuesta no válida"
    }
}

// MARK: - Respuesta de /api/oauth/usage

private struct UsageResponse: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }

    /// `display_name` de un modelo o superficie; tolera que venga como objeto o como texto.
    struct Named: Decodable {
        let display_name: String?

        init(from decoder: Decoder) throws {
            enum Keys: String, CodingKey { case display_name, id }
            if let container = try? decoder.container(keyedBy: Keys.self) {
                display_name = (try? container.decode(String.self, forKey: .display_name))
                    ?? (try? container.decode(String.self, forKey: .id))
            } else {
                display_name = try? decoder.singleValueContainer().decode(String.self)
            }
        }
    }

    struct Scope: Decodable {
        let model: Named?
        let surface: Named?
    }

    struct Limit: Decodable {
        let kind: String
        let percent: Double?
        let resets_at: String?
        let scope: Scope?
    }

    /// Un elemento que no se puede decodificar se descarta en lugar de romper toda la respuesta.
    struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    let five_hour: Window?
    let seven_day: Window?
    let seven_day_opus: Window?
    let seven_day_sonnet: Window?
    let limits: [Lossy<Limit>]?

    func normalizedLimits() -> [UsageLimit] {
        let limits = (limits ?? []).compactMap(\.value)
        if !limits.isEmpty {
            return limits.enumerated().map { index, limit in
                let scopeName = limit.scope?.model?.display_name ?? limit.scope?.surface?.display_name
                return UsageLimit(
                    id: "\(index)|\(limit.kind)|\(scopeName ?? "")",
                    kind: limit.kind,
                    label: Self.label(kind: limit.kind, scopeName: scopeName),
                    percent: limit.percent ?? 0,
                    resetsAt: Self.parseDate(limit.resets_at)
                )
            }
        }

        // Formato anterior, sin la lista `limits`.
        let windows: [(String, String?, Window?)] = [
            ("session", nil, five_hour),
            ("weekly_all", nil, seven_day),
            ("weekly_scoped", "Opus", seven_day_opus),
            ("weekly_scoped", "Sonnet", seven_day_sonnet),
        ]
        return windows.compactMap { kind, scopeName, window in
            guard let window, let utilization = window.utilization else { return nil }
            return UsageLimit(
                id: "\(kind)|\(scopeName ?? "")",
                kind: kind,
                label: Self.label(kind: kind, scopeName: scopeName),
                percent: utilization,
                resetsAt: Self.parseDate(window.resets_at)
            )
        }
    }

    private static func label(kind: String, scopeName: String?) -> String {
        switch kind {
        case "session": "Sesión actual"
        case "weekly_all": "Semana actual (todos los modelos)"
        case "weekly_scoped": "Semana actual (\(scopeName ?? "específico"))"
        default: scopeName.map { "\(kind) (\($0))" } ?? kind
        }
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
