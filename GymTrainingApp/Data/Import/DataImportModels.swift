import Foundation

enum DataImportFormat: String, Codable, CaseIterable, Identifiable {
    case bodyModeJSON
    case strongCSV
    case hevyCSV
    case appleHealthXML
    case jefitCSV
    case genericCSV

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodyModeJSON: "BodyMode JSON"
        case .strongCSV: "Strong CSV"
        case .hevyCSV: "Hevy CSV"
        case .appleHealthXML: "Apple Health XML"
        case .jefitCSV: "JEFIT CSV"
        case .genericCSV: "CSV"
        }
    }
}

enum DataImportWarningSeverity: String, Codable {
    case information
    case caution
    case blocking
}

struct DataImportWarning: Identifiable, Codable, Hashable {
    var id: String { "\(severity.rawValue):\(message)" }
    var severity: DataImportWarningSeverity
    var message: String
}

struct DataImportOptions: Equatable {
    var ambiguousWeightUnit: WeightUnit?
    var timeZone: TimeZone = .current
    var hasConfirmedTimeZone = false
}

struct DataImportSummary: Codable, Equatable, Hashable {
    var workoutCount = 0
    var exerciseCount = 0
    var setCount = 0
    var bodyMetricCount = 0
    var planCount = 0
    var mealCount = 0
    var photoCount = 0
    var duplicateCount = 0

    var totalRecordCount: Int {
        workoutCount + bodyMetricCount + planCount + mealCount + photoCount
    }
}

struct DataImportPayload {
    var workouts: [WorkoutSession] = []
    var bodyMetrics: [BodyMetricEntry] = []
    var customExercises: [Exercise] = []
    var bodyModeRestore: GymDataExport?
}

struct DataImportPreview: Identifiable {
    let id = UUID()
    var fileName: String
    var fingerprint: String
    var format: DataImportFormat
    var payload: DataImportPayload
    var summary: DataImportSummary
    var warnings: [DataImportWarning]
    var requiresWeightUnit: Bool
    var requiresTimeZoneConfirmation: Bool
    var wasPreviouslyImported: Bool

    var canImport: Bool {
        !wasPreviouslyImported
            && !warnings.contains(where: { $0.severity == .blocking })
            && (format == .bodyModeJSON || summary.totalRecordCount > 0)
    }
}

struct DataImportReceipt: Identifiable, Codable, Hashable {
    enum State: String, Codable {
        case applied
        case rolledBack
    }

    var id: UUID
    var importedAt: Date
    var fileName: String
    var fingerprint: String
    var format: DataImportFormat
    var summary: DataImportSummary
    var state: State

    init(
        id: UUID = UUID(),
        importedAt: Date = Date(),
        fileName: String,
        fingerprint: String,
        format: DataImportFormat,
        summary: DataImportSummary,
        state: State = .applied
    ) {
        self.id = id
        self.importedAt = importedAt
        self.fileName = fileName
        self.fingerprint = fingerprint
        self.format = format
        self.summary = summary
        self.state = state
    }
}

struct DataImportUndoSnapshot: Codable {
    var receiptID: UUID
    var createdAt: Date
    var previousData: GymDataExport
}

enum DataImportError: LocalizedError {
    case unsupportedFormat
    case malformedFile(String)
    case newerBodyModeSchema(Int)
    case weightUnitRequired
    case timeZoneConfirmationRequired
    case alreadyImported
    case nothingToImport
    case noRollbackAvailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "対応していないファイル形式です。BodyMode JSON、Strong、Hevy、JEFIT、一般的なCSV、Apple Health XMLを選んでください。"
        case .malformedFile(let detail):
            "ファイルを読み取れませんでした。\(detail)"
        case .newerBodyModeSchema(let version):
            "このバックアップは新しいBodyMode形式（スキーマ\(version)）です。アプリを更新してから復元してください。"
        case .weightUnitRequired:
            "重量の単位を選択してください。"
        case .timeZoneConfirmationRequired:
            "日時にタイムゾーンがないため、使用するタイムゾーンを確認してください。"
        case .alreadyImported:
            "このファイルはすでに読み込み済みです。"
        case .nothingToImport:
            "追加できる記録がありません。"
        case .noRollbackAvailable:
            "元に戻せる取り込みがありません。"
        }
    }
}
