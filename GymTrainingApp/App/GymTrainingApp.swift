import SwiftUI

@main
struct GymTrainingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appStore = AppStore()
    @StateObject private var aiTrainerBackgroundService = AITrainerBackgroundService.shared
    @StateObject private var watchPlanSyncService = WatchPlanSyncService()
    @StateObject private var healthDataManager = HealthDataManager()
    @StateObject private var gymLocationManager = GymLocationManager()
    @AppStorage(LegalConsentStore.acceptedVersionKey) private var acceptedLegalVersion = ""
    @State private var forceConsentPresentation = ProcessInfo.processInfo.arguments.contains("--force-legal-consent-ui-test")
    @State private var initialSetupVersion: Int

    init() {
        _initialSetupVersion = State(initialValue: InitialSetupStateStore.prepareForLaunch())
        AppDiagnostics.shared.start()
        UsageAnalytics.shared.record(.appOpened)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if shouldShowLegalConsent {
                    ReleaseConsentView {
                        LegalConsentStore.acceptCurrent()
                        acceptedLegalVersion = LegalConfiguration.currentConsentVersion
                        forceConsentPresentation = false
                    }
                } else if initialSetupVersion < InitialSetupStateStore.currentVersion {
                    InitialSetupView(profile: appStore.userProfile) {
                        AppTourStateStore.schedule()
                        InitialSetupStateStore.markCompleted()
                        initialSetupVersion = InitialSetupStateStore.currentVersion
                    }
                    .environmentObject(appStore)
                } else {
                    RootTabView()
                        .environmentObject(appStore)
                        .environmentObject(watchPlanSyncService)
                        .environmentObject(healthDataManager)
                        .environmentObject(gymLocationManager)
                }
            }
            .environmentObject(aiTrainerBackgroundService)
            .onAppear {
                aiTrainerBackgroundService.bind(appStore: appStore)
            }
            .preferredColorScheme(AppTheme.preferredColorScheme(for: appStore.appearanceSettings.mode))
            .id("\(appStore.appearanceSettings.colorTheme.rawValue)-\(appStore.appearanceSettings.mode.rawValue)")
        }
    }

    private var shouldShowLegalConsent: Bool {
        if forceConsentPresentation {
            return true
        }

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--reset-ui-test-data") {
            return false
        }

        return acceptedLegalVersion != LegalConfiguration.currentConsentVersion
    }
}

enum InitialSetupStateStore {
    static let completedVersionKey = "bodymode.initialSetup.completedVersion"
    static let currentVersion = 1

    static func prepareForLaunch(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Int {
        if arguments.contains("--force-initial-setup") {
            return 0
        }
        if arguments.contains("--reset-ui-test-data") {
            return currentVersion
        }
        if defaults.object(forKey: completedVersionKey) != nil {
            return defaults.integer(forKey: completedVersionKey)
        }

        let hasUsedPreviousVersion = !(defaults.string(forKey: LegalConsentStore.acceptedVersionKey) ?? "").isEmpty
        let version = hasUsedPreviousVersion ? currentVersion : 0
        defaults.set(version, forKey: completedVersionKey)
        return version
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: completedVersionKey)
    }
}
