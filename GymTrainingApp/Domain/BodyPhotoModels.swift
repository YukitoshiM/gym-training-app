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
