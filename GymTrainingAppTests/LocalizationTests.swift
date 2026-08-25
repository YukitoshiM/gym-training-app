import XCTest
@testable import GymTrainingApp

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguagePreference.storageKey)
        super.tearDown()
    }

    func testEnglishCatalogResolvesStableLocalizationID() throws {
        let localizationPath = try XCTUnwrap(
            Bundle.main.path(forResource: "en-US", ofType: "lproj")
                ?? Bundle.main.path(forResource: "en", ofType: "lproj")
        )
        let englishBundle = try XCTUnwrap(Bundle(path: localizationPath))

        XCTAssertEqual(
            L10n.string("core_ui.ef6a6560996f", fallback: "ホーム", bundle: englishBundle),
            "Home"
        )
    }

    func testLocalizedTemplateReplacesOrderedValues() throws {
        let localizationPath = try XCTUnwrap(
            Bundle.main.path(forResource: "en-US", ofType: "lproj")
                ?? Bundle.main.path(forResource: "en", ofType: "lproj")
        )
        let englishBundle = try XCTUnwrap(Bundle(path: localizationPath))

        XCTAssertEqual(
            L10n.string(
                "core_ui.703c05467ff9",
                fallback: "{{value1}} / {{value2}} 完了",
                values: ["2", "3"],
                bundle: englishBundle
            ),
            "2 / 3 complete"
        )
    }

    func testReleaseDeltaResolvesAndPreservesPlaceholder() throws {
        let localizationPath = try XCTUnwrap(
            Bundle.main.path(forResource: "en-US", ofType: "lproj")
                ?? Bundle.main.path(forResource: "en", ofType: "lproj")
        )
        let englishBundle = try XCTUnwrap(Bundle(path: localizationPath))

        let value = L10n.string(
            "release_delta.evidence_count",
            fallback: "科学的根拠 {{value1}}件",
            values: ["3"],
            bundle: englishBundle
        )

        XCTAssertTrue(value.contains("3"))
        XCTAssertFalse(value.contains("{{value1}}"))
    }

    func testInAppLanguageSelectionOverridesSystemLocalization() {
        UserDefaults.standard.set("en-US", forKey: AppLanguagePreference.storageKey)

        XCTAssertEqual(
            L10n.string("core_ui.ef6a6560996f", fallback: "ホーム"),
            "Home"
        )
        XCTAssertEqual(AppLanguagePreference.locale.identifier, "en-US")
    }

    func testUnsupportedStoredLanguageFallsBackToSystem() {
        UserDefaults.standard.set("unsupported", forKey: AppLanguagePreference.storageKey)

        XCTAssertEqual(AppLanguagePreference.selectedIdentifier, AppLanguagePreference.systemIdentifier)
    }
}
