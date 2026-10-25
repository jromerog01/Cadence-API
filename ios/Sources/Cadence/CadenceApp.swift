import SwiftUI

@main
struct CadenceApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ServerRefreshWatcher.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                let active = UserDefaults.standard.stringArray(forKey: "activeServerJobIDs") ?? []
                ServerRefreshWatcher.shared.scheduleNext(hasActiveJobs: !active.isEmpty)
            }
        }
    }
}
