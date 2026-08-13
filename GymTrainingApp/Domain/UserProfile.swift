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

    var expertiseProfile: CoachExpertiseProfile {
        CoachExpertiseProfile.profile(for: self)
    }

    static func recommendationReason(for profile: UserProfile) -> String {
        recommendations(for: profile).first?.reason
            ?? "目的と記録状況に合わせて担当を選べます。"
    }

    static func recommendations(for profile: UserProfile, limit: Int = 3) -> [CoachRecommendation] {
        var scores = Dictionary(uniqueKeysWithValues: allCases.map { ($0, 0) })
        scores[recommended(for: profile.goalType), default: 0] += 100

        let outcomeCoaches: [CoachType] = switch profile.outcomeStyle {
        case .leanMuscular, .vShape, .balancedMuscularity:
            [.hypertrophy, .bodyRecomposition]
        case .strengthFocused, .sportsPerformance:
            [.strength, .hypertrophy]
        case .steadyFatLoss, .waistFocused:
            [.fatLoss, .bodyRecomposition]
        case .activeLifestyle, .postureBalance:
            [.wellness, .bodyRecomposition]
        case .endurance:
            [.strength, .wellness]
        case .custom:
            []
        }
        for (index, coach) in outcomeCoaches.enumerated() {
            scores[coach, default: 0] += 35 - index * 10
        }

        if profile.experienceLevel == .beginner {
            scores[.wellness, default: 0] += 12
            scores[.returnToTraining, default: 0] += 6
        } else if profile.experienceLevel == .advanced {
            scores[.strength, default: 0] += 8
            scores[.hypertrophy, default: 0] += 8
        }
        if Set(profile.availableEquipment).isSubset(of: [.bodyweight, .resistanceBand, .other]) {
            scores[.wellness, default: 0] += 12
        }

        let outcome = profile.outcomeStyle == .custom && !profile.customOutcomeText.isEmpty
            ? profile.customOutcomeText
            : profile.outcomeStyle.displayName
        return allCases
            .sorted {
                let left = scores[$0, default: 0]
                let right = scores[$1, default: 0]
                return left == right ? $0.rawValue < $1.rawValue : left > right
            }
            .prefix(max(1, limit))
            .enumerated()
            .map { index, coach in
                let focus = coach.expertiseProfile.topFocusAreas.prefix(2).joined(separator: "と")
                let reason = index == 0
                    ? "\(profile.goalType.displayName)と「\(outcome)」に合わせ、\(focus)を優先します。"
                    : "別案として、\(coach.expertiseProfile.promise)。\(focus)を重視したい場合に合います。"
                return CoachRecommendation(coachType: coach, reason: reason)
            }
    }
}

struct CoachRecommendation: Identifiable, Hashable {
    var coachType: CoachType
    var reason: String

    var id: CoachType { coachType }
}

enum CoachPersona: String, CaseIterable, Identifiable, Codable {
    case aiko
    case ren
    case maya
    case haru
    case ken
    case emi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aiko: "Aiko"
        case .ren: "Leo"
        case .maya: "Maya"
        case .haru: "Noor"
        case .ken: "Diego"
        case .emi: "Priya"
        }
    }

    var assetName: String {
        switch self {
        case .aiko: "CoachAvatarAiko"
        case .ren: "CoachAvatarRen"
        case .maya: "CoachAvatarMaya"
        case .haru: "CoachAvatarHaru"
        case .ken: "CoachAvatarKen"
        case .emi: "CoachAvatarEmi"
        }
    }

    var coachingTone: String {
        recommendedStyle.promptDescription
    }

    var recommendedStyle: CoachingStyle {
        switch self {
        case .aiko: .calm
        case .ren: .direct
        case .maya: .encouraging
        case .haru: .analytical
        case .ken: .calm
        case .emi: .cautious
        }
    }
}

enum CoachingStyle: String, CaseIterable, Identifiable, Codable {
    case calm
    case direct
    case analytical
    case encouraging
    case cautious

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm: "穏やか"
        case .direct: "率直"
        case .analytical: "論理的"
        case .encouraging: "鼓舞"
        case .cautious: "慎重"
        }
    }

    var promptDescription: String {
        switch self {
        case .calm: "穏やかで現実的。小さな継続を具体的に認める"
        case .direct: "明るく率直。次に伸ばす一点を明確にする"
        case .analytical: "落ち着いて論理的。数値と体感を分けて説明する"
        case .encouraging: "力強く親しみやすい。達成を自信につなげる"
        case .cautious: "温かく慎重。焦らず安全に前進できる言葉を選ぶ"
        }
    }
}

struct CoachFocus: Hashable {
    let hypertrophy: Int
    let bodyRecomposition: Int
    let fatLoss: Int
    let nutrition: Int
    let movement: Int
    let recovery: Int
    let performance: Int
}

struct CoachExpertiseProfile: Identifiable, Hashable {
    let id: CoachType
    let promise: String
    let recommendedFor: [String]
    let focus: CoachFocus
    let approach: [String]
    let boundaries: [String]
    let topFocusAreas: [String]

    static func profile(for type: CoachType) -> CoachExpertiseProfile {
        switch type {
        case .fatLoss:
            CoachExpertiseProfile(
                id: type,
                promise: "無理なく落とし、戻りにくい習慣を作る",
                recommendedFor: ["減量を始めたい", "食事管理が続かない", "腹囲も整えたい"],
                focus: CoachFocus(hypertrophy: 2, bodyRecomposition: 4, fatLoss: 5, nutrition: 5, movement: 3, recovery: 3, performance: 1),
                approach: ["週平均で体重傾向を見る", "食事と活動量を小さく調整", "空腹と継続性を確認"],
                boundaries: ["急激な減量を勧めない", "医療的な診断をしない"],
                topFocusAreas: ["減量", "食事・栄養", "体型改善"]
            )
        case .hypertrophy:
            CoachExpertiseProfile(
                id: type,
                promise: "回復できる量で筋肉を着実に増やす",
                recommendedFor: ["筋量を増やしたい", "部位を重点的に伸ばしたい", "停滞を見直したい"],
                focus: CoachFocus(hypertrophy: 5, bodyRecomposition: 4, fatLoss: 1, nutrition: 4, movement: 2, recovery: 4, performance: 3),
                approach: ["ボリュームと漸進性を確認", "PFCと睡眠を合わせて評価", "部位バランスを調整"],
                boundaries: ["回復不能な量を増やさない", "見た目だけで体脂肪率を断定しない"],
                topFocusAreas: ["筋肥大", "回復", "食事・栄養"]
            )
        case .strength:
            CoachExpertiseProfile(
                id: type,
                promise: "疲労を管理しながら扱える力を伸ばす",
                recommendedFor: ["主要種目を伸ばしたい", "PRを狙いたい", "競技力を高めたい"],
                focus: CoachFocus(hypertrophy: 3, bodyRecomposition: 1, fatLoss: 1, nutrition: 2, movement: 4, recovery: 4, performance: 5),
                approach: ["重量・回数・RPEを比較", "疲労を見て負荷を調整", "PR傾向を長期で確認"],
                boundaries: ["危険な最大挙上を強制しない", "フォームや怪我を診断しない"],
                topFocusAreas: ["筋力・競技力", "回復", "動作・活動性"]
            )
        case .bodyRecomposition:
            CoachExpertiseProfile(
                id: type,
                promise: "数字と見た目の両方から身体を整える",
                recommendedFor: ["見た目を変えたい", "体重だけでは判断しづらい", "筋肉を保って絞りたい"],
                focus: CoachFocus(hypertrophy: 4, bodyRecomposition: 5, fatLoss: 4, nutrition: 4, movement: 3, recovery: 3, performance: 2),
                approach: ["写真・腹囲・体重を同期間で比較", "筋力の維持も確認", "次の一手を少数に絞る"],
                boundaries: ["写真から数値を断定しない", "写っていない部位を推測しない"],
                topFocusAreas: ["体型改善", "筋肥大", "減量"]
            )
        case .wellness:
            CoachExpertiseProfile(
                id: type,
                promise: "体調を崩さず、動ける毎日を続ける",
                recommendedFor: ["健康習慣を作りたい", "運動初心者", "無理なく続けたい"],
                focus: CoachFocus(hypertrophy: 1, bodyRecomposition: 3, fatLoss: 2, nutrition: 3, movement: 5, recovery: 5, performance: 1),
                approach: ["睡眠と疲労を優先", "歩数と軽い運動を積み上げ", "未達を責めず翌日へ調整"],
                boundaries: ["健康状態を診断しない", "体調不良時に運動を強制しない"],
                topFocusAreas: ["回復", "動作・活動性", "食事・栄養"]
            )
        case .returnToTraining:
            CoachExpertiseProfile(
                id: type,
                promise: "焦らず段階的に運動へ戻る",
                recommendedFor: ["ブランクから戻りたい", "疲労が強い", "負荷を慎重に上げたい"],
                focus: CoachFocus(hypertrophy: 1, bodyRecomposition: 2, fatLoss: 1, nutrition: 2, movement: 4, recovery: 5, performance: 2),
                approach: ["主観状態と運動反応を確認", "量・強度・頻度を段階化", "異常時は中止を案内"],
                boundaries: ["治療やリハビリの代替をしない", "痛みを診断しない"],
                topFocusAreas: ["回復・運動復帰", "動作・活動性", "継続"]
            )
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

    var systemImage: String {
        switch self {
        case .diet: "scalemass"
        case .muscleGain: "dumbbell.fill"
        case .health: "heart.fill"
        case .bodyShape: "figure.mind.and.body"
        case .performance: "bolt.fill"
        }
    }

    var supportsFocusMuscles: Bool {
        self == .muscleGain || self == .bodyShape
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

enum OutcomeStyle: String, CaseIterable, Identifiable, Codable {
    case leanMuscular
    case vShape
    case balancedMuscularity
    case strengthFocused
    case steadyFatLoss
    case waistFocused
    case activeLifestyle
    case endurance
    case postureBalance
    case sportsPerformance
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leanMuscular: "引き締まった筋肉"
        case .vShape: "Vシェイプ"
        case .balancedMuscularity: "全身の筋量とバランス"
        case .strengthFocused: "筋力も重視"
        case .steadyFatLoss: "無理のない減量"
        case .waistFocused: "腹囲を整える"
        case .activeLifestyle: "動ける習慣"
        case .endurance: "持久力を高める"
        case .postureBalance: "姿勢と全身バランス"
        case .sportsPerformance: "競技パフォーマンス"
        case .custom: "自分で設定"
        }
    }

    var detail: String {
        switch self {
        case .leanMuscular: "筋肉の輪郭と動きやすさを両立する"
        case .vShape: "肩・背中・胸上部を中心に整える"
        case .balancedMuscularity: "脚を含む全身をバランスよく育てる"
        case .strengthFocused: "見た目と主要種目の重量を一緒に伸ばす"
        case .steadyFatLoss: "急がず、継続できるペースで体重を整える"
        case .waistFocused: "体重だけでなく腹囲の変化を重視する"
        case .activeLifestyle: "日常の活動量と運動習慣を安定させる"
        case .endurance: "長く動ける体力と回復力を育てる"
        case .postureBalance: "姿勢と部位バランスを意識して整える"
        case .sportsPerformance: "競技に必要な筋力・体力を優先する"
        case .custom: "自分の言葉で目標を設定する"
        }
    }

    var systemImage: String {
        switch self {
        case .leanMuscular: "figure.strengthtraining.functional"
        case .vShape: "figure.arms.open"
        case .balancedMuscularity: "figure.mixed.cardio"
        case .strengthFocused: "dumbbell.fill"
        case .steadyFatLoss: "chart.line.downtrend.xyaxis"
        case .waistFocused: "figure.core.training"
        case .activeLifestyle: "figure.walk"
        case .endurance: "figure.run"
        case .postureBalance: "figure.mind.and.body"
        case .sportsPerformance: "medal.fill"
        case .custom: "slider.horizontal.3"
        }
    }

    static func available(for goal: GoalType) -> [OutcomeStyle] {
        let styles: [OutcomeStyle] = switch goal {
        case .diet:
            [.steadyFatLoss, .waistFocused, .leanMuscular]
        case .muscleGain:
            [.leanMuscular, .vShape, .balancedMuscularity, .strengthFocused]
        case .health:
            [.activeLifestyle, .endurance, .postureBalance]
        case .bodyShape:
            [.leanMuscular, .vShape, .waistFocused, .postureBalance]
        case .performance:
            [.strengthFocused, .endurance, .sportsPerformance]
        }
        return styles + [.custom]
    }

    static func recommended(for goal: GoalType) -> OutcomeStyle {
        available(for: goal).first ?? .custom
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
    var coachPersona: CoachPersona
    var coachingStyle: CoachingStyle
    var outcomeStyle: OutcomeStyle
    var focusMuscles: [MuscleGroup]
    var customOutcomeText: String
    var weeklyTrainingDays: Int
    var preferredSessionMinutes: Int
    var availableEquipment: [Equipment]
    var heightCm: Double?
    var birthYear: Int?
    var sex: Sex
    var experienceLevel: ExperienceLevel
    var weightUnit: WeightUnit
    var nutritionGoals: NutritionGoals

    static let `default` = UserProfile(
        goalType: .bodyShape,
        coachType: .bodyRecomposition,
        coachPersona: .haru,
        coachingStyle: .analytical,
        outcomeStyle: .leanMuscular,
        focusMuscles: [],
        customOutcomeText: "",
        weeklyTrainingDays: 3,
        preferredSessionMinutes: 60,
        availableEquipment: Equipment.allCases,
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
        coachPersona: CoachPersona = .haru,
        coachingStyle: CoachingStyle? = nil,
        outcomeStyle: OutcomeStyle? = nil,
        focusMuscles: [MuscleGroup] = [],
        customOutcomeText: String = "",
        weeklyTrainingDays: Int = 3,
        preferredSessionMinutes: Int = 60,
        availableEquipment: [Equipment] = Equipment.allCases,
        heightCm: Double?,
        birthYear: Int?,
        sex: Sex,
        experienceLevel: ExperienceLevel,
        weightUnit: WeightUnit,
        nutritionGoals: NutritionGoals = .default
    ) {
        self.goalType = goalType
        self.coachType = coachType ?? CoachType.recommended(for: goalType)
        self.coachPersona = coachPersona
        self.coachingStyle = coachingStyle ?? coachPersona.recommendedStyle
        self.outcomeStyle = outcomeStyle ?? OutcomeStyle.recommended(for: goalType)
        self.focusMuscles = Array(Set(focusMuscles)).sorted { $0.displayName < $1.displayName }
        self.customOutcomeText = customOutcomeText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.weeklyTrainingDays = min(7, max(1, weeklyTrainingDays))
        self.preferredSessionMinutes = min(240, max(10, preferredSessionMinutes))
        self.availableEquipment = Self.normalizedEquipment(availableEquipment)
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
        coachPersona = try container.decodeIfPresent(CoachPersona.self, forKey: .coachPersona) ?? .haru
        coachingStyle = try container.decodeIfPresent(CoachingStyle.self, forKey: .coachingStyle)
            ?? coachPersona.recommendedStyle
        outcomeStyle = try container.decodeIfPresent(OutcomeStyle.self, forKey: .outcomeStyle)
            ?? OutcomeStyle.recommended(for: goalType)
        focusMuscles = try container.decodeIfPresent([MuscleGroup].self, forKey: .focusMuscles) ?? []
        customOutcomeText = try container.decodeIfPresent(String.self, forKey: .customOutcomeText) ?? ""
        weeklyTrainingDays = min(7, max(1, try container.decodeIfPresent(Int.self, forKey: .weeklyTrainingDays) ?? 3))
        preferredSessionMinutes = min(240, max(10, try container.decodeIfPresent(Int.self, forKey: .preferredSessionMinutes) ?? 60))
        availableEquipment = Self.normalizedEquipment(
            try container.decodeIfPresent([Equipment].self, forKey: .availableEquipment) ?? Equipment.allCases
        )
        heightCm = try container.decodeIfPresent(Double.self, forKey: .heightCm)
        birthYear = try container.decodeIfPresent(Int.self, forKey: .birthYear)
        sex = try container.decodeIfPresent(Sex.self, forKey: .sex) ?? defaults.sex
        experienceLevel = try container.decodeIfPresent(ExperienceLevel.self, forKey: .experienceLevel) ?? defaults.experienceLevel
        weightUnit = try container.decodeIfPresent(WeightUnit.self, forKey: .weightUnit) ?? defaults.weightUnit
        nutritionGoals = try container.decodeIfPresent(NutritionGoals.self, forKey: .nutritionGoals) ?? defaults.nutritionGoals
    }

    private static func normalizedEquipment(_ equipment: [Equipment]) -> [Equipment] {
        let selected = Set(equipment)
        let normalized = Equipment.allCases.filter(selected.contains)
        return normalized.isEmpty ? Equipment.allCases : normalized
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
