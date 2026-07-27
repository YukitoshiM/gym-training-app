import Foundation

enum CoachType: String, CaseIterable, Identifiable, Codable {
    case fatLoss = "fat_loss"
    case hypertrophy
    case strength
    case bodyRecomposition = "body_recomposition"
    case wellness
    case returnToTraining = "return_to_training"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fatLoss: "減量コーチ"
        case .hypertrophy: "筋肥大コーチ"
        case .strength: "筋力向上コーチ"
        case .bodyRecomposition: "ボディメイクコーチ"
        case .wellness: "健康維持コーチ"
        case .returnToTraining: "復帰コーチ"
        }
    }

    var characteristic: String {
        switch self {
        case .fatLoss: "筋量を守りながら、カロリー・体重傾向・空腹対策を現実的に調整"
        case .hypertrophy: "トレーニング量、漸進性過負荷、PFC、回復を一体で評価"
        case .strength: "重量・回数・RPE・技術から、疲労を管理して主要種目を伸ばす"
        case .bodyRecomposition: "体重だけでなく腹囲・写真・筋力を合わせて体型変化を評価"
        case .wellness: "完璧さより継続性を優先し、活動量・睡眠・無理のない運動を支援"
        case .returnToTraining: "ブランク後の痛みと反応を確認し、負荷を段階的に戻す"
        }
    }

    static func recommended(for goal: GoalType) -> CoachType {
        switch goal {
        case .diet: .fatLoss
        case .muscleGain: .hypertrophy
        case .health: .wellness
        case .bodyShape: .bodyRecomposition
        case .performance: .strength
        }
    }
}

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

enum Sex: String, CaseIterable, Identifiable, Codable {
    case unspecified
    case male
    case female

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unspecified: "未設定"
        case .male: "男性"
        case .female: "女性"
        }
    }
}

enum ExperienceLevel: String, CaseIterable, Identifiable, Codable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: "初心者"
        case .intermediate: "中級者"
        case .advanced: "上級者"
        }
    }
}

enum WeightUnit: String, CaseIterable, Identifiable, Codable {
    case kg
    case lb

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kg: "kg"
        case .lb: "lb"
        }
    }
}

struct UserProfile: Codable, Equatable {
    var goalType: GoalType
    var coachType: CoachType
    var heightCm: Double?
    var birthYear: Int?
    var sex: Sex
    var experienceLevel: ExperienceLevel
    var weightUnit: WeightUnit
    var nutritionGoals: NutritionGoals

    static let `default` = UserProfile(
        goalType: .bodyShape,
        coachType: .bodyRecomposition,
        heightCm: nil,
        birthYear: nil,
        sex: .unspecified,
        experienceLevel: .beginner,
        weightUnit: .kg,
        nutritionGoals: .default
    )

    init(
        goalType: GoalType,
        coachType: CoachType? = nil,
        heightCm: Double?,
        birthYear: Int?,
        sex: Sex,
        experienceLevel: ExperienceLevel,
        weightUnit: WeightUnit,
        nutritionGoals: NutritionGoals = .default
    ) {
        self.goalType = goalType
        self.coachType = coachType ?? CoachType.recommended(for: goalType)
        self.heightCm = heightCm
        self.birthYear = birthYear
        self.sex = sex
        self.experienceLevel = experienceLevel
        self.weightUnit = weightUnit
        self.nutritionGoals = nutritionGoals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default
        goalType = try container.decodeIfPresent(GoalType.self, forKey: .goalType) ?? defaults.goalType
        coachType = try container.decodeIfPresent(CoachType.self, forKey: .coachType)
            ?? CoachType.recommended(for: goalType)
        heightCm = try container.decodeIfPresent(Double.self, forKey: .heightCm)
        birthYear = try container.decodeIfPresent(Int.self, forKey: .birthYear)
        sex = try container.decodeIfPresent(Sex.self, forKey: .sex) ?? defaults.sex
        experienceLevel = try container.decodeIfPresent(ExperienceLevel.self, forKey: .experienceLevel) ?? defaults.experienceLevel
        weightUnit = try container.decodeIfPresent(WeightUnit.self, forKey: .weightUnit) ?? defaults.weightUnit
        nutritionGoals = try container.decodeIfPresent(NutritionGoals.self, forKey: .nutritionGoals) ?? defaults.nutritionGoals
    }
}

struct NutritionGoals: Codable, Equatable, Hashable {
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var mealCount: Int

    static let `default` = NutritionGoals(
        calories: 2_000,
        protein: 120,
        fat: 60,
        carbs: 250,
        mealCount: 3
    )

    func normalized() -> NutritionGoals {
        NutritionGoals(
            calories: min(10_000, max(0, calories)),
            protein: min(1_000, max(0, protein)),
            fat: min(1_000, max(0, fat)),
            carbs: min(2_000, max(0, carbs)),
            mealCount: min(12, max(1, mealCount))
        )
    }
}
