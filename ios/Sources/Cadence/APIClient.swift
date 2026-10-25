import CadenceKit
import Foundation

struct TokenResponse: Decodable {
    let token: String
    let user: CadenceKit.User
}

enum APIError: LocalizedError {
    case invalidServer, unauthorized
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidServer: "Usa una URL HTTPS válida (o HTTP en la red local)."
        case .unauthorized: "La sesión caducó. Inicia sesión de nuevo."
        case let .server(code, message): "Error \(code): \(message)"
        }
    }
}

struct APIClient: Sendable {
    let baseURL: URL
    let token: String?

    init(server: String, token: String? = nil) throws {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty,
              scheme == "https" || (scheme == "http" && (host == "localhost" || host.hasSuffix(".local") || host.hasPrefix("192.168.") || host.hasPrefix("10."))) else {
            throw APIError.invalidServer
        }
        baseURL = url
        self.token = token
    }

    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.server(0, "Respuesta inválida") }
        if response.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.server(response.statusCode, String(data: data, encoding: .utf8) ?? "Error del servidor")
        }
        return try APIJSON.decoder().decode(T.self, from: data)
    }

    func delete(_ path: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "DELETE"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.server(0, "Respuesta inválida") }
        if response.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw APIError.server(response.statusCode, "No se pudo borrar") }
    }
}
