import Foundation
import Testing
@testable import GymTrainingApp

@Suite("Advertising configuration")
struct AdvertisingConfigurationTests {
    @Test("Google demo identifiers are accepted as a valid test configuration")
    func demoConfiguration() {
        let configuration = AdvertisingConfiguration(
            appID: AdvertisingConfiguration.demoAppID,
            bannerUnitID: AdvertisingConfiguration.demoBannerUnitID
        )

        #expect(configuration.isConfigured)
        #expect(configuration.isUsingDemoIDs)
    }

    @Test("Incomplete or malformed identifiers disable advertising")
    func invalidConfiguration() {
        #expect(!AdvertisingConfiguration(appID: "", bannerUnitID: "").isConfigured)
        #expect(
            !AdvertisingConfiguration(
                appID: "ca-app-pub-1234",
                bannerUnitID: "ca-app-pub-1234/5678"
            ).isConfigured
        )
    }

    @Test("TestFlight resolves to Google's demo banner while App Store builds keep production")
    func distributionSpecificBannerIdentifier() {
        let productionBanner = "ca-app-pub-1234567890123456/1234567890"
        let configuration = AdvertisingConfiguration(
            appID: "ca-app-pub-1234567890123456~1234567890",
            bannerUnitID: productionBanner
        )

        #expect(
            configuration.resolvedBannerUnitID(isTestFlight: true)
                == AdvertisingConfiguration.demoBannerUnitID
        )
        #expect(configuration.resolvedBannerUnitID(isTestFlight: false) == productionBanner)
    }

    @Test("Test environments use Google's demo rewarded unit")
    func distributionSpecificRewardedIdentifier() {
        let productionRewarded = "ca-app-pub-1234567890123456/0987654321"
        let configuration = AdvertisingConfiguration(
            appID: "ca-app-pub-1234567890123456~1234567890",
            bannerUnitID: "ca-app-pub-1234567890123456/1234567890",
            rewardedUnitID: productionRewarded
        )

        #expect(
            configuration.resolvedRewardedUnitID(usesTestAds: true)
                == AdvertisingConfiguration.demoRewardedUnitID
        )
        #expect(configuration.resolvedRewardedUnitID(usesTestAds: false) == productionRewarded)
    }

    @Test("Distribution channel uses the receipt once for ads, analytics, and AI quota")
    func distributionChannelResolution() {
        #expect(
            UsageDistributionChannel.resolve(
                receiptURL: URL(fileURLWithPath: "/receipt/sandboxReceipt"),
                isSimulator: false
            ) == .testFlight
        )
        #expect(
            UsageDistributionChannel.resolve(
                receiptURL: URL(fileURLWithPath: "/receipt/receipt"),
                isSimulator: false
            ) == .appStore
        )
        #expect(
            UsageDistributionChannel.resolve(receiptURL: nil, isSimulator: false) == .appStore
        )
        #expect(
            UsageDistributionChannel.resolve(receiptURL: nil, isSimulator: true) == .simulator
        )
    }
}
