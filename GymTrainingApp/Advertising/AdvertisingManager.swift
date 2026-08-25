import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform

struct AdvertisingConfiguration: Equatable {
    static let demoAppID = "ca-app-pub-3940256099942544~1458002511"
    static let demoBannerUnitID = "ca-app-pub-3940256099942544/2435281174"
    static let demoRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"

    let appID: String
    let bannerUnitID: String
    let rewardedUnitID: String

    init(appID: String, bannerUnitID: String, rewardedUnitID: String = "") {
        self.appID = appID
        self.bannerUnitID = bannerUnitID
        self.rewardedUnitID = rewardedUnitID
    }

    static var bundled: AdvertisingConfiguration {
        AdvertisingConfiguration(
            appID: configuredString(for: "GADApplicationIdentifier") ?? "",
            bannerUnitID: configuredString(for: "BodyModeAdBannerUnitID") ?? "",
            rewardedUnitID: configuredString(for: "BodyModeAdRewardedUnitID") ?? ""
        )
    }

    var isConfigured: Bool {
        appID.hasPrefix("ca-app-pub-")
            && appID.contains("~")
            && bannerUnitID.hasPrefix("ca-app-pub-")
            && bannerUnitID.contains("/")
    }

    var isUsingDemoIDs: Bool {
        appID == Self.demoAppID && bannerUnitID == Self.demoBannerUnitID
    }

    func resolvedBannerUnitID(isTestFlight: Bool) -> String {
        isTestFlight ? Self.demoBannerUnitID : bannerUnitID
    }

    func resolvedRewardedUnitID(usesTestAds: Bool) -> String {
        usesTestAds ? Self.demoRewardedUnitID : rewardedUnitID
    }

    private static func configuredString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

@MainActor
final class AdvertisingManager: ObservableObject {
    enum State: Equatable {
        case disabled
        case preparing
        case ready
        case unavailable(String)
    }

    static let shared = AdvertisingManager()

    @Published private(set) var state: State = .disabled
    @Published private(set) var isPrivacyOptionsRequired = false
    @Published private(set) var trackingAuthorizationStatus = ATTrackingManager.trackingAuthorizationStatus

    let configuration: AdvertisingConfiguration

    private var didBeginPreparation = false
    private var didStartSDK = false

    init(configuration: AdvertisingConfiguration = .bundled) {
        self.configuration = configuration
    }

    var canDisplayAds: Bool {
        state == .ready && configuration.isConfigured
    }

    var activeBannerUnitID: String {
        configuration.resolvedBannerUnitID(
            isTestFlight: UsageDistributionChannel.current() == .testFlight
        )
    }

    var activeRewardedUnitID: String {
        configuration.resolvedRewardedUnitID(
            usesTestAds: UsageDistributionChannel.current() != .appStore
        )
    }

    var canPreviewRewardedAd: Bool {
        UsageDistributionChannel.current() != .appStore
    }

    var isUsingTestBanner: Bool {
        activeBannerUnitID == AdvertisingConfiguration.demoBannerUnitID
    }

    var isUITestPlaceholderEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--show-banner-placeholder-ui-test")
#else
        false
#endif
    }

    var statusText: String {
        switch state {
        case .disabled:
            configuration.isConfigured ? L10n.string("core_ui.14dfa1fb3cf1", fallback: "無効") : L10n.string("core_ui.952d521268fa", fallback: "広告ID未設定")
        case .preparing:
            L10n.string("core_ui.744f3f778eba", fallback: "同意状態を確認中")
        case .ready:
            isUsingTestBanner ? L10n.string("core_ui.42da49eab006", fallback: "テスト広告") : L10n.string("core_ui.d30f54815002", fallback: "パーソナライズなし")
        case .unavailable:
            L10n.string("core_ui.6951e0c608be", fallback: "現在利用できません")
        }
    }

    func prepare() {
        guard !didBeginPreparation else { return }
        didBeginPreparation = true

        guard configuration.isConfigured, !isSuppressedForUITesting else {
            state = .disabled
            return
        }

        if isUITestPlaceholderEnabled {
            state = .ready
            return
        }

        state = .preparing
        configurePrivacyDefaults()

        requestTrackingAuthorizationIfNeeded { [weak self] in
            self?.requestAdvertisingConsent()
        }
    }

    private func requestAdvertisingConsent() {
        trackingAuthorizationStatus = ATTrackingManager.trackingAuthorizationStatus

        let parameters = RequestParameters()
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] requestError in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let requestError, !ConsentInformation.shared.canRequestAds {
                    self.finishAsUnavailable(requestError)
                    return
                }

                do {
                    try await ConsentForm.loadAndPresentIfRequired(from: nil)
                } catch {
                    if !ConsentInformation.shared.canRequestAds {
                        self.finishAsUnavailable(error)
                        return
                    }
                    AppDiagnostics.shared.record(
                        error: error,
                        category: "advertising.consent",
                        message: "Advertising consent form could not be presented"
                    )
                }

                self.refreshConsentState()
            }
        }
    }

    private func requestTrackingAuthorizationIfNeeded(
        completion: @escaping @MainActor () -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            while UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }

            // A newly displayed root view can report active just before it is ready
            // to present a system permission sheet.
            try? await Task.sleep(for: .milliseconds(350))

            var status = ATTrackingManager.trackingAuthorizationStatus
            if status == .notDetermined {
                status = await requestSystemTrackingAuthorization()
            }

            if status == .notDetermined {
                try? await Task.sleep(for: .milliseconds(750))
                status = await requestSystemTrackingAuthorization()
            }

            trackingAuthorizationStatus = status
            if status != .notDetermined {
                completion()
            }
        }
    }

    private func requestSystemTrackingAuthorization() async -> ATTrackingManager.AuthorizationStatus {
        await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func presentPrivacyOptions() async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        refreshConsentState()
    }

    private var isSuppressedForUITesting: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--reset-ui-test-data")
            && !arguments.contains("--enable-test-ads-ui-test")
            && !arguments.contains("--show-banner-placeholder-ui-test")
    }

    private func configurePrivacyDefaults() {
        // Limited/non-personalized ads only. No BodyMode or HealthKit value is added to requests.
        UserDefaults.standard.set(0, forKey: "gad_has_consent_for_cookies")
        let requestConfiguration = MobileAds.shared.requestConfiguration
        requestConfiguration.publisherPrivacyPersonalizationState = .disabled
        requestConfiguration.setPublisherFirstPartyIDEnabled(false)
        requestConfiguration.maxAdContentRating = .teen
    }

    private func refreshConsentState() {
        isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard ConsentInformation.shared.canRequestAds else {
            state = .unavailable("広告の同意が得られていません。")
            return
        }

        startSDKIfNeeded()
        state = .ready
    }

    private func startSDKIfNeeded() {
        guard !didStartSDK else { return }
        didStartSDK = true
        MobileAds.shared.start()
    }

    private func finishAsUnavailable(_ error: Error) {
        state = .unavailable(error.localizedDescription)
        isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        AppDiagnostics.shared.record(
            error: error,
            category: "advertising.consent",
            message: "Advertising consent could not be gathered"
        )
    }
}
