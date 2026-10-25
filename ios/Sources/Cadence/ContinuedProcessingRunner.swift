import BackgroundTasks
import Foundation

@MainActor final class ContinuedProcessingRunner {
    private var task: BGContinuedProcessingTask?
    private var worker: Task<Void, Never>?
    private(set) var isScheduled = false

    func start(title: String, operation: @escaping @MainActor @Sendable () async -> Bool) throws {
        guard !isScheduled else { return }
        let identifier = "com.jesusrg.cadence.transcribe." + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            guard let self, let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.task = continued
            continued.progress.totalUnitCount = 1000
            let worker = Task { @MainActor in
                let success = await operation()
                continued.setTaskCompleted(success: success)
                self.task = nil
                self.worker = nil
                self.isScheduled = false
            }
            self.worker = worker
            continued.expirationHandler = { [weak self] in
                worker.cancel()
                continued.setTaskCompleted(success: false)
                Task { @MainActor [weak self] in
                    self?.task = nil
                    self?.worker = nil
                    self?.isScheduled = false
                }
            }
        }
        guard registered else { throw APIError.server(0, "No se pudo registrar la tarea en segundo plano") }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title,
                                                       subtitle: "Transcripción en este iPhone")
        request.strategy = .fail
        try BGTaskScheduler.shared.submit(request)
        isScheduled = true
    }

    func update(_ fraction: Double) {
        task?.progress.completedUnitCount = Int64(min(max(fraction, 0), 1) * 1000)
    }
}
