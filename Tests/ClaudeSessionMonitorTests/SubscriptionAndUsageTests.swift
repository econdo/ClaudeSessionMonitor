import Foundation
import Testing
@testable import ClaudeSessionMonitor

/// Los JSON imitan las respuestas reales de `/api/oauth/profile` y `/api/oauth/usage`, sin datos personales.
struct SubscriptionTests {
    private func profile(max: Bool? = nil, pro: Bool? = nil, organization: String) throws -> ClaudeAPI.Profile {
        let flags = [max.map { "\"has_claude_max\": \($0)," }, pro.map { "\"has_claude_pro\": \($0)," }]
            .compactMap { $0 }.joined()
        let json = "{\"account\": {\(flags) \"uuid\": \"u\"}, \"organization\": \(organization)}"
        return try JSONDecoder().decode(ClaudeAPI.Profile.self, from: Data(json.utf8))
    }

    @Test func planUltraActivo() throws {
        let ultra = try profile(max: true, pro: false, organization: """
            {"organization_type": "claude_max", "rate_limit_tier": "default_claude_max_20x",
             "plan_display_name": "Ultra", "subscription_status": "active"}
            """)
        #expect(ultra.planName == "Ultra")
        #expect(ultra.hasSubscriptionInForce == true)
    }

    @Test func sinNombreDePlanSeDeduceDelNivel() throws {
        let max = try profile(max: true, organization: #"{"organization_type": "claude_max", "rate_limit_tier": "default_claude_max_5x"}"#)
        #expect(max.planName == "Max 5x")
    }

    @Test func maxConservaElNivelEnElNombre() throws {
        let plain = try profile(max: true, organization: #"{"plan_display_name": "Max", "rate_limit_tier": "default_claude_max_20x"}"#)
        #expect(plain.planName == "Max 20x")
        let explicit = try profile(max: true, organization: #"{"plan_display_name": "Max 5x", "rate_limit_tier": "default_claude_max_5x"}"#)
        #expect(explicit.planName == "Max 5x")
    }

    @Test func canceladaPeroPagadaHastaFinDePeriodoSigueVigente() throws {
        let cancelled = try profile(max: true, organization: #"{"subscription_status": "canceled"}"#)
        #expect(cancelled.hasSubscriptionInForce == true)
    }

    @Test(arguments: ["canceled", "cancelled", "expired", "unpaid", "CANCELED"])
    func estadoTerminalSinPlanEsFinDeSuscripcion(status: String) throws {
        let ended = try profile(max: false, pro: false, organization: "{\"subscription_status\": \"\(status)\"}")
        #expect(ended.hasSubscriptionInForce == false)
    }

    @Test func sinEstadoNiPlanEsFinDeSuscripcion() throws {
        let free = try profile(max: false, pro: false, organization: #"{"organization_type": "claude_free", "subscription_status": null}"#)
        #expect(free.hasSubscriptionInForce == false)
    }

    @Test(arguments: ["active", "trialing", "past_due", "un_estado_nuevo"])
    func unEstadoNoTerminalNuncaDesactiva(status: String) throws {
        let current = try profile(max: false, pro: false, organization: "{\"subscription_status\": \"\(status)\"}")
        #expect(current.hasSubscriptionInForce == true)
    }

    @Test(arguments: ["claude_team", "claude_enterprise"])
    func equipoYEmpresaSinEstadoSiguenVigentes(type: String) throws {
        let organization = try profile(organization: "{\"organization_type\": \"\(type)\"}")
        #expect(organization.hasSubscriptionInForce == true)
    }

    @Test func sinOrganizacionNoSePuedeSaber() throws {
        let unknown = try profile(organization: "null")
        #expect(unknown.hasSubscriptionInForce == nil)
    }

    @Test func cuentasGuardadasAntesDeEstaVersionSiguenFuncionando() throws {
        let saved = #"{"id": "6F1D4C0A-0000-4000-8000-000000000001", "accountUUID": "a", "email": "a@example.com"}"#
        let account = try JSONDecoder().decode(Account.self, from: Data(saved.utf8))
        #expect(account.isDisabled == false)
    }

    @Test func desactivadaPorSuscripcionOAMano() {
        var account = Account(id: UUID(), accountUUID: "a", email: "a@example.com")
        account.subscriptionEnded = true
        #expect(account.isDisabled)
        account.subscriptionEnded = false
        #expect(!account.isDisabled)
        account.manuallyDisabled = true
        #expect(account.isDisabled)
    }
}

struct UsageTests {
    private func kinds(_ json: String) throws -> [String] {
        try ClaudeAPI.parseUsage(Data(json.utf8)).limits.map(\.kind)
    }

    private let weekly = #"{"kind": "weekly_all", "percent": 2, "resets_at": "2026-11-07T09:00:00.739783+00:00"}"#

    @Test func ultraSinSesion() throws {
        let snapshot = try ClaudeAPI.parseUsage(Data("{\"five_hour\": null, \"limits\": [\(weekly)]}".utf8))
        #expect(snapshot.session == nil)
        #expect(snapshot.weekly?.percent == 2)
    }

    private let residual = #"{"kind": "session", "percent": 0, "resets_at": null}"#

    private func kindsShown(_ limits: String, plan: String?) throws -> [String] {
        try ClaudeAPI.parseUsage(Data("{\"limits\": [\(limits), \(weekly)]}".utf8))
            .displayed(forPlan: plan).limits.map(\.kind)
    }

    @Test(arguments: ["Ultra", "ultra", "Plan Ultra"])
    func enUltraSeOcultaLaSesionResidual(plan: String) throws {
        #expect(try kindsShown(residual, plan: plan) == ["weekly_all"])
    }

    @Test(arguments: ["Max", "Max 5x", "Max 20x", "Pro", "Team"])
    func enLosDemasPlanesLaSesionSeMuestraAunqueNoHayaNingunaEnCurso(plan: String) throws {
        #expect(try kindsShown(residual, plan: plan) == ["session", "weekly_all"])
    }

    @Test func sinPlanConocidoLaSesionSeMuestra() throws {
        #expect(try kindsShown(residual, plan: nil) == ["session", "weekly_all"])
    }

    @Test(arguments: ["Ultra", "Max 20x"])
    func unaSesionRealSiempreSeMuestra(plan: String) throws {
        let inProgress = #"{"kind": "session", "percent": 15, "resets_at": "2026-11-02T10:09:59.610764+00:00"}"#
        #expect(try kindsShown(inProgress, plan: plan) == ["session", "weekly_all"])
        let justStarted = #"{"kind": "session", "percent": 0, "resets_at": "2026-11-02T10:09:59+00:00"}"#
        #expect(try kindsShown(justStarted, plan: plan) == ["session", "weekly_all"])
    }

    @Test func formatoAnteriorSinLista() throws {
        let window = #"{"utilization": 53, "resets_at": "2026-11-07T09:00:00+00:00"}"#
        #expect(try kinds("{\"five_hour\": null, \"seven_day\": \(window)}") == ["weekly_all"])
        #expect(try kinds("{\"five_hour\": {\"utilization\": 15, \"resets_at\": \"2026-11-02T10:00:00+00:00\"}, \"seven_day\": \(window)}") == ["session", "weekly_all"])
    }
}
