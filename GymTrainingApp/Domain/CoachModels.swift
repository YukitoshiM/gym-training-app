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

    init(
        id: UUID = UUID(),
        role: CoachChatRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
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

    init(reply: String, memoryCandidates: [CoachMemoryCandidate] = []) {
        self.reply = reply
        self.memoryCandidates = memoryCandidates
    }

    enum CodingKeys: String, CodingKey {
        case reply
        case memoryCandidates = "memory_candidates"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(String.self, forKey: .reply)
        memoryCandidates = try container.decodeIfPresent(
            [CoachMemoryCandidate].self,
            forKey: .memoryCandidates
        ) ?? []
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
