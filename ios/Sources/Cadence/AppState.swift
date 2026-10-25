import CadenceKit
import Foundation
import Observation

@MainActor @Observable final class AppState {
    var server = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    var token = SessionStore.load()
    var user: CadenceKit.User?
    var jobs: [Job] = []
    var isBusy = false
    var errorMessage: String?

    func restore() async {
        guard token != nil else { return }
        do {
            user = try await client().request("api/auth/me")
            await refresh()
        } catch { handle(error) }
    }

    func login(email: String, password: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try APIClient(server: server)
            let health: Health = try await client.request("api/health")
            guard health.status == "ok" else { throw APIError.server(503, "El servidor no está listo") }
            let body = try JSONEncoder().encode(Credentials(email: email, password: password))
            let response: TokenResponse = try await client.request("api/auth/token", method: "POST", body: body)
            try SessionStore.save(response.token)
            token = response.token
            user = response.user
            UserDefaults.standard.set(server, forKey: "serverURL")
            await refresh()
        } catch { handle(error) }
    }

    func refresh() async {
        do { jobs = try await client().request("api/jobs") }
        catch { handle(error) }
    }

    func job(_ id: String) async throws -> Job {
        try await client().request("api/jobs/\(id)")
    }

    func delete(_ id: String) async {
        do {
            try await client().delete("api/jobs/\(id)")
            jobs.removeAll { $0.id == id }
        } catch { handle(error) }
    }

    func logout() {
        SessionStore.clear()
        token = nil
        user = nil
        jobs = []
    }

    private func client() throws -> APIClient { try APIClient(server: server, token: token) }

    private func handle(_ error: Error) {
        if case APIError.unauthorized = error { logout() }
        errorMessage = error.localizedDescription
    }
}

private struct Credentials: Encodable {
    let email: String
    let password: String
}

private struct Health: Decodable {
    let status: String
}
