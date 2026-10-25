import CadenceKit
import Foundation
import Observation
import CryptoKit
import Speech
import UserNotifications

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
    var pendingInboxItem: InboxItem?
    var localOnly = UserDefaults.standard.bool(forKey: "localOnly")
    var localRecords: [String: StoredJob] = [:]
    var activeLocalID: String?
    var localEngineAvailable: Bool { SpeechTranscriber.isAvailable }
    @ObservationIgnored private let localStore = FileJobStore(root:
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "DeviceJobs"))
    @ObservationIgnored private var serverCache: FileJobStore?
    @ObservationIgnored private let continuedRunner = ContinuedProcessingRunner()
    var liveProgress: [String: Double] = [:]
    @ObservationIgnored private var watchers: [String: Task<Void, Never>] = [:]

    func restore() async {
        await loadLocalJobs()
        if localOnly { jobs = localRecords.values.map(\.job); return }
        guard token != nil else { return }
        if let data = UserDefaults.standard.data(forKey: "sessionUser"),
           let saved = try? APIJSON.decoder().decode(CadenceKit.User.self, from: data) {
            user = saved
            configureCache()
            if let cached = try? await serverCache?.all() {
                jobs = cached.map(\.job) + localRecords.values.map(\.job)
            }
        }
        do {
            user = try await client().request("api/auth/me")
            configureCache()
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
            UserDefaults.standard.set(try APIJSON.encoder().encode(response.user), forKey: "sessionUser")
            localOnly = false
            UserDefaults.standard.set(false, forKey: "localOnly")
            configureCache()
            UserDefaults.standard.set(server, forKey: "serverURL")
            await refresh()
        } catch { handle(error) }
    }

    func refresh() async {
        await loadLocalJobs()
        if localOnly { jobs = localRecords.values.map(\.job).sorted { $0.createdAt > $1.createdAt }; return }
        do {
            let remote: [Job] = try await client().request("api/jobs")
            if let serverCache {
                for var job in remote {
                    if job.segments.isEmpty, let saved = try await serverCache.load(job.id) {
                        job.segments = saved.job.segments
                    }
                    try await serverCache.save(StoredJob(job: job, origin: .server))
                }
            }
            jobs = (remote + localRecords.values.map(\.job)).sorted { $0.createdAt > $1.createdAt }
            startWatching()
        }
        catch {
            if let serverCache, let cached = try? await serverCache.all(), !cached.isEmpty {
                jobs = (cached.map(\.job) + localRecords.values.map(\.job)).sorted { $0.createdAt > $1.createdAt }
            }
            handle(error)
        }
    }

    private func configureCache() {
        guard let user else { return }
        let scope = SHA256.hash(data: Data((server + "|" + user.id).utf8)).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        serverCache = FileJobStore(root: root.appending(path: "ServerCache/\(scope)"))
    }

    private func loadLocalJobs() async {
        do {
            var records = try await localStore.all()
            for index in records.indices where records[index].job.status == "processing" && activeLocalID != records[index].job.id {
                records[index].job.status = "paused"
                try await localStore.save(records[index])
            }
            localRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.job.id, $0) })
        }
        catch { handle(error) }
    }

    func useLocalMode() async {
        localOnly = true
        UserDefaults.standard.set(true, forKey: "localOnly")
        stopWatching()
        await refresh()
    }

    func downloadLocalModel(language: String) async {
        isBusy = true
        defer { isBusy = false }
        do { try await AppleSpeechEngine.downloadModel(language: language) }
        catch { handle(error) }
    }

    func startLocal(file: URL, filename: String, language: String, resumeID: String? = nil) async {
        guard activeLocalID == nil, !continuedRunner.isScheduled else { return }
        let id = resumeID ?? UUID().uuidString
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            try continuedRunner.start(title: "Transcribiendo \(filename)") { [self] in
                await transcribeLocally(file: file, filename: filename, language: language, resumeID: id)
                return localRecords[id]?.job.status == "done"
            }
        } catch {
            await transcribeLocally(file: file, filename: filename, language: language, resumeID: id)
        }
    }

    private func transcribeLocally(file: URL, filename: String, language: String, resumeID: String? = nil) async {
        guard activeLocalID == nil else { return }
        var audio = file
        if resumeID == nil, let item = pendingInboxItem,
           let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.jesusrg.cadence") {
            do {
                let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appending(path: "ImportedAudio/\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                audio = folder.appending(path: filename)
                try FileManager.default.copyItem(at: file, to: audio)
                try Inbox(root: group.appending(path: "Inbox")).remove(item)
                pendingInboxItem = nil
            } catch { handle(error); return }
        }
        var record = resumeID.flatMap { localRecords[$0] } ?? StoredJob(
            job: Job(id: resumeID ?? UUID().uuidString, originalFilename: filename, model: "apple-speech", language: language),
            origin: .device, audioPath: audio.path)
        activeLocalID = record.job.id
        defer { activeLocalID = nil }
        record.job.status = "processing"
        record.job.errorMessage = nil
        do {
            try await localStore.save(record)
            localRecords[record.job.id] = record
            jobs.removeAll { $0.id == record.job.id }
            jobs.insert(record.job, at: 0)
            let request = TranscriptionRequest(fileURL: audio, language: language, jobID: record.job.id,
                                               resumeSeconds: record.resumeSeconds, existingSegments: record.job.segments)
            for try await event in AppleSpeechEngine().transcribe(request) {
                switch event {
                case let .progress(fraction, _):
                    continuedRunner.update(fraction)
                    record.job.progress = fraction
                    liveProgress[record.job.id] = fraction
                case let .segments(segments):
                    record.job.segments += segments
                    record.resumeSeconds = segments.last?.endSeconds ?? record.resumeSeconds
                    try await localStore.save(record)
                case .finished(var job):
                    job.originalFilename = record.job.originalFilename
                    job.createdAt = record.job.createdAt
                    record.job = job
                    try await localStore.save(record)
                    let content = UNMutableNotificationContent()
                    content.title = "Transcripción lista"
                    content.body = job.originalFilename
                    content.userInfo = ["job_id": job.id]
                    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: job.id, content: content, trigger: nil))
                }
                localRecords[record.job.id] = record
                if let index = jobs.firstIndex(where: { $0.id == record.job.id }) { jobs[index] = record.job }
            }
        } catch {
            record.job.status = "paused"
            record.job.errorMessage = error.localizedDescription
            try? await localStore.save(record)
            localRecords[record.job.id] = record
            handle(error)
        }
        await refresh()
    }

    func resumeLocal(_ id: String) async {
        guard let record = localRecords[id], let audio = record.audioPath else { return }
        await startLocal(file: URL(fileURLWithPath: audio), filename: record.job.originalFilename,
                                language: record.job.language ?? "es", resumeID: id)
    }

    func stopWatching() {
        for task in watchers.values { task.cancel() }
        watchers.removeAll()
    }

    private func startWatching() {
        let active = Set(jobs.filter { localRecords[$0.id] == nil && ($0.status == "queued" || $0.status == "processing") }.map(\.id))
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

    func checkInbox() {
        guard importedAudio == nil,
              let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.jesusrg.cadence") else { return }
        do {
            let inbox = Inbox(root: group.appending(path: "Inbox"))
            if let item = try inbox.pending().first {
                pendingInboxItem = item
                importedAudio = item.fileURL(in: inbox.root)
            }
        } catch { handle(error) }
    }

    func upload(file: URL, filename: String? = nil, model: String, language: String?) async {
        uploadProgress = 0
        defer { uploadProgress = nil }
        do {
            let client = try client()
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 && size <= 500 * 1024 * 1024 else {
                throw APIError.server(413, "El archivo debe medir entre 1 byte y 500 MB")
            }
            let initBody = try APIJSON.encoder().encode(InitUploadRequest(
                filename: filename ?? file.lastPathComponent, sizeBytes: size, model: model,
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
            if let item = pendingInboxItem,
               let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.jesusrg.cadence") {
                try Inbox(root: group.appending(path: "Inbox")).remove(item)
                pendingInboxItem = nil
            }
            await refresh()
        } catch { handle(error) }
    }

    func job(_ id: String) async throws -> Job {
        if let local = localRecords[id] { return local.job }
        do {
            let job: Job = try await client().request("api/jobs/\(id)")
            try await serverCache?.save(StoredJob(job: job, origin: .server))
            return job
        } catch {
            if case APIError.unauthorized = error { handle(error); throw error }
            if let saved = try await serverCache?.load(id) { return saved.job }
            throw error
        }
    }

    func export(jobID: String, format: String) async throws -> URL {
        if let record = localRecords[jobID] { return try localExport(record.job, format: format) }
        do { return try await client().export(jobID: jobID, format: format) }
        catch {
            if case APIError.unauthorized = error { handle(error); throw error }
            if let saved = try await serverCache?.load(jobID), saved.job.status == "done" {
                return try localExport(saved.job, format: format)
            }
            throw error
        }
    }

    private func localExport(_ job: Job, format: String) throws -> URL {
        let data = format == "pdf" ? LocalPDFExporter.render(job) : Data(try TextExporter.render(job, format: format).utf8)
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = URL(fileURLWithPath: job.originalFilename).deletingPathExtension().lastPathComponent
        let file = folder.appending(path: "\(name).\(format)")
        try data.write(to: file, options: .atomic)
        return file
    }

    func delete(_ id: String) async {
        do {
            if let record = localRecords[id] {
                guard activeLocalID != id else { return }
                if let audio = record.audioPath { try? FileManager.default.removeItem(atPath: audio) }
                try await localStore.delete(id)
                localRecords.removeValue(forKey: id)
            } else {
                try await client().delete("api/jobs/\(id)")
                try await serverCache?.delete(id)
            }
            jobs.removeAll { $0.id == id }
        } catch { handle(error) }
    }

    func logout() {
        stopWatching()
        SessionStore.clear()
        token = nil
        user = nil
        jobs = []
        serverCache = nil
        localOnly = false
        UserDefaults.standard.set(false, forKey: "localOnly")
        UserDefaults.standard.removeObject(forKey: "sessionUser")
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
