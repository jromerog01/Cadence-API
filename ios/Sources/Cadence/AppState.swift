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
    var uploadProgress: Double?
    var models: [ModelInfo] = []
    var importedAudio: URL?
    var liveProgress: [String: Double] = [:]
    @ObservationIgnored private var watchers: [String: Task<Void, Never>] = [:]

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
        do {
            jobs = try await client().request("api/jobs")
            startWatching()
        }
        catch { handle(error) }
    }

    func stopWatching() {
        for task in watchers.values { task.cancel() }
        watchers.removeAll()
    }

    private func startWatching() {
        let active = Set(jobs.filter { $0.status == "queued" || $0.status == "processing" }.map(\.id))
        for (id, task) in watchers where !active.contains(id) {
            task.cancel()
            watchers.removeValue(forKey: id)
            liveProgress.removeValue(forKey: id)
        }
        for id in active where watchers[id] == nil {
            watchers[id] = Task {
                do {
                    for try await event in try client().events("api/jobs/\(id)/events") {
                        if event.event == "progress" {
                            let payload = try APIJSON.decoder().decode(ProgressPayload.self, from: Data(event.data.utf8))
                            liveProgress[id] = payload.progress
                        } else if event.event == "done" || event.event == "error" {
                            watchers.removeValue(forKey: id)
                            await refresh()
                            return
                        }
                    }
                } catch { if !Task.isCancelled { handle(error) } }
                watchers.removeValue(forKey: id)
            }
        }
    }

    func loadModels() async {
        do { models = try await client().request("api/models") }
        catch { handle(error) }
    }

    func receiveAudio(_ source: URL) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "ImportedAudio/\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let destination = root.appending(path: source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            importedAudio = destination
        } catch { handle(error) }
    }

    func upload(file: URL, model: String, language: String?) async {
        uploadProgress = 0
        defer { uploadProgress = nil }
        do {
            let client = try client()
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 && size <= 500 * 1024 * 1024 else {
                throw APIError.server(413, "El archivo debe medir entre 1 byte y 500 MB")
            }
            let initBody = try APIJSON.encoder().encode(InitUploadRequest(
                filename: file.lastPathComponent, sizeBytes: size, model: model,
                language: language?.isEmpty == true ? nil : language
            ))
            let session: InitUploadResponse = try await client.request("api/uploads", method: "POST", body: initBody)
            let plan = try UploadPlan(sizeBytes: Int64(size), chunkSize: session.chunkSize)
            let status: UploadStatusResponse = try await client.request("api/uploads/\(session.uploadId)")
            let missing = plan.missingParts(received: status.received)
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            for part in missing {
                let range = try plan.range(for: part)
                try input.seek(toOffset: UInt64(range.lowerBound))
                let data = try input.read(upToCount: Int(range.count)) ?? Data()
                guard data.count == range.count else { throw APIError.server(0, "No se pudo leer el audio completo") }
                let piece = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                try data.write(to: piece, options: .atomic)
                defer { try? FileManager.default.removeItem(at: piece) }
                try await client.uploadPart("api/uploads/\(session.uploadId)/parts/\(part)", fileURL: piece)
                uploadProgress = Double(range.upperBound) / Double(size)
            }
            let _: Job = try await client.request("api/uploads/\(session.uploadId)/complete", method: "POST")
            await refresh()
        } catch { handle(error) }
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
        stopWatching()
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

private struct InitUploadRequest: Encodable {
    let filename: String
    let sizeBytes: Int
    let model: String
    let language: String?
}

private struct ProgressPayload: Decodable {
    let progress: Double
}
