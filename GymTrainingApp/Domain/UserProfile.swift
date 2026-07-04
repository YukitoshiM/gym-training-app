import Foundation

enum GoalType: String, CaseIterable, Identifiable, Codable {
    case diet
    case muscleGain
    case health
    case bodyShape
    case performance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .diet: "ダイエット"
        case .muscleGain: "筋肥大"
        case .health: "健康維持"
        case .bodyShape: "体型改善"
        case .performance: "競技力向上"
        }
    }

    var shortAction: String {
        switch self {
        case .diet:
            "体重・腹囲・食事を記録する"
        case .muscleGain:
            "トレーニング量とたんぱく質を確認する"
        case .health:
            "体重・腹囲・運動頻度を確認する"
        case .bodyShape:
            "体型写真と腹囲を記録する"
        case .performance:
            "疲労度と練習量をメモする"
        }
    }

    var insightTitle: String {
        switch self {
        case .diet: "減量の確認ポイント"
        case .muscleGain: "筋肥大の確認ポイント"
        case .health: "健康維持の確認ポイント"
        case .bodyShape: "体型改善の確認ポイント"
        case .performance: "競技力向上の確認ポイント"
        }
    }

    var insightBody: String {
        switch self {
        case .diet:
            "体重だけでなく腹囲と食事記録を合わせて見ます。横ばいでも腹囲が落ちていれば進捗ありです。"
        case .muscleGain:
            "体重、トレーニングボリューム、種目別重量を見ます。前回実績を使って少しずつ伸ばします。"
        case .health:
            "体重、腹囲、運動頻度を無理なく維持します。記録が途切れないことを優先します。"
        case .bodyShape:
            "腹囲と体型写真の変化を重視します。写真は同じ角度、同じ光で撮ると比較しやすくなります。"
        case .performance:
            "体重、筋トレ量、疲労度、睡眠を見ます。疲労が高い日は無理に伸ばさない設計にします。"
        }
    }
}

struct UserProfile: Codable, Equatable {
    var goalType: GoalType

    static let `default` = UserProfile(goalType: .bodyShape)
}
