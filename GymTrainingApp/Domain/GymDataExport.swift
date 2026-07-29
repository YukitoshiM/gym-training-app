import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct GymDataExport: Codable {
    var schemaVersion: Int
    var generatedAt: Date
    var userProfile: UserProfile
    var plans: [TrainingPlan]
    var workoutHistory: [WorkoutSession]
    var bodyMetricEntries: [BodyMetricEntry]
    var bodyMetricGoals: [BodyMetricGoal]
    var mealEntries: [MealEntry]
    var bodyPhotoEntries: [BodyPhotoEntry]
    var customExercises: [Exercise]
    var aiInsights: [AIInsight]
    var sensorSettings: SensorSettings
    var appearanceSettings: AppAppearanceSettings
    var gymLocation: GymLocation?
    var gymVisits: [GymVisit]
    var subjectiveRecoveryEntries: [SubjectiveRecoveryEntry]
    var aiTransmissionHistory: [AITransmissionRecord]
}

struct GymDataExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data("{}".utf8)) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
