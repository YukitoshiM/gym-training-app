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
        case .fatLoss: L10n.string("domain_catalog.17e3947e1f94", fallback: "減量コーチ")
        case .hypertrophy: L10n.string("domain_catalog.a3e5c31bfea1", fallback: "筋肥大コーチ")
        case .strength: L10n.string("domain_catalog.3c0ba170d52c", fallback: "筋力向上コーチ")
        case .bodyRecomposition: L10n.string("domain_catalog.83e9d90bae18", fallback: "ボディメイクコーチ")
        case .wellness: L10n.string("domain_catalog.3ecf54bcfe2c", fallback: "健康維持コーチ")
        case .returnToTraining: L10n.string("domain_catalog.d9519ea3e1a9", fallback: "復帰コーチ")
        }
    }

    var characteristic: String {
        switch self {
        case .fatLoss: L10n.string("domain_catalog.27f7581e02a9", fallback: "筋量を守りながら、カロリー・体重傾向・空腹対策を現実的に調整")
        case .hypertrophy: L10n.string("domain_catalog.7f9c988574df", fallback: "トレーニング量、漸進性過負荷、PFC、回復を一体で評価")
        case .strength: L10n.string("domain_catalog.79f861a463c1", fallback: "重量・回数・RPE・技術から、疲労を管理して主要種目を伸ばす")
        case .bodyRecomposition: L10n.string("domain_catalog.28ab7663b1cf", fallback: "体重だけでなく腹囲・写真・筋力を合わせて体型変化を評価")
        case .wellness: L10n.string("domain_catalog.58d55c32f6a5", fallback: "完璧さより継続性を優先し、活動量・睡眠・無理のない運動を支援")
        case .returnToTraining: L10n.string("domain_catalog.8a82058b0b4a", fallback: "ブランク後の痛みと反応を確認し、負荷を段階的に戻す")
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
            ?? L10n.string("domain_catalog.c8e1c2433a37", fallback: "目的と記録状況に合わせて担当を選べます。")
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
                let focus = coach.expertiseProfile.topFocusAreas.prefix(2).joined(separator: L10n.string("domain_catalog.316f95cf480c", fallback: "と"))
                let reason = index == 0
                    ? L10n.string("domain_catalog.e56aceac59d8", fallback: "{{value1}}と「{{value2}}」に合わせ、{{value3}}を優先します。", values: [String(describing: profile.goalType.displayName), String(describing: outcome), String(describing: focus)])
                    : L10n.string("domain_catalog.1e1da1697fb2", fallback: "別案として、{{value1}}。{{value2}}を重視したい場合に合います。", values: [String(describing: coach.expertiseProfile.promise), String(describing: focus)])
                return CoachRecommendation(coachType: coach, reason: reason)
            }
    }
}

struct CoachRecommendation: Identifiable, Hashable {
    var coachType: CoachType
    var reason: String

    var id: CoachType { coachType }
}

enum CoachGender: String, Codable, Hashable {
    case woman
    case man

    var displayName: String {
        switch self {
        case .woman: L10n.string("domain_catalog.3a1fdfb57154", fallback: "女性")
        case .man: L10n.string("domain_catalog.def07f6a6e2e", fallback: "男性")
        }
    }
}

enum CoachPersona: String, CaseIterable, Identifiable, Codable {
    case hana
    case omar
    case camila
    case jun
    case ada
    case tomas
    case nia
    case mateo
    case sora
    case koa
    case leila
    case arun

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hana: "Hana"
        case .omar: "Omar"
        case .camila: "Camila"
        case .jun: "Jun"
        case .ada: "Ada"
        case .tomas: "Tomas"
        case .nia: "Nia"
        case .mateo: "Mateo"
        case .sora: "Sora"
        case .koa: "Koa"
        case .leila: "Leila"
        case .arun: "Arun"
        }
    }

    var assetName: String {
        switch self {
        case .hana: "CoachAvatarHana"
        case .omar: "CoachAvatarOmar"
        case .camila: "CoachAvatarCamila"
        case .jun: "CoachAvatarJun"
        case .ada: "CoachAvatarAda"
        case .tomas: "CoachAvatarTomas"
        case .nia: "CoachAvatarNia"
        case .mateo: "CoachAvatarMateo"
        case .sora: "CoachAvatarSora"
        case .koa: "CoachAvatarKoa"
        case .leila: "CoachAvatarLeila"
        case .arun: "CoachAvatarArun"
        }
    }

    var coachType: CoachType {
        switch self {
        case .hana, .omar: .fatLoss
        case .camila, .jun: .hypertrophy
        case .ada, .tomas: .strength
        case .nia, .mateo: .bodyRecomposition
        case .sora, .koa: .wellness
        case .leila, .arun: .returnToTraining
        }
    }

    var gender: CoachGender {
        switch self {
        case .hana, .camila, .ada, .nia, .sora, .leila: .woman
        case .omar, .jun, .tomas, .mateo, .koa, .arun: .man
        }
    }

    var bodyGoal: String {
        switch self {
        case .hana: L10n.string("domain_catalog.e358e462b285", fallback: "引き締まった健康体")
        case .omar: L10n.string("domain_catalog.252badb33931", fallback: "たくましさを残した健康体")
        case .camila: L10n.string("domain_catalog.5a3309c1a4ab", fallback: "力強く均整の取れた筋肉")
        case .jun: L10n.string("domain_catalog.5c95976db5e0", fallback: "健康的なVシェイプ")
        case .ada: L10n.string("domain_catalog.8c54b80a0189", fallback: "大きく力強い身体")
        case .tomas: L10n.string("domain_catalog.68e0568f4060", fallback: "厚みのある強い身体")
        case .nia: L10n.string("domain_catalog.9671cfa0696d", fallback: "動けるアスリート体型")
        case .mateo: L10n.string("domain_catalog.320305ccc66f", fallback: "細身で筋肉質")
        case .sora: L10n.string("domain_catalog.78aac0044cb3", fallback: "しなやかで良い姿勢")
        case .koa: L10n.string("domain_catalog.2718b93b2a7d", fallback: "自然な厚みのある健康体")
        case .leila: L10n.string("domain_catalog.cce9873e489c", fallback: "安定感のあるアクティブ体型")
        case .arun: L10n.string("domain_catalog.e456ae9699e2", fallback: "年齢に合った機能的な身体")
        }
    }

    var characterSummary: String {
        switch self {
        case .hana: L10n.string("domain_catalog.9b273c019479", fallback: "穏やかな戦略家。続く習慣へ小さく整える")
        case .omar: L10n.string("domain_catalog.08329aec4da4", fallback: "安心感のある現実派。難しい変化を生活へ落とし込む")
        case .camila: L10n.string("domain_catalog.9bedfff40213", fallback: "明るい技術屋。細かな上達を見つけて伸ばす")
        case .jun: L10n.string("domain_catalog.2494d7fd4a9d", fallback: "静かな分析家。記録から変更点を一つに絞る")
        case .ada: L10n.string("domain_catalog.a2265283c677", fallback: "冷静で決断が早い。安全と再現性を守る")
        case .tomas: L10n.string("domain_catalog.7063ae40e3ab", fallback: "穏やかな職人。基礎から強さを積み上げる")
        case .nia: L10n.string("domain_catalog.8f59183868a6", fallback: "温かく率直。数字と見た目を同じ期間で見る")
        case .mateo: L10n.string("domain_catalog.75c103d04abe", fallback: "好奇心の強い現実派。生活全体を組み替える")
        case .sora: L10n.string("domain_catalog.c3313a2b5bfb", fallback: "静かな観察者。睡眠と体調を優先する")
        case .koa: L10n.string("domain_catalog.a8a598371ccc", fallback: "聞き上手でおおらか。動く敷居を下げる")
        case .leila: L10n.string("domain_catalog.6ee5fb530229", fallback: "慎重で共感的。限界を明確にしながら戻す")
        case .arun: L10n.string("domain_catalog.87e1af9fe092", fallback: "辛抱強く正確。少ない量で終える判断も支える")
        }
    }

    var tagline: String {
        switch self {
        case .hana: L10n.string("domain_catalog.f34feca2145c", fallback: "明日も続く形に整えましょう")
        case .omar: L10n.string("domain_catalog.26a1032993dc", fallback: "続く置き換えを一つ決めよう")
        case .camila: L10n.string("domain_catalog.8e9ff0b8c79e", fallback: "次も伸びる一回にしましょう")
        case .jun: L10n.string("domain_catalog.0c8609aa1dea", fallback: "記録は静かに答えを出します")
        case .ada: L10n.string("domain_catalog.4c3c32ef7d36", fallback: "再現できる強さを作りましょう")
        case .tomas: L10n.string("domain_catalog.7478c7d73bb1", fallback: "強さは急がなくても逃げません")
        case .nia: L10n.string("domain_catalog.55b287d1dab0", fallback: "体重だけで変化を決めません")
        case .mateo: L10n.string("domain_catalog.53bdd01e0cdb", fallback: "見た目と動ける身体を整えよう")
        case .sora: L10n.string("domain_catalog.09dc95770c76", fallback: "整えるだけでも十分前進です")
        case .koa: L10n.string("domain_catalog.b90323da299e", fallback: "動ける日を増やそう")
        case .leila: L10n.string("domain_catalog.2a7953128385", fallback: "止める判断も強さです")
        case .arun: L10n.string("domain_catalog.0e78e214dcb3", fallback: "戻れる速さが最適な速さです")
        }
    }

    var coachingTone: String {
        recommendedStyle.promptDescription
    }

    var recommendedStyle: CoachingStyle {
        switch self {
        case .hana, .tomas, .arun: .calm
        case .omar, .ada: .direct
        case .jun, .mateo: .analytical
        case .camila, .nia, .koa: .encouraging
        case .sora, .leila: .cautious
        }
    }

    static func options(for coachType: CoachType) -> [CoachPersona] {
        allCases.filter { $0.coachType == coachType }
    }

    static func defaultPersona(for coachType: CoachType) -> CoachPersona {
        options(for: coachType).first ?? .nia
    }

    func replacement(for coachType: CoachType) -> CoachPersona {
        guard self.coachType != coachType else { return self }
        return Self.options(for: coachType).first { $0.gender == gender }
            ?? Self.defaultPersona(for: coachType)
    }

    static func migrated(rawValue: String?, coachType: CoachType) -> CoachPersona {
        if let rawValue, let persona = CoachPersona(rawValue: rawValue) {
            return persona.replacement(for: coachType)
        }

        let legacyGender: CoachGender? = switch rawValue {
        case "aiko", "maya", "emi": .woman
        case "ren", "ken": .man
        default: nil
        }
        if let legacyGender,
           let match = options(for: coachType).first(where: { $0.gender == legacyGender }) {
            return match
        }
        return defaultPersona(for: coachType)
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
        case .calm: L10n.string("domain_catalog.0e4c8a4fa2e7", fallback: "穏やか")
        case .direct: L10n.string("domain_catalog.5c32efe378e8", fallback: "率直")
        case .analytical: L10n.string("domain_catalog.7ad7d18bfcfe", fallback: "論理的")
        case .encouraging: L10n.string("domain_catalog.bb95842e6bcc", fallback: "鼓舞")
        case .cautious: L10n.string("domain_catalog.e1efeefe80f7", fallback: "慎重")
        }
    }

    var promptDescription: String {
        switch self {
        case .calm: L10n.string("domain_catalog.deb749236745", fallback: "穏やかで現実的。小さな継続を具体的に認める")
        case .direct: L10n.string("domain_catalog.27d78815325a", fallback: "明るく率直。次に伸ばす一点を明確にする")
        case .analytical: L10n.string("domain_catalog.573b24a5dd9c", fallback: "落ち着いて論理的。数値と体感を分けて説明する")
        case .encouraging: L10n.string("domain_catalog.086cb45cf7dc", fallback: "力強く親しみやすい。達成を自信につなげる")
        case .cautious: L10n.string("domain_catalog.894b7cbd839d", fallback: "温かく慎重。焦らず安全に前進できる言葉を選ぶ")
        }
    }

    var openingLine: String {
        switch self {
        case .calm:
            L10n.string("domain_catalog.670b1b812dc2", fallback: "急がなくて大丈夫です。記録を見ながら、今日できることを一緒に決めましょう。")
        case .direct:
            L10n.string("domain_catalog.0eb540ed09f8", fallback: "記録から、今いちばん効果的な一手をはっきりさせましょう。")
        case .analytical:
            L10n.string("domain_catalog.1c530e00e8cf", fallback: "数値と体感を分けて、次の一手を整理しましょう。")
        case .encouraging:
            L10n.string("domain_catalog.493865938e62", fallback: "できていることから確認して、次の一歩につなげましょう。")
        case .cautious:
            L10n.string("domain_catalog.6e22f6c1c05e", fallback: "無理のない範囲を確認しながら、少しずつ進めましょう。")
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
                promise: L10n.string("domain_catalog.3fe0220dd26a", fallback: "無理なく落とし、戻りにくい習慣を作る"),
                recommendedFor: [L10n.string("domain_catalog.279d6a742762", fallback: "減量を始めたい"), L10n.string("domain_catalog.13853e814f8f", fallback: "食事管理が続かない"), L10n.string("domain_catalog.9e625c0f3f20", fallback: "腹囲も整えたい")],
                focus: CoachFocus(hypertrophy: 2, bodyRecomposition: 4, fatLoss: 5, nutrition: 5, movement: 3, recovery: 3, performance: 1),
                approach: [L10n.string("domain_catalog.483f3d1f2776", fallback: "週平均で体重傾向を見る"), L10n.string("domain_catalog.907731db04ef", fallback: "食事と活動量を小さく調整"), L10n.string("domain_catalog.d76841a395cb", fallback: "空腹と継続性を確認")],
                boundaries: [L10n.string("domain_catalog.5599e1303468", fallback: "急激な減量を勧めない"), L10n.string("domain_catalog.b181ea2552a3", fallback: "医療的な診断をしない")],
                topFocusAreas: [L10n.string("domain_catalog.18eaffdeb72d", fallback: "減量"), L10n.string("domain_catalog.607b7ba39582", fallback: "食事・栄養"), L10n.string("domain_catalog.8f9666833a49", fallback: "体型改善")]
            )
        case .hypertrophy:
            CoachExpertiseProfile(
                id: type,
                promise: L10n.string("domain_catalog.e5fa769d296f", fallback: "回復できる量で筋肉を着実に増やす"),
                recommendedFor: [L10n.string("domain_catalog.3e66fb6a90f8", fallback: "筋量を増やしたい"), L10n.string("domain_catalog.32dd39a34212", fallback: "部位を重点的に伸ばしたい"), L10n.string("domain_catalog.096953528159", fallback: "停滞を見直したい")],
                focus: CoachFocus(hypertrophy: 5, bodyRecomposition: 4, fatLoss: 1, nutrition: 4, movement: 2, recovery: 4, performance: 3),
                approach: [L10n.string("domain_catalog.fdc6190c332c", fallback: "ボリュームと漸進性を確認"), L10n.string("domain_catalog.f69267553023", fallback: "PFCと睡眠を合わせて評価"), L10n.string("domain_catalog.880abc0737e1", fallback: "部位バランスを調整")],
                boundaries: [L10n.string("domain_catalog.d6cdc9900460", fallback: "回復不能な量を増やさない"), L10n.string("domain_catalog.0f85d83ff7e6", fallback: "見た目だけで体脂肪率を断定しない")],
                topFocusAreas: [L10n.string("domain_catalog.93167d5b2a06", fallback: "筋肥大"), L10n.string("domain_catalog.164854e9197e", fallback: "回復"), L10n.string("domain_catalog.607b7ba39582", fallback: "食事・栄養")]
            )
        case .strength:
            CoachExpertiseProfile(
                id: type,
                promise: L10n.string("domain_catalog.1620145908e9", fallback: "疲労を管理しながら扱える力を伸ばす"),
                recommendedFor: [L10n.string("domain_catalog.b38b92363a48", fallback: "主要種目を伸ばしたい"), L10n.string("domain_catalog.8a8b4730b070", fallback: "PRを狙いたい"), L10n.string("domain_catalog.c82e13ae5f18", fallback: "競技力を高めたい")],
                focus: CoachFocus(hypertrophy: 3, bodyRecomposition: 1, fatLoss: 1, nutrition: 2, movement: 4, recovery: 4, performance: 5),
                approach: [L10n.string("domain_catalog.4eaa2c3979db", fallback: "重量・回数・RPEを比較"), L10n.string("domain_catalog.43f8bf1ae07a", fallback: "疲労を見て負荷を調整"), L10n.string("domain_catalog.d550531520da", fallback: "PR傾向を長期で確認")],
                boundaries: [L10n.string("domain_catalog.0cc2ae8526d1", fallback: "危険な最大挙上を強制しない"), L10n.string("domain_catalog.4483abaf3a46", fallback: "フォームや怪我を診断しない")],
                topFocusAreas: [L10n.string("domain_catalog.db056d12f9b6", fallback: "筋力・競技力"), L10n.string("domain_catalog.164854e9197e", fallback: "回復"), L10n.string("domain_catalog.bbba963ea7a4", fallback: "動作・活動性")]
            )
        case .bodyRecomposition:
            CoachExpertiseProfile(
                id: type,
                promise: L10n.string("domain_catalog.59ffb3a17375", fallback: "数字と見た目の両方から身体を整える"),
                recommendedFor: [L10n.string("domain_catalog.b0a38eba9e96", fallback: "見た目を変えたい"), L10n.string("domain_catalog.06fc88ece224", fallback: "体重だけでは判断しづらい"), L10n.string("domain_catalog.6b6098a03f15", fallback: "筋肉を保って絞りたい")],
                focus: CoachFocus(hypertrophy: 4, bodyRecomposition: 5, fatLoss: 4, nutrition: 4, movement: 3, recovery: 3, performance: 2),
                approach: [L10n.string("domain_catalog.1bd26ac102fb", fallback: "写真・腹囲・体重を同期間で比較"), L10n.string("domain_catalog.8cfc11471c7f", fallback: "筋力の維持も確認"), L10n.string("domain_catalog.2fc7ca18b2ba", fallback: "次の一手を少数に絞る")],
                boundaries: [L10n.string("domain_catalog.8a7c08ed1b16", fallback: "写真から数値を断定しない"), L10n.string("domain_catalog.eb4094333313", fallback: "写っていない部位を推測しない")],
                topFocusAreas: [L10n.string("domain_catalog.8f9666833a49", fallback: "体型改善"), L10n.string("domain_catalog.93167d5b2a06", fallback: "筋肥大"), L10n.string("domain_catalog.18eaffdeb72d", fallback: "減量")]
            )
        case .wellness:
            CoachExpertiseProfile(
                id: type,
                promise: L10n.string("domain_catalog.f798938f0c2a", fallback: "体調を崩さず、動ける毎日を続ける"),
                recommendedFor: [L10n.string("domain_catalog.7f998a38e9ec", fallback: "健康習慣を作りたい"), L10n.string("domain_catalog.d564c551ea76", fallback: "運動初心者"), L10n.string("domain_catalog.37117afd784a", fallback: "無理なく続けたい")],
                focus: CoachFocus(hypertrophy: 1, bodyRecomposition: 3, fatLoss: 2, nutrition: 3, movement: 5, recovery: 5, performance: 1),
                approach: [L10n.string("domain_catalog.01e37dd99f83", fallback: "睡眠と疲労を優先"), L10n.string("domain_catalog.356d05aa6e57", fallback: "歩数と軽い運動を積み上げ"), L10n.string("domain_catalog.a619e7918f83", fallback: "未達を責めず翌日へ調整")],
                boundaries: [L10n.string("domain_catalog.6ce192c3f346", fallback: "健康状態を診断しない"), L10n.string("domain_catalog.b0879cc1fb63", fallback: "体調不良時に運動を強制しない")],
                topFocusAreas: [L10n.string("domain_catalog.164854e9197e", fallback: "回復"), L10n.string("domain_catalog.bbba963ea7a4", fallback: "動作・活動性"), L10n.string("domain_catalog.607b7ba39582", fallback: "食事・栄養")]
            )
        case .returnToTraining:
            CoachExpertiseProfile(
                id: type,
                promise: L10n.string("domain_catalog.bd9cd11d98b4", fallback: "焦らず段階的に運動へ戻る"),
                recommendedFor: [L10n.string("domain_catalog.08989de187ef", fallback: "ブランクから戻りたい"), L10n.string("domain_catalog.e8c66116952a", fallback: "疲労が強い"), L10n.string("domain_catalog.4a930a07ceee", fallback: "負荷を慎重に上げたい")],
                focus: CoachFocus(hypertrophy: 1, bodyRecomposition: 2, fatLoss: 1, nutrition: 2, movement: 4, recovery: 5, performance: 2),
                approach: [L10n.string("domain_catalog.f48399266fad", fallback: "主観状態と運動反応を確認"), L10n.string("domain_catalog.cd15ad9d635f", fallback: "量・強度・頻度を段階化"), L10n.string("domain_catalog.7d432687472b", fallback: "異常時は中止を案内")],
                boundaries: [L10n.string("domain_catalog.0e80f2603837", fallback: "治療やリハビリの代替をしない"), L10n.string("domain_catalog.d84c7a574f52", fallback: "痛みを診断しない")],
                topFocusAreas: [L10n.string("domain_catalog.797274b60003", fallback: "回復・運動復帰"), L10n.string("domain_catalog.bbba963ea7a4", fallback: "動作・活動性"), L10n.string("domain_catalog.11458957af67", fallback: "継続")]
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
        case .diet: L10n.string("domain_catalog.87656b607ca4", fallback: "ダイエット")
        case .muscleGain: L10n.string("domain_catalog.93167d5b2a06", fallback: "筋肥大")
        case .health: L10n.string("domain_catalog.1ae4e72bc475", fallback: "健康維持")
        case .bodyShape: L10n.string("domain_catalog.8f9666833a49", fallback: "体型改善")
        case .performance: L10n.string("domain_catalog.2ced63518185", fallback: "競技力向上")
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
            L10n.string("domain_catalog.a73dafb59621", fallback: "体重・腹囲・食事を記録する")
        case .muscleGain:
            L10n.string("domain_catalog.7936fdc099ed", fallback: "トレーニング量とたんぱく質を確認する")
        case .health:
            L10n.string("domain_catalog.eac1bac2c287", fallback: "体重・腹囲・運動頻度を確認する")
        case .bodyShape:
            L10n.string("domain_catalog.026b630cba03", fallback: "体型写真と腹囲を記録する")
        case .performance:
            L10n.string("domain_catalog.8921fea36b9f", fallback: "疲労度と練習量をメモする")
        }
    }

    var insightTitle: String {
        switch self {
        case .diet: L10n.string("domain_catalog.562d2e325099", fallback: "減量の確認ポイント")
        case .muscleGain: L10n.string("domain_catalog.681685c3cfc7", fallback: "筋肥大の確認ポイント")
        case .health: L10n.string("domain_catalog.d25c4cd334d9", fallback: "健康維持の確認ポイント")
        case .bodyShape: L10n.string("domain_catalog.05748bf04331", fallback: "体型改善の確認ポイント")
        case .performance: L10n.string("domain_catalog.73b63dc1b17e", fallback: "競技力向上の確認ポイント")
        }
    }

    var insightBody: String {
        switch self {
        case .diet:
            L10n.string("domain_catalog.6e6324cfc621", fallback: "体重だけでなく腹囲と食事記録を合わせて見ます。横ばいでも腹囲が落ちていれば進捗ありです。")
        case .muscleGain:
            L10n.string("domain_catalog.da5a773cf49d", fallback: "体重、トレーニングボリューム、種目別重量を見ます。前回実績を使って少しずつ伸ばします。")
        case .health:
            L10n.string("domain_catalog.0d4594b21e65", fallback: "体重、腹囲、運動頻度を無理なく維持します。記録が途切れないことを優先します。")
        case .bodyShape:
            L10n.string("domain_catalog.38480060807b", fallback: "腹囲と体型写真の変化を重視します。写真は同じ角度、同じ光で撮ると比較しやすくなります。")
        case .performance:
            L10n.string("domain_catalog.818335950a33", fallback: "体重、筋トレ量、疲労度、睡眠を見ます。疲労が高い日は無理に伸ばさない設計にします。")
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
        case .leanMuscular: L10n.string("domain_catalog.652504e347e3", fallback: "引き締まった筋肉")
        case .vShape: L10n.string("domain_catalog.05ab5da975bb", fallback: "Vシェイプ")
        case .balancedMuscularity: L10n.string("domain_catalog.55d772a6e8ff", fallback: "全身の筋量とバランス")
        case .strengthFocused: L10n.string("domain_catalog.c55b2ba8a1d6", fallback: "筋力も重視")
        case .steadyFatLoss: L10n.string("domain_catalog.9b30fcdd1dfd", fallback: "無理のない減量")
        case .waistFocused: L10n.string("domain_catalog.e692c8226d36", fallback: "腹囲を整える")
        case .activeLifestyle: L10n.string("domain_catalog.97a1cb44cf8f", fallback: "動ける習慣")
        case .endurance: L10n.string("domain_catalog.f08567f16af7", fallback: "持久力を高める")
        case .postureBalance: L10n.string("domain_catalog.bdad4573f65a", fallback: "姿勢と全身バランス")
        case .sportsPerformance: L10n.string("domain_catalog.6e1a813d538e", fallback: "競技パフォーマンス")
        case .custom: L10n.string("domain_catalog.873302c4b236", fallback: "自分で設定")
        }
    }

    var detail: String {
        switch self {
        case .leanMuscular: L10n.string("domain_catalog.edf60d12c07a", fallback: "筋肉の輪郭と動きやすさを両立する")
        case .vShape: L10n.string("domain_catalog.01cf3683ebe8", fallback: "肩・背中・胸上部を中心に整える")
        case .balancedMuscularity: L10n.string("domain_catalog.dc0e85fb5bb9", fallback: "脚を含む全身をバランスよく育てる")
        case .strengthFocused: L10n.string("domain_catalog.a76ee7ffbac7", fallback: "見た目と主要種目の重量を一緒に伸ばす")
        case .steadyFatLoss: L10n.string("domain_catalog.9c22fcf178d4", fallback: "急がず、継続できるペースで体重を整える")
        case .waistFocused: L10n.string("domain_catalog.3bb27f474dc3", fallback: "体重だけでなく腹囲の変化を重視する")
        case .activeLifestyle: L10n.string("domain_catalog.5ec6b5bcf76b", fallback: "日常の活動量と運動習慣を安定させる")
        case .endurance: L10n.string("domain_catalog.479cc8f98eb5", fallback: "長く動ける体力と回復力を育てる")
        case .postureBalance: L10n.string("domain_catalog.20ba864f955c", fallback: "姿勢と部位バランスを意識して整える")
        case .sportsPerformance: L10n.string("domain_catalog.1bfcd928cce8", fallback: "競技に必要な筋力・体力を優先する")
        case .custom: L10n.string("domain_catalog.acf28c504ce2", fallback: "自分の言葉で目標を設定する")
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
        case .unspecified: L10n.string("domain_catalog.48a43e821e28", fallback: "未設定")
        case .male: L10n.string("domain_catalog.def07f6a6e2e", fallback: "男性")
        case .female: L10n.string("domain_catalog.3a1fdfb57154", fallback: "女性")
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
        case .beginner: L10n.string("domain_catalog.1957758467a5", fallback: "初心者")
        case .intermediate: L10n.string("domain_catalog.dcfab50b8a2c", fallback: "中級者")
        case .advanced: L10n.string("domain_catalog.572082fe89e3", fallback: "上級者")
        }
    }
}

enum WeightUnit: String, CaseIterable, Identifiable, Codable {
    case kg
    case lb

    var id: String { rawValue }

    static func defaultValue(for locale: Locale) -> WeightUnit {
        locale.measurementSystem == .us ? .lb : .kg
    }

    static var regionalDefault: WeightUnit {
        defaultValue(for: .current)
    }

    var displayName: String {
        switch self {
        case .kg: "kg"
        case .lb: "lb"
        }
    }
}

enum ExerciseActivityLevel: String, CaseIterable, Identifiable, Codable {
    case notAnswered
    case notRegular
    case regular

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notAnswered:
            AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered")
        case .notRegular:
            AppLanguagePreference.bilingual(japanese: "定期的にはしていない", english: "Not regularly active")
        case .regular:
            AppLanguagePreference.bilingual(japanese: "週3日以上を3か月程度", english: "3+ days/week for about 3 months")
        }
    }
}

enum PlannedExerciseIntensity: String, CaseIterable, Identifiable, Codable {
    case notAnswered
    case lightToModerate
    case vigorous

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notAnswered:
            AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered")
        case .lightToModerate:
            AppLanguagePreference.bilingual(japanese: "軽め〜中程度", english: "Light to moderate")
        case .vigorous:
            AppLanguagePreference.bilingual(japanese: "高強度も行う", english: "Includes vigorous exercise")
        }
    }
}

enum TrainingSafetyStatus: String, CaseIterable, Identifiable, Codable {
    case notAnswered
    case noKnownConcerns
    case hasConsiderations
    case followsProfessionalGuidance
    case preferNotToSay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notAnswered:
            AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered")
        case .noKnownConcerns:
            AppLanguagePreference.bilingual(japanese: "現在、特にない", english: "No known concerns")
        case .hasConsiderations:
            AppLanguagePreference.bilingual(japanese: "配慮したいことがある", english: "I have considerations")
        case .followsProfessionalGuidance:
            AppLanguagePreference.bilingual(japanese: "医師・専門家の指示がある", english: "I follow professional guidance")
        case .preferNotToSay:
            AppLanguagePreference.bilingual(japanese: "回答しない", english: "Prefer not to say")
        }
    }
}

enum TrainingHealthConsideration: String, CaseIterable, Identifiable, Codable {
    case cardiovascularMetabolicOrRenalCondition
    case chestPainOrPressure
    case unusualBreathlessness
    case dizzinessOrFainting
    case palpitations
    case recentInjuryOrSurgery
    case jointOrMuscleDiscomfort
    case balanceOrMobility
    case pregnancyOrPostpartum
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cardiovascularMetabolicOrRenalCondition:
            AppLanguagePreference.bilingual(
                japanese: "心臓・血管、糖代謝、腎臓の診断・治療中",
                english: "Cardiovascular, metabolic, or kidney condition"
            )
        case .chestPainOrPressure:
            AppLanguagePreference.bilingual(japanese: "運動時の胸の痛み・圧迫感", english: "Chest pain or pressure with activity")
        case .unusualBreathlessness:
            AppLanguagePreference.bilingual(japanese: "軽い動作でも強い息切れ", english: "Unusual breathlessness with light activity")
        case .dizzinessOrFainting:
            AppLanguagePreference.bilingual(japanese: "めまい・失神", english: "Dizziness or fainting")
        case .palpitations:
            AppLanguagePreference.bilingual(japanese: "運動時の強い動悸・不整脈", english: "Strong palpitations or irregular heartbeat with activity")
        case .recentInjuryOrSurgery:
            AppLanguagePreference.bilingual(japanese: "最近のけが・手術", english: "Recent injury or surgery")
        case .jointOrMuscleDiscomfort:
            AppLanguagePreference.bilingual(japanese: "関節・筋肉の痛みや違和感", english: "Joint or muscle pain or discomfort")
        case .balanceOrMobility:
            AppLanguagePreference.bilingual(japanese: "バランス・移動の制限", english: "Balance or mobility limitation")
        case .pregnancyOrPostpartum:
            AppLanguagePreference.bilingual(japanese: "妊娠中・産後", english: "Pregnancy or postpartum")
        case .other:
            AppLanguagePreference.bilingual(japanese: "その他", english: "Other")
        }
    }

    var requiresProfessionalGuidance: Bool {
        switch self {
        case .cardiovascularMetabolicOrRenalCondition,
             .chestPainOrPressure,
             .unusualBreathlessness,
             .dizzinessOrFainting,
             .palpitations,
             .recentInjuryOrSurgery:
            true
        case .jointOrMuscleDiscomfort, .balanceOrMobility, .pregnancyOrPostpartum, .other:
            false
        }
    }

}

enum TypicalSleepRange: String, CaseIterable, Identifiable, Codable {
    case notAnswered
    case underSix
    case sixToSeven
    case sevenToNine
    case overNine
    case irregular

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notAnswered: AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered")
        case .underSix: AppLanguagePreference.bilingual(japanese: "6時間未満", english: "Under 6 hours")
        case .sixToSeven: AppLanguagePreference.bilingual(japanese: "6〜7時間", english: "6–7 hours")
        case .sevenToNine: AppLanguagePreference.bilingual(japanese: "7〜9時間", english: "7–9 hours")
        case .overNine: AppLanguagePreference.bilingual(japanese: "9時間以上", english: "9+ hours")
        case .irregular: AppLanguagePreference.bilingual(japanese: "日によって大きく変わる", english: "Varies widely")
        }
    }
}

enum GoalIntakeFocus: String, CaseIterable, Identifiable, Codable {
    case notAnswered
    case sustainableWeightLoss
    case mealConsistency
    case waistReduction
    case muscleSize
    case strengthProgress
    case recoveryCapacity
    case activityHabit
    case cardiovascularFitness
    case mobility
    case sleepAndEnergy
    case physiqueChange
    case postureAndBalance
    case muscleBalance
    case strengthAndPower
    case endurance
    case performanceRecovery

    var id: String { rawValue }

    static func options(for goal: GoalType) -> [GoalIntakeFocus] {
        switch goal {
        case .diet: [.sustainableWeightLoss, .mealConsistency, .waistReduction]
        case .muscleGain: [.muscleSize, .strengthProgress, .recoveryCapacity]
        case .health: [.activityHabit, .cardiovascularFitness, .mobility, .sleepAndEnergy]
        case .bodyShape: [.physiqueChange, .postureAndBalance, .muscleBalance]
        case .performance: [.strengthAndPower, .endurance, .performanceRecovery]
        }
    }

    var displayName: String {
        switch self {
        case .notAnswered: AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered")
        case .sustainableWeightLoss: AppLanguagePreference.bilingual(japanese: "無理のない体重減", english: "Sustainable weight loss")
        case .mealConsistency: AppLanguagePreference.bilingual(japanese: "食事の安定", english: "Consistent eating habits")
        case .waistReduction: AppLanguagePreference.bilingual(japanese: "腹囲を整える", english: "Reduce waist size")
        case .muscleSize: AppLanguagePreference.bilingual(japanese: "筋肉量", english: "Muscle size")
        case .strengthProgress: AppLanguagePreference.bilingual(japanese: "重量・筋力", english: "Strength progress")
        case .recoveryCapacity: AppLanguagePreference.bilingual(japanese: "回復と疲労管理", english: "Recovery and fatigue")
        case .activityHabit: AppLanguagePreference.bilingual(japanese: "運動習慣", english: "Activity habit")
        case .cardiovascularFitness: AppLanguagePreference.bilingual(japanese: "心肺体力", english: "Cardiorespiratory fitness")
        case .mobility: AppLanguagePreference.bilingual(japanese: "動きやすさ", english: "Mobility")
        case .sleepAndEnergy: AppLanguagePreference.bilingual(japanese: "睡眠と日中の調子", english: "Sleep and daily energy")
        case .physiqueChange: AppLanguagePreference.bilingual(japanese: "写真で分かる体型変化", english: "Visible physique change")
        case .postureAndBalance: AppLanguagePreference.bilingual(japanese: "姿勢と左右差", english: "Posture and symmetry")
        case .muscleBalance: AppLanguagePreference.bilingual(japanese: "部位のバランス", english: "Muscle balance")
        case .strengthAndPower: AppLanguagePreference.bilingual(japanese: "筋力・パワー", english: "Strength and power")
        case .endurance: AppLanguagePreference.bilingual(japanese: "持久力", english: "Endurance")
        case .performanceRecovery: AppLanguagePreference.bilingual(japanese: "競技負荷と回復", english: "Training load and recovery")
        }
    }
}

enum NutritionGuidanceMode: String, CaseIterable, Identifiable, Codable {
    case notAnswered
    case standard
    case avoidCalorieFocus
    case followProfessionalPlan
    case preferNotToSay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notAnswered: AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered")
        case .standard: AppLanguagePreference.bilingual(japanese: "通常の食事目安でよい", english: "Standard nutrition guidance")
        case .avoidCalorieFocus: AppLanguagePreference.bilingual(japanese: "カロリー・体重中心の助言は控えたい", english: "Avoid calorie- or weight-focused guidance")
        case .followProfessionalPlan: AppLanguagePreference.bilingual(japanese: "専門家の食事方針を優先", english: "Follow a professional nutrition plan")
        case .preferNotToSay: AppLanguagePreference.bilingual(japanese: "回答しない", english: "Prefer not to say")
        }
    }
}

struct HealthIntakeProfile: Codable, Equatable {
    var activityLevel: ExerciseActivityLevel
    var plannedIntensity: PlannedExerciseIntensity
    var safetyStatus: TrainingSafetyStatus
    var considerations: [TrainingHealthConsideration]
    var typicalSleep: TypicalSleepRange
    var goalFocus: GoalIntakeFocus
    var nutritionGuidanceMode: NutritionGuidanceMode
    var otherTrainingDays: Int?
    var sportOrActivity: String
    var note: String

    static let `default` = HealthIntakeProfile(
        activityLevel: .notAnswered,
        plannedIntensity: .notAnswered,
        safetyStatus: .notAnswered,
        considerations: [],
        typicalSleep: .notAnswered,
        goalFocus: .notAnswered,
        nutritionGuidanceMode: .notAnswered,
        otherTrainingDays: nil,
        sportOrActivity: "",
        note: ""
    )

    var isComplete: Bool {
        activityLevel != .notAnswered
            && plannedIntensity != .notAnswered
            && safetyStatus != .notAnswered
            && typicalSleep != .notAnswered
            && goalFocus != .notAnswered
    }

    var requiresProfessionalGuidance: Bool {
        safetyStatus == .followsProfessionalGuidance
            || considerations.contains(where: \.requiresProfessionalGuidance)
            || nutritionGuidanceMode == .followProfessionalPlan
    }

    var requiresLoadAdjustment: Bool {
        safetyStatus == .hasConsiderations
            || safetyStatus == .followsProfessionalGuidance
            || !considerations.isEmpty
    }

    var hasWarningSymptoms: Bool {
        considerations.contains { consideration in
            switch consideration {
            case .chestPainOrPressure, .unusualBreathlessness, .dizzinessOrFainting, .palpitations:
                true
            default:
                false
            }
        }
    }

    func normalized(for goal: GoalType) -> HealthIntakeProfile {
        var result = self
        result.considerations = TrainingHealthConsideration.allCases.filter(Set(considerations).contains)
        result.goalFocus = GoalIntakeFocus.options(for: goal).contains(goalFocus) ? goalFocus : .notAnswered
        if ![GoalType.diet, .bodyShape].contains(goal) {
            result.nutritionGuidanceMode = .notAnswered
        }
        if goal != .performance {
            result.otherTrainingDays = nil
            result.sportOrActivity = ""
        } else {
            result.otherTrainingDays = result.otherTrainingDays.map { min(14, max(0, $0)) }
            result.sportOrActivity = String(result.sportOrActivity.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        }
        result.note = String(result.note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        if result.safetyStatus == .noKnownConcerns || result.safetyStatus == .preferNotToSay {
            result.considerations = []
        }
        return result
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
    var healthIntake: HealthIntakeProfile

    static let `default` = UserProfile(
        goalType: .bodyShape,
        coachType: .bodyRecomposition,
        coachPersona: .nia,
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
        weightUnit: .regionalDefault,
        nutritionGoals: .default,
        healthIntake: .default
    )

    init(
        goalType: GoalType,
        coachType: CoachType? = nil,
        coachPersona: CoachPersona? = nil,
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
        nutritionGoals: NutritionGoals = .default,
        healthIntake: HealthIntakeProfile = .default
    ) {
        self.goalType = goalType
        let resolvedCoachType = coachType ?? CoachType.recommended(for: goalType)
        let resolvedPersona = coachPersona?.replacement(for: resolvedCoachType)
            ?? CoachPersona.defaultPersona(for: resolvedCoachType)
        self.coachType = resolvedCoachType
        self.coachPersona = resolvedPersona
        self.coachingStyle = coachingStyle ?? resolvedPersona.recommendedStyle
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
        self.healthIntake = healthIntake.normalized(for: goalType)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default
        goalType = try container.decodeIfPresent(GoalType.self, forKey: .goalType) ?? defaults.goalType
        coachType = try container.decodeIfPresent(CoachType.self, forKey: .coachType)
            ?? CoachType.recommended(for: goalType)
        let storedPersona = try container.decodeIfPresent(String.self, forKey: .coachPersona)
        coachPersona = CoachPersona.migrated(rawValue: storedPersona, coachType: coachType)
        let storedCoachingStyle = try container.decodeIfPresent(CoachingStyle.self, forKey: .coachingStyle)
        coachingStyle = storedCoachingStyle
            ?? (storedPersona == nil ? defaults.coachingStyle : coachPersona.recommendedStyle)
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
        healthIntake = try container.decodeIfPresent(HealthIntakeProfile.self, forKey: .healthIntake) ?? .default
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
