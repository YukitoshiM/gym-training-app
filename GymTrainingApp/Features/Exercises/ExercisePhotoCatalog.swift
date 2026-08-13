import Foundation

struct ExercisePhotoReference: Hashable {
    let atlasName: String
    let column: Int
    let row: Int
}

enum ExercisePhotoCatalog {
    static let fallbackReference = ExercisePhotoReference(
        atlasName: "ExerciseAtlas12",
        column: 2,
        row: 1
    )

    private static let presetIndexByName: [String: Int] = Dictionary(
        uniqueKeysWithValues: PresetExerciseStore.exercises.enumerated().map { index, exercise in
            (exercise.name, index)
        }
    )

    static func reference(for exerciseName: String) -> ExercisePhotoReference {
        guard let index = presetIndexByName[exerciseName] else {
            return fallbackReference
        }

        let atlasNumber = (index / 6) + 1
        let panel = index % 6
        return ExercisePhotoReference(
            atlasName: String(format: "ExerciseAtlas%02d", atlasNumber),
            column: panel % 3,
            row: panel / 3
        )
    }
}

extension Exercise {
    var photoReference: ExercisePhotoReference {
        ExercisePhotoCatalog.reference(for: name)
    }
}
