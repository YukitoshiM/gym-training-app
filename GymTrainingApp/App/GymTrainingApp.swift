import SwiftUI

@main
struct GymTrainingApp: App {
    @StateObject private var appStore = AppStore()
    @StateObject private var watchPlanSyncService = WatchPlanSyncService()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appStore)
                .environmentObject(watchPlanSyncService)
        }
    }
}
