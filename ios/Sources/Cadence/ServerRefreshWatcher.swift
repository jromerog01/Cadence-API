import BackgroundTasks
import CadenceKit
import Foundation
import UserNotifications

@MainActor final class ServerRefreshWatcher {
    static let shared = ServerRefreshWatcher()
    static let refreshIdentifier = "com.jesusrg.cadence.refresh"

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await self.handle(task: refreshTask)
            }
        }
    }

    func scheduleNext(hasActiveJobs: Bool) {
        guard hasActiveJobs else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Ignorar errores de submission si el sistema limita refrescos
        }
    }

    private func handle(task: BGAppRefreshTask) async {
        scheduleNext(hasActiveJobs: true)

        let checkTask = Task { @MainActor () -> Bool in
            guard let token = SessionStore.load(),
                  let server = UserDefaults.standard.string(forKey: "serverURL"),
                  !server.isEmpty else { return false }

            do {
                let client = try APIClient(server: server, token: token)
                let jobs: [Job] = try await client.request("api/jobs")

                let previouslyActive = UserDefaults.standard.stringArray(forKey: "activeServerJobIDs") ?? []
                var currentlyActive: [String] = []

                for job in jobs {
                    if job.status == "queued" || job.status == "processing" {
                        currentlyActive.append(job.id)
                    } else if previouslyActive.contains(job.id) {
                        let content = UNMutableNotificationContent()
                        if job.status == "done" {
                            content.title = "Transcripción lista"
                            content.body = job.originalFilename
                        } else if job.status == "error" {
                            content.title = "Error en transcripción"
                            content.body = job.originalFilename
                        }
                        content.userInfo = ["job_id": job.id]
                        try? await UNUserNotificationCenter.current().add(
                            UNNotificationRequest(identifier: "server-\(job.id)", content: content, trigger: nil)
                        )
                    }
                }

                UserDefaults.standard.set(currentlyActive, forKey: "activeServerJobIDs")
                return true
            } catch {
                return false
            }
        }

        task.expirationHandler = {
            checkTask.cancel()
        }

        let success = await checkTask.value
        task.setTaskCompleted(success: success)
    }
}
