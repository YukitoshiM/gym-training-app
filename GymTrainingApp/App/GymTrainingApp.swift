import SwiftUI

@main
struct GymTrainingApp: App {
    @StateObject private var appStore = AppStore()
    @StateObject private var watchPlanSyncService = WatchPlanSyncService()
    @StateObject private var healthDataManager = HealthDataManager()
    @StateObject private var gymLocationManager = GymLocationManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appStore)
                .environmentObject(watchPlanSyncService)
                .environmentObject(healthDataManager)
                .environmentObject(gymLocationManager)
        }
    }
}
