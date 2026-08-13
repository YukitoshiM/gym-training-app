import Foundation

enum BodyPhotoAngle: String, CaseIterable, Identifiable, Codable {
    case front
    case side
    case back
    case abdomen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .front: "正面"
        case .side: "横"
        case .back: "背面"
        case .abdomen: "腹部アップ"
        }
    }
}

struct BodyPhotoAnalysisInput: Hashable {
    let angle: BodyPhotoAngle
    let imageData: Data
}

struct BodyPhotoEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var recordedAt: Date
    var angle: BodyPhotoAngle
    var memo: String
    var imageData: Data?
    var aiComment: BodyPhotoAIComment?

    init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        angle: BodyPhotoAngle = .front,
        memo: String = "",
        imageData: Data? = nil,
        aiComment: BodyPhotoAIComment? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.angle = angle
        self.memo = memo
        self.imageData = imageData
        self.aiComment = aiComment
    }
}

struct BodyPhotoSet: Identifiable, Hashable {
    let date: Date
    let entries: [BodyPhotoEntry]

    var id: Date { date }

    var photoEntries: [BodyPhotoEntry] {
        entries
            .filter { $0.imageData != nil }
            .sorted { left, right in
                let leftIndex = BodyPhotoAngle.allCases.firstIndex(of: left.angle) ?? 0
                let rightIndex = BodyPhotoAngle.allCases.firstIndex(of: right.angle) ?? 0
                if leftIndex == rightIndex { return left.recordedAt > right.recordedAt }
                return leftIndex < rightIndex
            }
    }

    var angleEntries: [BodyPhotoEntry] {
        BodyPhotoAngle.allCases.compactMap { angle in
            photoEntries.first { $0.angle == angle }
        }
    }

    var analysis: BodyPhotoAIComment? {
        photoEntries.compactMap(\.aiComment).first
            ?? entries.compactMap(\.aiComment).first
    }

    var needsAnalysis: Bool {
        !photoEntries.isEmpty && (analysis == nil || photoEntries.contains { $0.aiComment == nil })
    }

    var memo: String {
        entries
            .sorted { $0.recordedAt > $1.recordedAt }
            .lazy
            .map(\.memo)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? ""
    }

    var recordedAt: Date {
        entries.map(\.recordedAt).max() ?? date
    }

    static func grouped(
        _ entries: [BodyPhotoEntry],
        calendar: Calendar = .current
    ) -> [BodyPhotoSet] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.recordedAt) }
            .map { day, entries in
                BodyPhotoSet(
                    date: day,
                    entries: entries.sorted { $0.recordedAt > $1.recordedAt }
                )
            }
            .sorted { $0.date > $1.date }
    }
}
