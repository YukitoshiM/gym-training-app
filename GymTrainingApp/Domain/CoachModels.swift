import Foundation

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

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case studyType = "study_type"
        case confidence
        case url
        case doi
        case relevance
    }

    var studyTypeLabel: String {
        switch studyType {
        case "guideline": return "ガイドライン"
        case "meta_analysis": return "メタ解析"
        case "systematic_review": return "系統的レビュー"
        case "randomized_controlled_trial": return "ランダム化比較試験"
        case "clinical_trial": return "臨床試験"
        case "observational": return "観察研究"
        case "review": return "レビュー"
        default: return "研究論文"
        }
    }

    var confidenceLabel: String {
        switch confidence {
        case "high": return "高"
        case "moderate": return "中"
        case "low": return "低"
        default: return "参考"
        }
    }
}

struct CoachEvidenceStatus: Codable, Hashable {
    var state: String
    var confidence: String
    var lastUpdatedAt: String?
    var searchedDocuments: Int

    static let unavailable = CoachEvidenceStatus(
        state: "unavailable",
        confidence: "insufficient",
        lastUpdatedAt: nil,
        searchedDocuments: 0
    )

    enum CodingKeys: String, CodingKey {
        case state
        case confidence
        case lastUpdatedAt = "last_updated_at"
        case searchedDocuments = "searched_documents"
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
        CoachContext(
            recent7Days: Self.limited(
                recent7Days,
                maximumKeys: aggressively ? 6 : 12,
                maximumValues: aggressively ? 2 : 4
            ),
            recent4Weeks: Self.limited(
                recent4Weeks,
                maximumKeys: aggressively ? 3 : 6,
                maximumValues: aggressively ? 2 : 4
            ),
            longTermTrends: Self.limited(
                longTermTrends,
                maximumKeys: aggressively ? 3 : 6,
                maximumValues: aggressively ? 1 : 3
            ),
            personalRecords: Array(personalRecords.prefix(aggressively ? 6 : 12)),
            goals: Array(goals.prefix(aggressively ? 6 : 12)),
            preferences: Array(preferences.prefix(aggressively ? 6 : 12)),
            memories: Array(memories.prefix(aggressively ? 20 : 50)),
            previousSuggestion: previousSuggestion,
            suggestionResult: suggestionResult
        )
    }

    private static func limited(
        _ source: [String: [String]],
        maximumKeys: Int,
        maximumValues: Int
    ) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: source.keys.sorted().prefix(maximumKeys).map { key in
            (key, Array((source[key] ?? []).prefix(maximumValues)))
        })
    }
}

struct CoachChatRequest: Encodable, Hashable {
    static let maximumMessageCharacters = 4_000
    static let maximumRecentMessages = 20
    static let maximumContextCharacters = 60_000

    var coachID: String
    var message: String
    var context: CoachContext
    var recentMessages: [CoachChatMessage]

    enum CodingKeys: String, CodingKey {
        case coachID = "coach_id"
        case message
        case context
        case recentMessages = "recent_messages"
    }

    func constrainedForInitialRequest() -> CoachChatRequest {
        constrained(maximumMessages: Self.maximumRecentMessages, aggressively: false)
    }

    func compactedForRetry() -> CoachChatRequest {
        constrained(maximumMessages: 8, aggressively: true)
    }

    private func constrained(maximumMessages: Int, aggressively: Bool) -> CoachChatRequest {
        var result = CoachChatRequest(
            coachID: coachID,
            message: message,
            context: aggressively ? context.compacted(aggressively: true) : context,
            recentMessages: Array(recentMessages.suffix(maximumMessages))
        )

        guard result.contextAndMessagesCharacterCount > Self.maximumContextCharacters else {
            return result
        }

        result.context = result.context.compacted(aggressively: true)
        while result.contextAndMessagesCharacterCount > Self.maximumContextCharacters,
              !result.recentMessages.isEmpty {
            result.recentMessages.removeFirst()
        }
        return result
    }

    private var contextAndMessagesCharacterCount: Int {
        struct Payload: Encodable {
            var context: CoachContext
            var recentMessages: [CoachChatMessage]

            enum CodingKeys: String, CodingKey {
                case context
                case recentMessages = "recent_messages"
            }
        }

        let payload = Payload(context: context, recentMessages: recentMessages)
        guard let data = try? JSONEncoder().encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return .max
        }
        return string.count
    }
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
            "メッセージを入力してください。"
        case .messageTooLong:
            "メッセージは4,000文字以内で入力してください。"
        case .contextTooLarge:
            "AIへ送る履歴が大きすぎます。記録をさらに集計してから再試行してください。"
        case .invalidRequest:
            "AIトレーナーへ送る内容の形式が正しくありません。"
        case .connection:
            "AIトレーナーに接続できません。時間をおいて再試行してください。"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .emptyMessage, .messageTooLong:
            nil
        case .contextTooLarge:
            "会話履歴を整理するか、時間をおいてもう一度送信してください。"
        case .invalidRequest:
            "アプリとAIサーバーを最新の仕様へ更新してください。"
        case .connection:
            "ネットワーク状態、サーバーURL、AIサーバーの稼働状態を確認してください。"
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
