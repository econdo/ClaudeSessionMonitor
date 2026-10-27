import Foundation
import Network

/// Servidor HTTP mínimo, solo en loopback, que recibe la redirección OAuth (`/callback?code=…&state=…`).
/// Escucha en IPv4 e IPv6 en el mismo puerto porque el navegador puede resolver `localhost` a cualquiera de los dos.
final class OAuthCallbackServer {
    struct Page {
        let success: Bool
        let message: String
    }

    private var listeners: [NWListener] = []
    private var onCallback: ((URLComponents) async -> Page)?

    func start(onCallback: @escaping (URLComponents) async -> Page) async throws -> UInt16 {
        stop()
        self.onCallback = onCallback
        let port = try await startListener(host: .ipv4(.loopback), port: .any)
        if let fixedPort = NWEndpoint.Port(rawValue: port) {
            _ = try? await startListener(host: .ipv6(.loopback), port: fixedPort)
        }
        return port
    }

    func stop() {
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
        onCallback = nil
    }

    private func startListener(host: NWEndpoint.Host, port: NWEndpoint.Port) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
        // Sin esto, IPv4 e IPv6 no pueden compartir el puerto (EADDRINUSE).
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.handle(connection) }
        }
        listeners.append(listener)

        let resumed = ResumeFlag()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                MainActor.assumeIsolated {
                    guard !resumed.value else { return }
                    switch state {
                    case .ready:
                        resumed.value = true
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    case .failed(let error):
                        resumed.value = true
                        continuation.resume(throwing: error)
                    case .cancelled:
                        resumed.value = true
                        continuation.resume(throwing: CancellationError())
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .main)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let target = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first ?? "/"
                guard let self, let onCallback = self.onCallback,
                      let components = URLComponents(string: "http://localhost\(target)"),
                      components.path == "/callback"
                else {
                    Self.respond(connection, status: "404 Not Found", html: "")
                    return
                }
                Task {
                    let page = await onCallback(components)
                    Self.respond(connection, status: "200 OK", html: Self.html(for: page))
                }
            }
        }
    }

    private static func respond(_ connection: NWConnection, status: String, html: String) {
        let body = Data(html.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func html(for page: Page) -> String {
        let title = page.success ? "Cuenta añadida" : "No se pudo añadir la cuenta"
        let symbol = page.success ? "✓" : "✕"
        let color = page.success ? "#2e9d5b" : "#c0392b"
        let message = page.message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html><html lang="es"><head><meta charset="utf-8"><title>\(title)</title>
        <style>body{font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:100vh;margin:0;background:#f5f4ef;color:#222}
        @media(prefers-color-scheme:dark){body{background:#1e1e1c;color:#eee}}
        .c{text-align:center;max-width:420px;padding:24px}.s{font-size:48px;color:\(color)}</style></head>
        <body><div class="c"><div class="s">\(symbol)</div><h2>\(title)</h2><p>\(message)</p>
        <p style="opacity:.6">Ya puedes cerrar esta pestaña.</p></div></body></html>
        """
    }
}

private final class ResumeFlag {
    var value = false
}
