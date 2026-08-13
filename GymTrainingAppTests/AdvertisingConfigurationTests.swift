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
}
