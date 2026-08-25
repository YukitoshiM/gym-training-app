import Foundation

private func compactAIText(_ text: String, maximumCharacters: Int) -> String {
    guard text.count > maximumCharacters else { return text }
    let marker = " … "
    let available = max(2, maximumCharacters - marker.count)
    let headCount = max(1, Int(Double(available) * 0.65))
    let tailCount = max(1, available - headCount)
    return String(text.prefix(headCount)) + marker + String(text.suffix(tailCount))
}

enum CoachChatRole: String, Codable, Hashable {
    case user
    case assistant
}

struct CoachChatMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var role: CoachChatRole
    var content: String
    var createdAt: Date
    var evidence: [CoachEvidenceCitation]

    init(
        id: UUID = UUID(),
        role: CoachChatRole,
        content: String,
        createdAt: Date = Date(),
        evidence: [CoachEvidenceCitation] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt
        case evidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(CoachChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        evidence = try container.decodeIfPresent(
            [CoachEvidenceCitation].self,
            forKey: .evidence
        ) ?? []
    }
}

struct CoachEvidenceCitation: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var year: Int?
    var studyType: String
    var confidence: String
    var url: String
    var doi: String
    var relevance: Double
    var sourceScope: String
    var evidenceSummary: String
    var population: String
    var intervention: String
    var outcomes: [String]
    var limitations: [String]
    var applicabilityScore: Double
    var applicabilityLabel: String
    var versionStatus: String
    var conclusionConsistency: String
    var newerEvidenceNote: String
    var fullTextLicense: String
    var sourceDetailURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case studyType = "study_type"
        case confidence
        case url
        case doi
        case relevance
        case sourceScope = "source_scope"
        case evidenceSummary = "evidence_summary"
        case population
        case intervention
        case outcomes
        case limitations
        case applicabilityScore = "applicability_score"
        case applicabilityLabel = "applicability_label"
        case versionStatus = "version_status"
        case conclusionConsistency = "conclusion_consistency"
        case newerEvidenceNote = "newer_evidence_note"
        case fullTextLicense = "full_text_license"
        case sourceDetailURL = "source_detail_url"
    }

    init(
        id: String,
        title: String,
        year: Int?,
        studyType: String,
        confidence: String,
        url: String,
        doi: String,
        relevance: Double,
        sourceScope: String = "abstract",
        evidenceSummary: String = "",
        population: String = "",
        intervention: String = "",
        outcomes: [String] = [],
        limitations: [String] = [],
        applicabilityScore: Double = 0.5,
        applicabilityLabel: String = "unclear",
        versionStatus: String = "current",
        conclusionConsistency: String = "unknown",
        newerEvidenceNote: String = ""
        , fullTextLicense: String = ""
        , sourceDetailURL: String = ""
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.studyType = studyType
        self.confidence = confidence
        self.url = url
        self.doi = doi
        self.relevance = relevance
        self.sourceScope = sourceScope
        self.evidenceSummary = evidenceSummary
        self.population = population
        self.intervention = intervention
        self.outcomes = outcomes
        self.limitations = limitations
        self.applicabilityScore = applicabilityScore
        self.applicabilityLabel = applicabilityLabel
        self.versionStatus = versionStatus
        self.conclusionConsistency = conclusionConsistency
        self.newerEvidenceNote = newerEvidenceNote
        self.fullTextLicense = fullTextLicense
        self.sourceDetailURL = sourceDetailURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        studyType = try container.decode(String.self, forKey: .studyType)
        confidence = try container.decode(String.self, forKey: .confidence)
        url = try container.decode(String.self, forKey: .url)
        doi = try container.decodeIfPresent(String.self, forKey: .doi) ?? ""
        relevance = try container.decodeIfPresent(Double.self, forKey: .relevance) ?? 0
        sourceScope = try container.decodeIfPresent(String.self, forKey: .sourceScope) ?? "abstract"
        evidenceSummary = try container.decodeIfPresent(String.self, forKey: .evidenceSummary) ?? ""
        population = try container.decodeIfPresent(String.self, forKey: .population) ?? ""
        intervention = try container.decodeIfPresent(String.self, forKey: .intervention) ?? ""
        outcomes = try container.decodeIfPresent([String].self, forKey: .outcomes) ?? []
        limitations = try container.decodeIfPresent([String].self, forKey: .limitations) ?? []
        applicabilityScore = try container.decodeIfPresent(Double.self, forKey: .applicabilityScore) ?? 0.5
        applicabilityLabel = try container.decodeIfPresent(String.self, forKey: .applicabilityLabel) ?? "unclear"
        versionStatus = try container.decodeIfPresent(String.self, forKey: .versionStatus) ?? "current"
        conclusionConsistency = try container.decodeIfPresent(String.self, forKey: .conclusionConsistency) ?? "unknown"
        newerEvidenceNote = try container.decodeIfPresent(String.self, forKey: .newerEvidenceNote) ?? ""
        fullTextLicense = try container.decodeIfPresent(String.self, forKey: .fullTextLicense) ?? ""
        sourceDetailURL = try container.decodeIfPresent(String.self, forKey: .sourceDetailURL) ?? ""
    }

    var studyTypeLabel: String {
        switch studyType {
        case "guideline": return L10n.string("domain_catalog.ff3d4ff54fbf", fallback: "ガイドライン")
        case "meta_analysis": return L10n.string("domain_catalog.06d5ac3d8c2e", fallback: "メタ解析")
        case "systematic_review": return L10n.string("domain_catalog.7aeed2d99541", fallback: "系統的レビュー")
        case "randomized_controlled_trial": return L10n.string("domain_catalog.a42741ed272e", fallback: "ランダム化比較試験")
        case "clinical_trial": return L10n.string("domain_catalog.7f75bc969b66", fallback: "臨床試験")
        case "observational": return L10n.string("domain_catalog.24f122d18ea7", fallback: "観察研究")
        case "review": return L10n.string("domain_catalog.ef0b3d8cfce0", fallback: "レビュー")
        default: return L10n.string("domain_catalog.4305a22657cf", fallback: "研究論文")
        }
    }

    var confidenceLabel: String {
        switch confidence {
        case "high": return L10n.string("domain_catalog.c28b6b0b1e5e", fallback: "高")
        case "moderate": return L10n.string("domain_catalog.f09327f3d764", fallback: "中")
        case "low": return L10n.string("domain_catalog.f58e9d61af58", fallback: "低")
        default: return L10n.string("domain_catalog.39171b27dcf6", fallback: "参考")
        }
    }
}

struct CoachEvidenceStatus: Codable, Hashable {
    var state: String
    var confidence: String
    var lastUpdatedAt: String?
    var searchedDocuments: Int
    var matchedDocuments: Int
    var reason: String

    static let unavailable = CoachEvidenceStatus(
        state: "unavailable",
        confidence: "insufficient",
        lastUpdatedAt: nil,
        searchedDocuments: 0,
        matchedDocuments: 0,
        reason: ""
    )

    enum CodingKeys: String, CodingKey {
        case state
        case confidence
        case lastUpdatedAt = "last_updated_at"
        case searchedDocuments = "searched_documents"
        case matchedDocuments = "matched_documents"
        case reason
    }

    init(
        state: String,
        confidence: String,
        lastUpdatedAt: String?,
        searchedDocuments: Int,
        matchedDocuments: Int = 0,
        reason: String = ""
    ) {
        self.state = state
        self.confidence = confidence
        self.lastUpdatedAt = lastUpdatedAt
        self.searchedDocuments = searchedDocuments
        self.matchedDocuments = matchedDocuments
        self.reason = reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(String.self, forKey: .state)
        confidence = try container.decodeIfPresent(String.self, forKey: .confidence) ?? "insufficient"
        lastUpdatedAt = try container.decodeIfPresent(String.self, forKey: .lastUpdatedAt)
        searchedDocuments = try container.decodeIfPresent(Int.self, forKey: .searchedDocuments) ?? 0
        matchedDocuments = try container.decodeIfPresent(Int.self, forKey: .matchedDocuments) ?? 0
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
}

struct CoachMemory: Identifiable, Codable, Hashable {
    var id: UUID
    var content: String
    var reason: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        reason: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.reason = reason
        self.createdAt = createdAt
    }
}

struct CoachMemoryCandidate: Codable, Hashable, Identifiable {
    var content: String
    var reason: String

    var id: String { content.normalizedCoachMemoryKey }
}

struct CoachContext: Codable, Hashable {
    var recent7Days: [String: [String]]
    var recent4Weeks: [String: [String]]
    var longTermTrends: [String: [String]]
    var personalRecords: [String]
    var goals: [String]
    var preferences: [String]
    var memories: [String]
    var previousSuggestion: [String: String]
    var suggestionResult: [String: String]

    enum CodingKeys: String, CodingKey {
        case recent7Days = "recent_7_days"
        case recent4Weeks = "recent_4_weeks"
        case longTermTrends = "long_term_trends"
        case personalRecords = "personal_records"
        case goals
        case preferences
        case memories
        case previousSuggestion = "previous_suggestion"
        case suggestionResult = "suggestion_result"
    }

    var itemCount: Int {
        recent7Days.values.reduce(0) { $0 + $1.count }
            + recent4Weeks.values.reduce(0) { $0 + $1.count }
            + longTermTrends.values.reduce(0) { $0 + $1.count }
            + personalRecords.count
            + goals.count
            + preferences.count
            + memories.count
            + previousSuggestion.count
            + suggestionResult.count
    }

    func compacted(aggressively: Bool = false) -> CoachContext {
        let maximumValueCharacters = aggressively ? 120 : 240
        return CoachContext(
            recent7Days: Self.limited(
                recent7Days,
                maximumKeys: aggressively ? 6 : 12,
                maximumValues: aggressively ? 2 : 4,
                maximumValueCharacters: maximumValueCharacters
            ),
            recent4Weeks: Self.limited(
                recent4Weeks,
                maximumKeys: aggressively ? 3 : 6,
                maximumValues: aggressively ? 2 : 4,
                maximumValueCharacters: maximumValueCharacters
            ),
            longTermTrends: Self.limited(
                longTermTrends,
                maximumKeys: aggressively ? 3 : 6,
                maximumValues: aggressively ? 1 : 3,
                maximumValueCharacters: maximumValueCharacters
            ),
            personalRecords: Self.limited(personalRecords, count: aggressively ? 6 : 12, characters: maximumValueCharacters),
            goals: Self.limited(goals, count: aggressively ? 6 : 12, characters: maximumValueCharacters),
            preferences: Self.limited(preferences, count: aggressively ? 6 : 12, characters: maximumValueCharacters),
            memories: Self.limited(memories, count: aggressively ? 20 : 40, characters: maximumValueCharacters),
            previousSuggestion: Self.limited(previousSuggestion, characters: maximumValueCharacters),
            suggestionResult: Self.limited(suggestionResult, characters: maximumValueCharacters)
        )
    }

    private static func limited(
        _ source: [String: [String]],
        maximumKeys: Int,
        maximumValues: Int,
        maximumValueCharacters: Int
    ) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: source.keys.sorted().prefix(maximumKeys).map { key in
            (
                key,
                (source[key] ?? []).prefix(maximumValues).map {
                    compactAIText($0, maximumCharacters: maximumValueCharacters)
                }
            )
        })
    }

    private static func limited(
        _ source: [String],
        count: Int,
        characters: Int
    ) -> [String] {
        source.prefix(count).map { compactAIText($0, maximumCharacters: characters) }
    }

    private static func limited(
        _ source: [String: String],
        characters: Int
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: source.keys.sorted().prefix(8).map { key in
            (
                key,
                compactAIText(source[key] ?? "", maximumCharacters: characters)
            )
        })
    }
}

struct CoachChatRequest: Encodable, Hashable {
    static let maximumMessageCharacters = 4_000
    static let maximumUserMessageCharacters = 300
    static let maximumRecentMessages = 20
    static let maximumSentRecentMessages = 8
    static let maximumContextCharacters = 60_000
    static let preferredRequestCharacters = 8_000
    static let compactedRequestCharacters = 4_000

    var coachID: String
    var coach: AIRequestCoachContext? = nil
    var purpose: AIRequestPurpose = .chat
    var message: String
    var context: CoachContext
    var recentMessages: [CoachChatMessage]
    var responseLocale: String = AppLanguagePreference.aiLocaleIdentifier

    enum CodingKeys: String, CodingKey {
        case coachID = "coach_id"
        case coach
        case purpose
        case message
        case context
        case recentMessages = "recent_messages"
        case responseLocale = "response_locale"
    }

    func constrainedForInitialRequest() -> CoachChatRequest {
        constrained(
            maximumMessages: Self.maximumSentRecentMessages,
            maximumMessageCharacters: 600,
            targetCharacters: Self.preferredRequestCharacters,
            aggressively: false
        )
    }

    func compactedForRetry() -> CoachChatRequest {
        constrained(
            maximumMessages: 4,
            maximumMessageCharacters: 300,
            targetCharacters: Self.compactedRequestCharacters,
            aggressively: true
        )
    }

    private func constrained(
        maximumMessages: Int,
        maximumMessageCharacters: Int,
        targetCharacters: Int,
        aggressively: Bool
    ) -> CoachChatRequest {
        var result = CoachChatRequest(
            coachID: coachID,
            coach: coach,
            purpose: purpose,
            message: message,
            context: context.compacted(aggressively: aggressively),
            recentMessages: recentMessages.suffix(maximumMessages).map {
                var compacted = $0
                compacted.content = compactAIText(
                    $0.content,
                    maximumCharacters: maximumMessageCharacters
                )
                compacted.evidence = []
                return compacted
            },
            responseLocale: responseLocale
        )

        if result.requestInputCharacterCount > targetCharacters {
            result.context = result.context.compacted(aggressively: true)
        }

        while result.requestInputCharacterCount > targetCharacters,
              !result.recentMessages.isEmpty {
            result.recentMessages.removeFirst()
        }
        return result
    }

    private struct RequestMessage: Encodable {
        var role: CoachChatRole
        var content: String
    }

    private var requestInputCharacterCount: Int {
        struct Payload: Encodable {
            var context: CoachContext
            var recentMessages: [RequestMessage]

            enum CodingKeys: String, CodingKey {
                case context
                case recentMessages = "recent_messages"
            }
        }

        let payload = Payload(
            context: context,
            recentMessages: recentMessages.map { RequestMessage(role: $0.role, content: $0.content) }
        )
        guard let data = try? JSONEncoder().encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return .max
        }
        return message.count + string.count
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coachID, forKey: .coachID)
        try container.encodeIfPresent(coach, forKey: .coach)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(message, forKey: .message)
        try container.encode(context, forKey: .context)
        try container.encode(responseLocale, forKey: .responseLocale)
        try container.encode(
            recentMessages.map { RequestMessage(role: $0.role, content: $0.content) },
            forKey: .recentMessages
        )
    }
}

enum AIRequestPurpose: String, Codable, Hashable {
    case chat
    case planGeneration = "plan_generation"
    case dailyRecommendation = "daily_recommendation"
}

struct CoachChatResponse: Codable, Hashable {
    var reply: String
    var memoryCandidates: [CoachMemoryCandidate]
    var evidence: [CoachEvidenceCitation]
    var evidenceStatus: CoachEvidenceStatus

    init(
        reply: String,
        memoryCandidates: [CoachMemoryCandidate] = [],
        evidence: [CoachEvidenceCitation] = [],
        evidenceStatus: CoachEvidenceStatus = .unavailable
    ) {
        self.reply = reply
        self.memoryCandidates = memoryCandidates
        self.evidence = evidence
        self.evidenceStatus = evidenceStatus
    }

    enum CodingKeys: String, CodingKey {
        case reply
        case memoryCandidates = "memory_candidates"
        case evidence
        case evidenceStatus = "evidence_status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(String.self, forKey: .reply)
        memoryCandidates = try container.decodeIfPresent(
            [CoachMemoryCandidate].self,
            forKey: .memoryCandidates
        ) ?? []
        evidence = try container.decodeIfPresent(
            [CoachEvidenceCitation].self,
            forKey: .evidence
        ) ?? []
        evidenceStatus = try container.decodeIfPresent(
            CoachEvidenceStatus.self,
            forKey: .evidenceStatus
        ) ?? .unavailable
    }
}

struct CoachMemoryStore {
    static let maximumMemories = 100

    func candidatesNotAlreadyStored(
        _ candidates: [CoachMemoryCandidate],
        memories: [CoachMemory]
    ) -> [CoachMemoryCandidate] {
        var existing = Set(memories.map { $0.content.normalizedCoachMemoryKey })
        return candidates.filter { candidate in
            let key = candidate.content.normalizedCoachMemoryKey
            guard !key.isEmpty, existing.insert(key).inserted else { return false }
            return true
        }
    }

    func approving(_ candidate: CoachMemoryCandidate, in memories: [CoachMemory]) -> [CoachMemory] {
        guard !candidate.content.normalizedCoachMemoryKey.isEmpty,
              !memories.contains(where: {
                  $0.content.normalizedCoachMemoryKey == candidate.content.normalizedCoachMemoryKey
              }) else {
            return memories
        }

        let approved = CoachMemory(
            content: candidate.content.trimmingCharacters(in: .whitespacesAndNewlines),
            reason: candidate.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return Array(([approved] + memories).prefix(Self.maximumMemories))
    }
}

enum AITrainerError: LocalizedError {
    case emptyMessage
    case messageTooLong
    case contextTooLarge
    case invalidRequest
    case connection

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            L10n.string("domain_catalog.c6b16105b918", fallback: "メッセージを入力してください。")
        case .messageTooLong:
            L10n.string("domain_catalog.3645d68d6247", fallback: "メッセージは4,000文字以内で入力してください。")
        case .contextTooLarge:
            L10n.string("domain_catalog.a02090ea0171", fallback: "AIへ送る履歴が大きすぎます。記録をさらに集計してから再試行してください。")
        case .invalidRequest:
            L10n.string("domain_catalog.0fe0841c2b17", fallback: "AIトレーナーへ送る内容の形式が正しくありません。")
        case .connection:
            L10n.string("domain_catalog.7864c3fcb9ae", fallback: "AIトレーナーに接続できません。時間をおいて再試行してください。")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .emptyMessage, .messageTooLong:
            nil
        case .contextTooLarge:
            L10n.string("domain_catalog.78e438f50d22", fallback: "会話履歴を整理するか、時間をおいてもう一度送信してください。")
        case .invalidRequest:
            L10n.string("domain_catalog.1438eb05085d", fallback: "アプリとAIサーバーを最新の仕様へ更新してください。")
        case .connection:
            L10n.string("domain_catalog.d68a2b5a32a9", fallback: "ネットワーク状態、サーバーURL、AIサーバーの稼働状態を確認してください。")
        }
    }
}

extension String {
    fileprivate var normalizedCoachMemoryKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}
