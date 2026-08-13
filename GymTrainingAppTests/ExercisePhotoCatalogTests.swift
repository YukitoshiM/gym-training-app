import XCTest
@testable import GymTrainingApp

final class ExercisePhotoCatalogTests: XCTestCase {
    func testEveryPresetExerciseHasAnIndividualPhotoPanel() {
        let references = PresetExerciseStore.exercises.map(\.photoReference)

        XCTAssertEqual(references.count, 71)
        XCTAssertEqual(Set(references).count, 71)
        XCTAssertTrue(references.allSatisfy { (1...12).contains(atlasNumber(from: $0.atlasName)) })
        XCTAssertTrue(references.allSatisfy { (0...2).contains($0.column) })
        XCTAssertTrue(references.allSatisfy { (0...1).contains($0.row) })
    }

    func testCustomExerciseUsesGenericGymPhoto() {
        let custom = Exercise(
            name: "施設独自の種目",
            primaryMuscle: .fullBody,
            equipment: .other,
            instruction: "施設の案内に従う"
        )

        XCTAssertEqual(custom.photoReference, ExercisePhotoCatalog.fallbackReference)
    }

    private func atlasNumber(from name: String) -> Int {
        Int(name.suffix(2)) ?? 0
    }
}
