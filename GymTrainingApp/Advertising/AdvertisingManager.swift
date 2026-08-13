import GoogleMobileAds
import SwiftUI
import UserMessagingPlatform

struct AdvertisingConfiguration: Equatable {
    static let demoAppID = "ca-app-pub-3940256099942544~1458002511"
    static let demoBannerUnitID = "ca-app-pub-3940256099942544/2435281174"

    let appID: String
    let bannerUnitID: String

    static var bundled: AdvertisingConfiguration {
        AdvertisingConfiguration(
            appID: configuredString(for: "GADApplicationIdentifier") ?? "",
            bannerUnitID: configuredString(for: "BodyModeAdBannerUnitID") ?? ""
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

    let configuration: AdvertisingConfiguration

    private var didBeginPreparation = false
    private var didStartSDK = false

    init(configuration: AdvertisingConfiguration = .bundled) {
        self.configuration = configuration
    }

    var canDisplayAds: Bool {
        state == .ready && configuration.isConfigured
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
            configuration.isConfigured ? "無効" : "広告ID未設定"
        case .preparing:
            "同意状態を確認中"
        case .ready:
            configuration.isUsingDemoIDs ? "テスト広告" : "パーソナライズなし"
        case .unavailable:
            "現在利用できません"
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
