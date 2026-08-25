import XCTest
@testable import GymTrainingApp

final class BodyUnitPreferenceTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: BodyUnitPreferences.weightKey)
        UserDefaults.standard.removeObject(forKey: BodyLengthUnit.storageKey)
        super.tearDown()
    }

    func testPoundsRoundTripKeepsKilogramStorageValue() {
        UserDefaults.standard.set(WeightUnit.lb.rawValue, forKey: BodyUnitPreferences.weightKey)
        let stored = 72.4
        let displayed = BodyMetricKind.bodyWeight.displayedValue(fromStored: stored)

        XCTAssertEqual(BodyMetricKind.bodyWeight.storedValue(fromDisplayed: displayed), stored, accuracy: 0.0001)
    }

    func testInchesRoundTripKeepsCentimeterStorageValue() {
        UserDefaults.standard.set(BodyLengthUnit.inches.rawValue, forKey: BodyLengthUnit.storageKey)
        let stored = 82.5
        let displayed = BodyMetricKind.waist.displayedValue(fromStored: stored)

        XCTAssertEqual(BodyMetricKind.waist.storedValue(fromDisplayed: displayed), stored, accuracy: 0.0001)
    }

    func testWeightUnitDefaultsFromRegion() {
        XCTAssertEqual(WeightUnit.defaultValue(for: Locale(identifier: "en_US")), .lb)
        XCTAssertEqual(WeightUnit.defaultValue(for: Locale(identifier: "ja_JP")), .kg)
        XCTAssertEqual(WeightUnit.defaultValue(for: Locale(identifier: "en_GB")), .kg)
    }
}
