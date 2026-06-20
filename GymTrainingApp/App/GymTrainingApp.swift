import SwiftUI

@main
struct GymTrainingApp: App {
    @StateObject private var appStore = AppStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appStore)
        }
    }
}
