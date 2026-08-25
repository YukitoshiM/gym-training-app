import Foundation
import Security

struct AISettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var baseURLString: String
    var apiKey: String
    var usesSessionTokens: Bool
    var dataSharing: AIDataSharingSettings
    var managedConfigurationVersion: Int?

    init(
        isEnabled: Bool,
        baseURLString: String,
        apiKey: String,
        usesSessionTokens: Bool = false,
        dataSharing: AIDataSharingSettings = .default,
        managedConfigurationVersion: Int? = nil
    ) {
        self.isEnabled = isEnabled
        self.baseURLString = baseURLString
        self.apiKey = apiKey
        self.usesSessionTokens = usesSessionTokens
        self.dataSharing = dataSharing
        self.managedConfigurationVersion = managedConfigurationVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled
        baseURLString = try container.decodeIfPresent(String.self, forKey: .baseURLString) ?? Self.default.baseURLString
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? Self.default.apiKey
        usesSessionTokens = try container.decodeIfPresent(Bool.self, forKey: .usesSessionTokens) ?? false
        dataSharing = try container.decodeIfPresent(AIDataSharingSettings.self, forKey: .dataSharing) ?? .default
        managedConfigurationVersion = try container.decodeIfPresent(Int.self, forKey: .managedConfigurationVersion)
    }

    static let `default`: AISettings = {
        if let bundled = AIServiceBuildConfiguration.settings {
            return bundled
        }

        #if DEBUG
        return AISettings(
            isEnabled: true,
            baseURLString: "http://127.0.0.1:8765",
            apiKey: "dev-local-key"
        )
        #else
        return AISettings(isEnabled: false, baseURLString: "", apiKey: "")
        #endif
    }()

    static var allowsConnectionEditing: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--enable-ai-connection-editor")
        #else
        false
        #endif
    }

    static var configurationHelp: String {
        if allowsConnectionEditing {
            return L10n.string("domain_catalog.4d5b0045e0e5", fallback: "開発用の接続先を指定できます。APIキーは端末のKeychainへ保存します。")
        }
        return L10n.string("domain_catalog.b1f2c64a95cc", fallback: "接続先と認証情報はBodyModeが管理します。画面や診断ログには接続アドレスを表示しません。")
    }

    var hasConfiguredConnection: Bool {
        guard !apiKey.isEmpty,
              let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return false
        }
        return true
    }

    static var hasBundledConfiguration: Bool {
        bundledConfiguration != nil
    }

    static var bundledConfiguration: AISettings? {
        AIServiceBuildConfiguration.settings
    }

    func migratingManagedConfiguration(to bundled: AISettings?) -> AISettings {
        guard let bundled,
              let bundledVersion = bundled.managedConfigurationVersion else {
            return self
        }

        let currentURL = Self.normalizedBaseURL(baseURLString)
        let bundledURL = Self.normalizedBaseURL(bundled.baseURLString)
        let usesRetiredBundledURL = Self.isRetiredBundledURL(currentURL)
        let matchesUnversionedBundledConfiguration = managedConfigurationVersion == nil
            && currentURL == bundledURL
            && apiKey == bundled.apiKey
        let usesOlderManagedConfiguration = managedConfigurationVersion.map { $0 < bundledVersion } ?? false
        let managedConfigurationChanged = managedConfigurationVersion != nil
            && (currentURL != bundledURL
                || apiKey != bundled.apiKey
                || usesSessionTokens != bundled.usesSessionTokens)
        guard usesRetiredBundledURL
                || matchesUnversionedBundledConfiguration
                || usesOlderManagedConfiguration
                || managedConfigurationChanged else {
            return self
        }

        var migrated = self
        migrated.baseURLString = bundled.baseURLString
        migrated.apiKey = bundled.apiKey
        migrated.usesSessionTokens = bundled.usesSessionTokens
        migrated.managedConfigurationVersion = bundledVersion
        return migrated
    }

    func normalizedForPersistence(relativeTo bundled: AISettings?) -> AISettings {
        guard let bundled else { return self }

        var normalized = self
        let matchesBundledConfiguration = Self.normalizedBaseURL(baseURLString)
            == Self.normalizedBaseURL(bundled.baseURLString)
            && apiKey == bundled.apiKey
            && usesSessionTokens == bundled.usesSessionTokens
        normalized.managedConfigurationVersion = matchesBundledConfiguration
            ? bundled.managedConfigurationVersion
            : nil
        return normalized
    }

    private static func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " /\n\t")).lowercased()
    }

    private static let retiredBundledBaseURLs: Set<String> = [
        "https://retired-ai-endpoint.invalid",
        "https://bodymode-ai-gateway.bodymode-ai.workers.dev",
        "https://bodymode-ai-gateway-staging.bodymode-ai.workers.dev",
        "http://127.0.0.1:8765",
        "http://localhost:8765"
    ]

    private static func isRetiredBundledURL(_ value: String) -> Bool {
        if retiredBundledBaseURLs.contains(value) {
            return true
        }
        guard let host = URL(string: value)?.host?.lowercased() else { return false }
        return host.hasSuffix(".trycloudflare.com") || host.hasSuffix(".ts.net")
    }
}

private enum AIServiceBuildConfiguration {
    static var settings: AISettings? {
        let baseURL = string(forInfoKey: "BodyModeAIBaseURL")
        let apiKey = string(forInfoKey: "BodyModeAIAPIKey")
        let configurationVersion = Int(string(forInfoKey: "BodyModeAIConfigurationVersion"))
        let usesSessionTokens = bool(forInfoKey: "BodyModeAIUsesSessionTokens")
        guard !baseURL.isEmpty, !apiKey.isEmpty else { return nil }
        return AISettings(
            isEnabled: true,
            baseURLString: baseURL,
            apiKey: apiKey,
            usesSessionTokens: usesSessionTokens,
            managedConfigurationVersion: configurationVersion
        )
    }

    private static func string(forInfoKey key: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("$(") ? "" : trimmed
    }

    private static func bool(forInfoKey key: String) -> Bool {
        switch string(forInfoKey: key).lowercased() {
        case "yes", "true", "1": true
        default: false
        }
    }
}

enum SecureSettingsStore {
    private static let service = "com.yukitoshim.gymtrainingapp.ai"
    private static let apiKeyAccount = "local-ai-api-key"
    private static let accessTokenAccount = "local-ai-access-token-v1"
    private static let accountRegistrationAccount = "ai-account-registration-v1"
    private static let appAccountTokenAccount = "storekit-app-account-token-v1"
    private static let installationIDAccount = "installation-id-v1"

    static func loadAPIKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func saveAPIKey(_ value: String) -> Bool {
        if value.isEmpty {
            deleteAPIKey()
            return true
        }

        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else { return false }

        var item = baseQuery
        item.merge(attributes) { _, new in new }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func deleteAPIKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static func loadAccessToken() -> AICachedAccessToken? {
        guard let data = loadData(account: accessTokenAccount) else { return nil }
        return try? JSONDecoder().decode(AICachedAccessToken.self, from: data)
    }

    @discardableResult
    static func saveAccessToken(_ token: AICachedAccessToken) -> Bool {
        guard let data = try? JSONEncoder().encode(token) else { return false }
        return saveData(data, account: accessTokenAccount)
    }

    static func deleteAccessToken() {
        delete(account: accessTokenAccount)
    }

    static var hasAIAccount: Bool {
        loadData(account: accountRegistrationAccount) != nil
    }

    @discardableResult
    static func markAIAccountRegistered() -> Bool {
        saveData(Data([1]), account: accountRegistrationAccount)
    }

    static func deleteAIAccountRegistration() {
        delete(account: accountRegistrationAccount)
    }

    static var appAccountToken: UUID? {
        guard let data = loadData(account: appAccountTokenAccount),
              let value = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: value)
    }

    @discardableResult
    static func saveAppAccountToken(_ token: UUID) -> Bool {
        saveData(Data(token.uuidString.lowercased().utf8), account: appAccountTokenAccount)
    }

    static func deleteInstallationID() {
        delete(account: installationIDAccount)
    }

    static func resetAIIdentity() {
        deleteAPIKey()
        deleteAccessToken()
        deleteAIAccountRegistration()
        delete(account: appAccountTokenAccount)
        deleteInstallationID()
    }

    static func installationID() -> String {
        if let data = loadData(account: installationIDAccount),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }
        let value = UUID().uuidString.lowercased()
        _ = saveData(Data(value.utf8), account: installationIDAccount)
        return value
    }

    private static func loadData(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func saveData(_ data: Data, account: String) -> Bool {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var item = query
        item.merge(attributes) { _, new in new }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        baseQuery(account: apiKeyAccount)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct AICachedAccessToken: Codable, Equatable, Sendable {
    var value: String
    var baseURLString: String
    var expiresAt: Date

    func isUsable(for baseURLString: String, now: Date = Date()) -> Bool {
        self.baseURLString == baseURLString && expiresAt.timeIntervalSince(now) > 60
    }
}

final class AIAuthenticationStore: @unchecked Sendable {
    static let shared = AIAuthenticationStore()

    private let lock = NSLock()
    private var memoryToken: AICachedAccessToken?
    private var tokenRequests: [String: (id: UUID, task: Task<AICachedAccessToken, Error>)] = [:]

    private init() {}

    func usableToken(for baseURLString: String) -> AICachedAccessToken? {
        lock.lock()
        defer { lock.unlock() }
        if let memoryToken, memoryToken.isUsable(for: baseURLString) {
            return memoryToken
        }
        guard let persisted = SecureSettingsStore.loadAccessToken(),
              persisted.isUsable(for: baseURLString) else {
            memoryToken = nil
            return nil
        }
        memoryToken = persisted
        return persisted
    }

    func save(_ token: AICachedAccessToken) {
        lock.lock()
        defer { lock.unlock() }
        memoryToken = token
        _ = SecureSettingsStore.saveAccessToken(token)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        memoryToken = nil
        SecureSettingsStore.deleteAccessToken()
    }

    func coordinatedToken(
        for baseURLString: String,
        fetch: @escaping @Sendable () async throws -> AICachedAccessToken
    ) async throws -> AICachedAccessToken {
        if let cached = usableToken(for: baseURLString) {
            return cached
        }

        let request = tokenRequest(for: baseURLString, fetch: fetch)
        defer { clearTokenRequest(for: baseURLString, id: request.id) }
        let token = try await request.task.value
        save(token)
        return token
    }

    private func tokenRequest(
        for baseURLString: String,
        fetch: @escaping @Sendable () async throws -> AICachedAccessToken
    ) -> (id: UUID, task: Task<AICachedAccessToken, Error>) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = tokenRequests[baseURLString] {
            return existing
        }

        let request = (id: UUID(), task: Task { try await fetch() })
        tokenRequests[baseURLString] = request
        return request
    }

    private func clearTokenRequest(for baseURLString: String, id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard tokenRequests[baseURLString]?.id == id else { return }
        tokenRequests.removeValue(forKey: baseURLString)
    }
}

struct AIAccessTokenResponse: Decodable {
    var accessToken: String
    var tokenType: String
    var expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct AIAccessTokenRequest: Encodable {
    var installationID: String
    var appVersion: String

    enum CodingKeys: String, CodingKey {
        case installationID = "installation_id"
        case appVersion = "app_version"
    }
}

struct AIAppleAccountRequest: Encodable {
    var identityToken: String
    var authorizationCode: String
    var rawNonce: String
    var installationID: String
    var appVersion: String

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case rawNonce = "raw_nonce"
        case installationID = "installation_id"
        case appVersion = "app_version"
    }
}

struct AIAppleAccountResponse: Decodable {
    var accessToken: String
    var expiresIn: TimeInterval
    var signupGranted: Bool
    var signupGrantedAmount: Int
    var credits: AICreditBalance
    var featureCosts: [String: Int]
    var appAccountToken: UUID

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case signupGranted = "signup_granted"
        case signupGrantedAmount = "signup_granted_amount"
        case credits
        case featureCosts = "feature_costs"
        case appAccountToken = "app_account_token"
    }
}

struct AICreditBalance: Codable, Hashable {
    var total: Int
    var available: Int
    var reserved: Int
    var buckets: [String: Int]
}

struct AICreditSummary: Codable, Hashable {
    var enforced: Bool
    var unlimited: Bool
    var supportID: String?
    var balance: AICreditBalance?
    var featureCosts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case enforced, unlimited, balance
        case supportID = "support_id"
        case featureCosts = "feature_costs"
    }
}

struct AIRewardedAdClaimRequest: Encodable {
    var challengeID: String
    enum CodingKeys: String, CodingKey { case challengeID = "challenge_id" }
}

struct AIRewardedAdChallengeResponse: Decodable {
    var challengeID: String
    var customData: String
    var expiresIn: Int
    var remainingToday: Int
    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case customData = "custom_data"
        case expiresIn = "expires_in"
        case remainingToday = "remaining_today"
    }
}

struct AIRewardedAdClaimResponse: Decodable {
    var granted: Bool
    var grantedAmount: Int
    var remainingToday: Int
    var balance: AICreditBalance
    var pending: Bool
    enum CodingKeys: String, CodingKey {
        case granted, balance
        case grantedAmount = "granted_amount"
        case remainingToday = "remaining_today"
        case pending
    }
}

struct AICreditPurchaseVerifyRequest: Encodable {
    var signedTransaction: String
    enum CodingKeys: String, CodingKey { case signedTransaction = "signed_transaction" }
}

struct AICreditPurchaseVerifyResponse: Decodable {
    var granted: Bool
    var grantedAmount: Int
    var transactionID: String
    var productID: String
    var balance: AICreditBalance
    enum CodingKeys: String, CodingKey {
        case granted, balance
        case grantedAmount = "granted_amount"
        case transactionID = "transaction_id"
        case productID = "product_id"
    }
}

struct AIAccountDeletionResponse: Decodable {
    var removedCredits: Int
    enum CodingKeys: String, CodingKey { case removedCredits = "removed_credits" }
}

struct AICreditHistoryResponse: Decodable {
    var supportID: String?
    var events: [AICreditHistoryEvent]
    var balance: AICreditBalance

    enum CodingKeys: String, CodingKey {
        case supportID = "support_id"
        case events, balance
    }
}

struct AICreditHistoryEvent: Decodable, Identifiable {
    var id: Int
    var eventType: String
    var amount: Int
    var source: String?
    var feature: String?
    var occurredAt: Int
    enum CodingKeys: String, CodingKey {
        case id, amount, source, feature
        case eventType = "event_type"
        case occurredAt = "occurred_at"
    }
}

struct UsageAnalyticsUploadEvent: Encodable {
    var id: UUID
    var occurredAt: Int
    var name: String
    var dimension: String?
    var properties: UsageEventProperties?
    var appVersion: String
    var locale: String
    var channel: String

    enum CodingKeys: String, CodingKey {
        case id
        case occurredAt = "occurred_at"
        case name
        case dimension
        case properties
        case appVersion = "app_version"
        case locale
        case channel
    }
}

struct UsageAnalyticsUploadBatch: Encodable {
    var events: [UsageAnalyticsUploadEvent]
}

struct UsageAnalyticsUploadResponse: Decodable {
    var accepted: Int
}

struct UsageAnalyticsDeleteResponse: Decodable {
    var deleted: Int
}

struct AIDataSharingSettings: Codable, Equatable, Sendable {
    var bodyMetrics: Bool
    var meals: Bool
    var workouts: Bool
    var bodyPhotos: Bool
    var sleepAndRecovery: Bool
    var dailyActivity: Bool
    var gymVisits: Bool
    var workoutSensors: Bool
    var trainingConsiderations: Bool

    init(
        bodyMetrics: Bool,
        meals: Bool,
        workouts: Bool,
        bodyPhotos: Bool,
        sleepAndRecovery: Bool,
        dailyActivity: Bool,
        gymVisits: Bool,
        workoutSensors: Bool,
        trainingConsiderations: Bool = false
    ) {
        self.bodyMetrics = bodyMetrics
        self.meals = meals
        self.workouts = workouts
        self.bodyPhotos = bodyPhotos
        self.sleepAndRecovery = sleepAndRecovery
        self.dailyActivity = dailyActivity
        self.gymVisits = gymVisits
        self.workoutSensors = workoutSensors
        self.trainingConsiderations = trainingConsiderations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bodyMetrics = try container.decodeIfPresent(Bool.self, forKey: .bodyMetrics) ?? true
        meals = try container.decodeIfPresent(Bool.self, forKey: .meals) ?? true
        workouts = try container.decodeIfPresent(Bool.self, forKey: .workouts) ?? true
        bodyPhotos = try container.decodeIfPresent(Bool.self, forKey: .bodyPhotos) ?? true
        sleepAndRecovery = try container.decodeIfPresent(Bool.self, forKey: .sleepAndRecovery) ?? false
        dailyActivity = try container.decodeIfPresent(Bool.self, forKey: .dailyActivity) ?? false
        gymVisits = try container.decodeIfPresent(Bool.self, forKey: .gymVisits) ?? false
        workoutSensors = try container.decodeIfPresent(Bool.self, forKey: .workoutSensors) ?? false
        trainingConsiderations = try container.decodeIfPresent(Bool.self, forKey: .trainingConsiderations) ?? false
    }

    static let `default` = AIDataSharingSettings(
        bodyMetrics: true,
        meals: true,
        workouts: true,
        bodyPhotos: true,
        sleepAndRecovery: false,
        dailyActivity: false,
        gymVisits: false,
        workoutSensors: false,
        trainingConsiderations: false
    )

    var enabledCategoryNames: [String] {
        [
            bodyMetrics ? L10n.string("domain_catalog.629a44944024", fallback: "身体KPI") : nil,
            meals ? L10n.string("domain_catalog.c313c696c2b6", fallback: "食事") : nil,
            workouts ? L10n.string("domain_catalog.50320710b7fb", fallback: "筋トレ") : nil,
            bodyPhotos ? L10n.string("domain_catalog.b9009f656b8d", fallback: "体型写真") : nil,
            sleepAndRecovery ? L10n.string("domain_catalog.d6c47594dbd3", fallback: "睡眠・回復") : nil,
            dailyActivity ? L10n.string("domain_catalog.e452c77116e2", fallback: "日常活動") : nil,
            gymVisits ? L10n.string("domain_catalog.4c7e42a86929", fallback: "ジム訪問") : nil,
            workoutSensors ? L10n.string("domain_catalog.ee583d0f2045", fallback: "ワークアウトセンサー") : nil,
            trainingConsiderations ? AppLanguagePreference.bilingual(
                japanese: "運動上の配慮事項",
                english: "Training considerations"
            ) : nil
        ].compactMap { $0 }
    }

    private enum CodingKeys: String, CodingKey {
        case bodyMetrics
        case meals
        case workouts
        case bodyPhotos
        case sleepAndRecovery
        case dailyActivity
        case gymVisits
        case workoutSensors
        case trainingConsiderations
    }
}

struct MealAIDraft: Codable, Hashable {
    var mealName: String
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var confidence: String
    var comment: String
    var items: [MealAIDraftItem]

    enum CodingKeys: String, CodingKey {
        case mealName = "meal_name"
        case calories
        case protein
        case fat
        case carbs
        case confidence
        case comment
        case items
    }

    static let empty = MealAIDraft(
        mealName: "",
        calories: 0,
        protein: 0,
        fat: 0,
        carbs: 0,
        confidence: "low",
        comment: "",
        items: []
    )

    func reconciledFromItems() -> MealAIDraft {
        guard !items.isEmpty else { return self }

        let totals = items.reduce(into: (calories: 0.0, protein: 0.0, fat: 0.0, carbs: 0.0)) { result, item in
            result.calories += item.calories
            result.protein += item.protein
            result.fat += item.fat
            result.carbs += item.carbs
        }
        let hasMaterialDifference = [
            abs(calories - totals.calories) > max(10, totals.calories * 0.05),
            abs(protein - totals.protein) > max(2, totals.protein * 0.08),
            abs(fat - totals.fat) > max(2, totals.fat * 0.08),
            abs(carbs - totals.carbs) > max(2, totals.carbs * 0.08)
        ].contains(true)

        var reconciled = self
        reconciled.calories = totals.calories
        reconciled.protein = totals.protein
        reconciled.fat = totals.fat
        reconciled.carbs = totals.carbs
        if hasMaterialDifference {
            let notice = L10n.string("domain_catalog.c8708c4bc61f", fallback: "食品別の内訳を合計してPFCとカロリーを補正しました。")
            reconciled.comment = comment.isEmpty ? notice : "\(comment)\n\(notice)"
        }
        return reconciled
    }
}

struct AICoachSummary: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var identity: String
    var priorities: [String]
}

struct MealAIDraftItem: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var amount: String
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var nutritionSource: MealNutritionSource?
    var sourceID: String?

    init(
        id: UUID = UUID(),
        name: String,
        amount: String,
        calories: Double,
        protein: Double,
        fat: Double,
        carbs: Double,
        nutritionSource: MealNutritionSource? = nil,
        sourceID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.nutritionSource = nutritionSource
        self.sourceID = sourceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        calories = try container.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        protein = try container.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        fat = try container.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        carbs = try container.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        nutritionSource = try container.decodeIfPresent(MealNutritionSource.self, forKey: .nutritionSource)
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case calories
        case protein
        case fat
        case carbs
        case nutritionSource = "nutrition_source"
        case sourceID = "source_id"
    }
}

struct BodyPhotoAIComment: Codable, Hashable {
    var summary: String
    var abdomen: String
    var waist: String
    var posture: String
    var score: Double?
    var confidence: String
    var goalRelevance: String? = nil
    var positiveFindings: [String]? = nil
    var observedChanges: [String]? = nil
    var nextActions: [String]? = nil
    var referenceEstimates: [BodyPhotoReferenceEstimate]? = nil

    enum CodingKeys: String, CodingKey {
        case summary
        case abdomen
        case waist
        case posture
        case score
        case confidence
        case goalRelevance = "goal_relevance"
        case positiveFindings = "positive_findings"
        case observedChanges = "observed_changes"
        case nextActions = "next_actions"
        case referenceEstimates = "reference_estimates"
    }

    init(
        summary: String,
        abdomen: String,
        waist: String,
        posture: String,
        score: Double?,
        confidence: String,
        goalRelevance: String? = nil,
        positiveFindings: [String]? = nil,
        observedChanges: [String]? = nil,
        nextActions: [String]? = nil,
        referenceEstimates: [BodyPhotoReferenceEstimate]? = nil
    ) {
        self.summary = summary
        self.abdomen = abdomen
        self.waist = waist
        self.posture = posture
        self.score = score
        self.confidence = confidence
        self.goalRelevance = goalRelevance
        self.positiveFindings = positiveFindings
        self.observedChanges = observedChanges
        self.nextActions = nextActions
        self.referenceEstimates = referenceEstimates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        abdomen = try container.decode(String.self, forKey: .abdomen)
        waist = try container.decode(String.self, forKey: .waist)
        posture = try container.decode(String.self, forKey: .posture)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        confidence = try container.decode(String.self, forKey: .confidence)
        goalRelevance = try container.decodeIfPresent(String.self, forKey: .goalRelevance)
        positiveFindings = try container.decodeIfPresent([String].self, forKey: .positiveFindings)
        observedChanges = try container.decodeIfPresent([String].self, forKey: .observedChanges)
        nextActions = try container.decodeIfPresent([String].self, forKey: .nextActions)
        referenceEstimates = try container.decodeIfPresent(
            [BodyPhotoReferenceEstimate].self,
            forKey: .referenceEstimates
        )
    }
}

struct BodyPhotoReferenceEstimate: Codable, Hashable, Identifiable {
    var metric: String
    var lowerBound: Double
    var upperBound: Double
    var unit: String
    var confidence: String
    var rationale: String

    var id: String { metric }

    enum CodingKeys: String, CodingKey {
        case metric
        case lowerBound = "lower_bound"
        case upperBound = "upper_bound"
        case unit
        case confidence
        case rationale
    }

    var displayName: String {
        switch metric {
        case "body_fat_percent": L10n.string("domain_catalog.70b83fa847e3", fallback: "体脂肪率")
        default: metric
        }
    }
}

struct BodyPhotoAnalysisMetrics: Encodable, Hashable {
    var weightKG: Double?
    var waistCM: Double?
    var bodyFatPercentage: Double?

    var isEmpty: Bool {
        weightKG == nil && waistCM == nil && bodyFatPercentage == nil
    }

    init(
        weightKG: Double? = nil,
        waistCM: Double? = nil,
        bodyFatPercentage: Double? = nil
    ) {
        self.weightKG = weightKG
        self.waistCM = waistCM
        self.bodyFatPercentage = bodyFatPercentage
    }

    enum CodingKeys: String, CodingKey {
        case weightKG = "weight_kg"
        case waistCM = "waist_cm"
        case bodyFatPercentage = "body_fat_percent"
    }
}

struct BodyPhotoAnalysisContext: Encodable, Hashable {
    var profileGoal: String
    var outcomeStyle: String
    var focusAreas: [String]
    var experienceLevel: String
    var currentMetrics: [String]
    var previousCaptureDate: String?
    var previousSummary: String?
    var previousMetrics: BodyPhotoAnalysisMetrics?
    var metricDeltas: BodyPhotoAnalysisMetrics?
    var coach: AIRequestCoachContext?

    init(
        profileGoal: String,
        outcomeStyle: String,
        focusAreas: [String],
        experienceLevel: String,
        currentMetrics: [String],
        previousCaptureDate: String?,
        previousSummary: String?,
        previousMetrics: BodyPhotoAnalysisMetrics? = nil,
        metricDeltas: BodyPhotoAnalysisMetrics? = nil,
        coach: AIRequestCoachContext? = nil
    ) {
        self.profileGoal = profileGoal
        self.outcomeStyle = outcomeStyle
        self.focusAreas = focusAreas
        self.experienceLevel = experienceLevel
        self.currentMetrics = currentMetrics
        self.previousCaptureDate = previousCaptureDate
        self.previousSummary = previousSummary
        self.previousMetrics = previousMetrics?.isEmpty == false ? previousMetrics : nil
        self.metricDeltas = metricDeltas?.isEmpty == false ? metricDeltas : nil
        self.coach = coach
    }

    enum CodingKeys: String, CodingKey {
        case profileGoal = "profile_goal"
        case outcomeStyle = "outcome_style"
        case focusAreas = "focus_areas"
        case experienceLevel = "experience_level"
        case currentMetrics = "current_metrics"
        case previousCaptureDate = "previous_capture_date"
        case previousSummary = "previous_summary"
        case previousMetrics = "previous_metrics"
        case metricDeltas = "metric_deltas"
        case coach
    }
}

struct AIRequestCoachContext: Encodable, Hashable {
    var coachID: String
    var personaID: String
    var coachName: String
    var personaSummary: String
    var coachingStyleID: String
    var coachingStyle: String
    var promise: String
    var focusAreas: [String]
    var approach: [String]
    var boundaries: [String]

    init(profile: UserProfile) {
        let expertise = profile.coachType.expertiseProfile
        coachID = profile.coachType.rawValue
        personaID = profile.coachPersona.rawValue
        coachName = profile.coachPersona.displayName
        personaSummary = profile.coachPersona.characterSummary
        coachingStyleID = profile.coachingStyle.rawValue
        coachingStyle = profile.coachingStyle.promptDescription
        promise = expertise.promise
        focusAreas = expertise.topFocusAreas
        approach = expertise.approach
        boundaries = expertise.boundaries
    }

    enum CodingKeys: String, CodingKey {
        case coachID = "coach_id"
        case personaID = "persona_id"
        case coachName = "coach_name"
        case personaSummary = "persona_summary"
        case coachingStyleID = "coaching_style_id"
        case coachingStyle = "coaching_style"
        case promise
        case focusAreas = "focus_areas"
        case approach
        case boundaries
    }
}

struct AIInsight: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var insightType: AIInsightType
    var inputSummary: String
    var outputComment: String
    var actionSuggestion: String
    var goodPoints: [String]?
    var challenges: [String]?
    var rationales: [String]?
    var nextActions: [String]?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        insightType: AIInsightType,
        inputSummary: String,
        outputComment: String,
        actionSuggestion: String,
        goodPoints: [String]? = nil,
        challenges: [String]? = nil,
        rationales: [String]? = nil,
        nextActions: [String]? = nil
    ) {
        self.id = id
        self.date = date
        self.insightType = insightType
        self.inputSummary = inputSummary
        self.outputComment = outputComment
        self.actionSuggestion = actionSuggestion
        self.goodPoints = goodPoints
        self.challenges = challenges
        self.rationales = rationales
        self.nextActions = nextActions
    }
}

enum AIInsightType: String, Codable, Hashable {
    case weekly
    case monthly
    case meal
    case bodyPhoto
}

struct AITransmissionRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var sentAt: Date
    var purpose: String
    var sharedCategories: [String]
    var itemCount: Int
    var status: AITransmissionStatus
    var failureMessage: String?
    var recoverySuggestion: String?
    var canRetry: Bool?
    var consumedQuota: Bool?

    init(
        id: UUID = UUID(),
        sentAt: Date = Date(),
        purpose: String,
        sharedCategories: [String],
        itemCount: Int,
        status: AITransmissionStatus = .sending,
        failureMessage: String? = nil,
        recoverySuggestion: String? = nil,
        canRetry: Bool? = nil,
        consumedQuota: Bool? = nil
    ) {
        self.id = id
        self.sentAt = sentAt
        self.purpose = purpose
        self.sharedCategories = sharedCategories
        self.itemCount = itemCount
        self.status = status
        self.failureMessage = failureMessage
        self.recoverySuggestion = recoverySuggestion
        self.canRetry = canRetry
        self.consumedQuota = consumedQuota
    }
}

enum AITransmissionStatus: String, Codable {
    case sending
    case completed
    case failed
}
