import Foundation

enum DailyReadinessLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case good
    case normal
    case tired
    case rest

    var displayName: String { rawValue.uppercased() }
}

enum DailyRecommendationSource: String, Codable, Hashable, Sendable {
    case localRule
    case ai
    case mixed
    case user
}

enum DailyActionCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case workout
    case steps
    case protein
    case mealGuidance
    case bodyWeight
    case waist
    case bodyPhoto
    case sleep
    case recovery
    case lightActivity

    var systemImage: String {
        switch self {
        case .workout: "figure.strengthtraining.traditional"
        case .steps, .lightActivity: "figure.walk"
        case .protein: "fork.knife"
        case .mealGuidance: "takeoutbag.and.cup.and.straw.fill"
        case .bodyWeight: "scalemass"
        case .waist: "figure.core.training"
        case .bodyPhoto: "camera.fill"
        case .sleep: "bed.double.fill"
        case .recovery: "heart.text.square.fill"
        }
    }
}

enum DailyActionStatus: String, Codable, Hashable, Sendable {
    case pending
    case inProgress
    case completed
    case skipped
    case replaced
}

enum DailyActionCompletionRule: Codable, Hashable, Sendable {
    case workoutCompleted(planID: UUID?)
    case stepsAtLeast(Int)
    case proteinAtLeast(Double)
    case mealsRecorded(Int)
    case bodyMetricRecorded(BodyMetricKind)
    case photoSetRecorded
    case sleepAtLeast(Double)
    case recoveryDayObserved
    case manuallyConfirmed
}

enum DailyActionDestination: Codable, Hashable, Sendable {
    case workout(planID: UUID?)
    case steps
    case meal
    case bodyMetric(BodyMetricKind)
    case bodyPhoto
    case condition
    case none
}

struct DailyReadiness: Codable, Hashable, Sendable {
    var level: DailyReadinessLevel
    var confidence: Double
    var contributingFactors: [String]
    var missingData: [String]

    init(
        level: DailyReadinessLevel,
        confidence: Double,
        contributingFactors: [String],
        missingData: [String]
    ) {
        self.level = level
        self.confidence = min(1, max(0, confidence))
        self.contributingFactors = contributingFactors
        self.missingData = missingData
    }
}

struct DailyAction: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var category: DailyActionCategory
    var title: String
    var targetDescription: String
    var completionRule: DailyActionCompletionRule
    var destination: DailyActionDestination
    var status: DailyActionStatus
    var adoptedAt: Date?
    var priority: Int
    var rationale: String

    init(
        id: UUID = UUID(),
        category: DailyActionCategory,
        title: String,
        targetDescription: String = "",
        completionRule: DailyActionCompletionRule,
        destination: DailyActionDestination,
        status: DailyActionStatus = .pending,
        adoptedAt: Date? = nil,
        priority: Int,
        rationale: String
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.targetDescription = targetDescription
        self.completionRule = completionRule
        self.destination = destination
        self.status = status
        self.adoptedAt = adoptedAt
        self.priority = priority
        self.rationale = rationale
    }
}

struct DailyRecommendation: Identifiable, Codable, Hashable, Sendable {
    var date: Date
    var generatedAt: Date
    var readiness: DailyReadiness
    var actions: [DailyAction]
    var summary: String
    var contextVersion: Int
    var source: DailyRecommendationSource
    var aiRequestedAt: Date?
    var aiEvaluatedAt: Date?
    var evidence: [CoachEvidenceCitation]? = nil
    var evidenceStatus: CoachEvidenceStatus? = nil

    var id: Date { date }

    var activeActions: [DailyAction] {
        actions
            .filter { $0.status != .replaced }
            .sorted { $0.priority < $1.priority }
            .prefix(3)
            .map { $0 }
    }
}

struct RecommendationRevision: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var timestamp: Date
    var previousActions: [DailyAction]
    var newActions: [DailyAction]
    var reason: String
    var source: DailyRecommendationSource

    init(
        id: UUID = UUID(),
        date: Date,
        timestamp: Date = Date(),
        previousActions: [DailyAction],
        newActions: [DailyAction],
        reason: String,
        source: DailyRecommendationSource
    ) {
        self.id = id
        self.date = date
        self.timestamp = timestamp
        self.previousActions = previousActions
        self.newActions = newActions
        self.reason = reason
        self.source = source
    }
}

struct DailyReview: Identifiable, Codable, Hashable, Sendable {
    var date: Date
    var generatedAt: Date
    var completedActionIDs: [UUID]
    var skippedActionIDs: [UUID]
    var summary: String
    var nextDayAdjustments: [String]

    var id: Date { date }
}

enum TargetAdjustmentKind: String, Codable, Hashable, Sendable {
    case calorieTarget
}

enum TargetAdjustmentStatus: String, Codable, Hashable, Sendable {
    case pending
    case accepted
    case declined
}

struct TargetAdjustmentProposal: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var kind: TargetAdjustmentKind
    var currentValue: Double
    var proposedValue: Double
    var reason: String
    var status: TargetAdjustmentStatus
    var evidence: [CoachEvidenceCitation]?
    var evidenceStatus: CoachEvidenceStatus?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: TargetAdjustmentKind,
        currentValue: Double,
        proposedValue: Double,
        reason: String,
        status: TargetAdjustmentStatus = .pending,
        evidence: [CoachEvidenceCitation]? = nil,
        evidenceStatus: CoachEvidenceStatus? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.currentValue = currentValue
        self.proposedValue = proposedValue
        self.reason = reason
        self.status = status
        self.evidence = evidence
        self.evidenceStatus = evidenceStatus
    }
}

struct DailyActionProgress: Equatable, Sendable {
    var current: Double
    var target: Double
    var detail: String
    var isCompleted: Bool

    var fraction: Double {
        guard target > 0 else { return isCompleted ? 1 : 0 }
        return min(1, max(0, current / target))
    }
}

struct DailyRecommendationAIDraft: Decodable, Sendable {
    struct Action: Decodable, Sendable {
        var id: UUID?
        var category: DailyActionCategory
        var title: String
        var target: Double?
        var rationale: String

        enum CodingKeys: String, CodingKey {
            case id
            case category
            case title
            case target
            case rationale
        }
    }

    var keepExisting: Bool
    var readinessLevel: DailyReadinessLevel?
    var summary: String
    var changeReason: String
    var actions: [Action]

    enum CodingKeys: String, CodingKey {
        case keepExisting = "keep_existing"
        case readinessLevel = "readiness_level"
        case summary
        case changeReason = "change_reason"
        case actions
    }
}

extension DailyRecommendationAIDraft {
    static func parse(from response: String) throws -> DailyRecommendationAIDraft {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if let opening = trimmed.firstIndex(of: "{"), let closing = trimmed.lastIndex(of: "}") {
            json = String(trimmed[opening...closing])
        } else {
            throw DailyRecommendationAIError.invalidResponse
        }
        guard let data = json.data(using: .utf8) else {
            throw DailyRecommendationAIError.invalidResponse
        }
        return try JSONDecoder().decode(DailyRecommendationAIDraft.self, from: data)
    }
}

enum DailyRecommendationAIError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        L10n.string("domain_catalog.d88484d584a8", fallback: "AIの日次提案を読み取れませんでした。ローカル提案をそのまま使用します。")
    }
}
