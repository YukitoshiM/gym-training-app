import SwiftUI

@main
struct GymTrainingWatchApp: App {
    @StateObject private var workoutStore = WatchWorkoutStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(workoutStore)
                .id(workoutStore.appearanceSettings.colorTheme.rawValue)
        }
    }
}
