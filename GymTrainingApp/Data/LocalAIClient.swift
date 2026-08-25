import Foundation

private struct EmptyAIRequest: Encodable {}

struct AIAPIClient: Sendable {
    private static let inferenceTimeout: TimeInterval = 240
    private static let maximumTransientInferenceRetries = 1
    private static let maximumAIMemoCharacters = 500
    private static let maximumMealItemCharacters = 120
    private static let distributionChannelHeader = "X-BodyMode-Distribution-Channel"
    private static let distributionChannelFallbackHeader = "X-App-Distribution-Channel"

    let settings: AISettings
    private let session: URLSession

    init(settings: AISettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    private var baseURL: URL? {
        URL(string: settings.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func health() async throws -> AIHealthResponse {
        try await get("/v1/health", responseType: AIHealthResponse.self, timeout: 15)
    }

    func coaches() async throws -> [AICoachSummary] {
        try await get("/v1/coaches", responseType: [AICoachSummary].self, timeout: 15)
    }

    func usage() async throws -> AIUsageSummary {
        try await get("/v1/usage", responseType: AIUsageSummary.self, timeout: 15)
    }

    func createAppleAccount(
        identityToken: String,
        authorizationCode: String,
        rawNonce: String
    ) async throws -> AIAppleAccountResponse {
        guard settings.isEnabled else { throw AIClientError.disabled }
        var request = URLRequest(url: try makeURL("/v1/account/apple"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        request.httpBody = try JSONEncoder.aiEncoder.encode(
            AIAppleAccountRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                rawNonce: rawNonce,
                installationID: SecureSettingsStore.installationID(),
                appVersion: appVersion
            )
        )
        let response = try await send(request, responseType: AIAppleAccountResponse.self)
        let token = AICachedAccessToken(
            value: response.accessToken,
            baseURLString: settings.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            expiresAt: Date().addingTimeInterval(max(0, response.expiresIn))
        )
        guard SecureSettingsStore.markAIAccountRegistered(),
              SecureSettingsStore.saveAppAccountToken(response.appAccountToken) else {
            throw AIClientError.secureStorageFailed
        }
        AIAuthenticationStore.shared.save(token)
        return response
    }

    func createRewardedAdChallenge() async throws -> AIRewardedAdChallengeResponse {
        try await post(
            "/v1/credits/rewarded-ad/challenge",
            body: EmptyAIRequest(),
            responseType: AIRewardedAdChallengeResponse.self,
            timeout: 20
        )
    }

    func claimRewardedAd(challengeID: String) async throws -> AIRewardedAdClaimResponse {
        try await post(
            "/v1/credits/rewarded-ad/claim",
            body: AIRewardedAdClaimRequest(challengeID: challengeID),
            responseType: AIRewardedAdClaimResponse.self,
            timeout: 20
        )
    }

    func verifyCreditPurchase(signedTransaction: String) async throws -> AICreditPurchaseVerifyResponse {
        try await post(
            "/v1/credits/purchases/verify",
            body: AICreditPurchaseVerifyRequest(signedTransaction: signedTransaction),
            responseType: AICreditPurchaseVerifyResponse.self,
            timeout: 30
        )
    }

    func deleteAccount() async throws -> AIAccountDeletionResponse {
        var request = URLRequest(url: try makeURL("/v1/account"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 20
        try await applyHeaders(to: &request)
        return try await send(request, responseType: AIAccountDeletionResponse.self)
    }

    func creditHistory() async throws -> AICreditHistoryResponse {
        try await get("/v1/credits/history", responseType: AICreditHistoryResponse.self, timeout: 15)
    }

    func uploadUsageEvents(_ events: [UsageEvent]) async throws {
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.missingAPIKey
        }
        let payload = UsageAnalyticsUploadBatch(events: events.map {
            UsageAnalyticsUploadEvent(
                id: $0.id,
                occurredAt: Int($0.timestamp.timeIntervalSince1970),
                name: $0.name.rawValue,
                dimension: $0.dimension,
                properties: $0.properties,
                appVersion: $0.appVersion,
                locale: $0.locale,
                channel: $0.channel.rawValue
            )
        })
        var request = URLRequest(url: try makeURL("/v1/analytics/events"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder.aiEncoder.encode(payload)
        try await applyHeaders(to: &request)
        do {
            _ = try await send(request, responseType: UsageAnalyticsUploadResponse.self)
        } catch AIClientError.httpStatus(401) where settings.usesSessionTokens {
            AIAuthenticationStore.shared.reset()
            try await applyHeaders(to: &request)
            _ = try await send(request, responseType: UsageAnalyticsUploadResponse.self)
        }
    }

    func deleteUsageEvents() async throws {
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.missingAPIKey
        }
        var request = URLRequest(url: try makeURL("/v1/analytics/events"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 20
        try await applyHeaders(to: &request)
        do {
            _ = try await send(request, responseType: UsageAnalyticsDeleteResponse.self)
        } catch AIClientError.httpStatus(401) where settings.usesSessionTokens {
            AIAuthenticationStore.shared.reset()
            try await applyHeaders(to: &request)
            _ = try await send(request, responseType: UsageAnalyticsDeleteResponse.self)
        }
    }

    func analyzeMealImage(
        imageData: Data,
        mealType: MealType,
        memo: String,
        coach: AIRequestCoachContext? = nil
    ) async throws -> MealAIDraft {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--stub-meal-ai") {
            return MealAIDraft(
                mealName: L10n.string("health_meals_body_ai.91d223d5b73b", fallback: "鶏むね肉定食"),
                calories: 483,
                protein: 34,
                fat: 14,
                carbs: 55,
                confidence: "medium",
                comment: L10n.string("health_meals_body_ai.5abcc8fb6635", fallback: "テスト用の推定値です。"),
                items: []
            )
        }
        #endif

        let uploadData = try await prepareImageForUpload(imageData)
        let request = MealAnalysisRequest(
            imageBase64: uploadData.base64EncodedString(),
            mealType: mealType.rawValue,
            memo: memo.aiCompactedForUpload(maximumCharacters: Self.maximumAIMemoCharacters),
            coach: coach,
            locale: AppLanguagePreference.aiLocaleIdentifier
        )
        let draft = try await post("/v1/meals/analyze-image", body: request, responseType: MealAIDraft.self, timeout: Self.inferenceTimeout)
        return draft.reconciledFromItems()
    }

    func analyzeMealText(
        items: [String],
        mealType: MealType,
        memo: String,
        coach: AIRequestCoachContext? = nil
    ) async throws -> MealAIDraft {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--stub-meal-text-ai") {
            return MealAIDraft(
                mealName: L10n.string("health_meals_body_ai.704be7784e42", fallback: "白ごはん・鶏むね肉・味噌汁"),
                calories: 427,
                protein: 33.9,
                fat: 3.4,
                carbs: 56,
                confidence: "high",
                comment: L10n.string("health_meals_body_ai.5abcc8fb6635", fallback: "テスト用の推定値です。"),
                items: [
                    MealAIDraftItem(
                        name: L10n.string("health_meals_body_ai.54adbdc92e60", fallback: "白ごはん"),
                        amount: "150g",
                        calories: 234,
                        protein: 3.9,
                        fat: 0.5,
                        carbs: 53
                    ),
                    MealAIDraftItem(
                        name: L10n.string("health_meals_body_ai.8690f6def93b", fallback: "鶏むね肉（皮なし）"),
                        amount: "120g",
                        calories: 163,
                        protein: 28,
                        fat: 2.4,
                        carbs: 0
                    ),
                    MealAIDraftItem(
                        name: L10n.string("health_meals_body_ai.f93ac37a9b58", fallback: "味噌汁"),
                        amount: L10n.string("health_meals_body_ai.238a52b5a2f7", fallback: "1杯"),
                        calories: 30,
                        protein: 2,
                        fat: 0.5,
                        carbs: 3
                    ),
                ]
            )
        }
        #endif

        let normalizedItems = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.aiCompactedForUpload(maximumCharacters: Self.maximumMealItemCharacters) }
        guard !normalizedItems.isEmpty else { throw AIClientError.emptyMealItems }

        let request = MealTextAnalysisRequest(
            items: Array(normalizedItems.prefix(20)),
            mealType: mealType.rawValue,
            memo: memo.aiCompactedForUpload(maximumCharacters: Self.maximumAIMemoCharacters),
            coach: coach,
            locale: AppLanguagePreference.aiLocaleIdentifier
        )
        let draft = try await post("/v1/meals/analyze-text", body: request, responseType: MealAIDraft.self, timeout: Self.inferenceTimeout)
        return draft.reconciledFromItems()
    }

    func analyzeBodyPhoto(imageData: Data, angle: BodyPhotoAngle, memo: String) async throws -> BodyPhotoAIComment {
        let uploadData = try await prepareImageForUpload(imageData)
        let request = BodyPhotoAnalysisRequest(
            imageBase64: uploadData.base64EncodedString(),
            angle: angle.rawValue,
            memo: memo.aiCompactedForUpload(maximumCharacters: Self.maximumAIMemoCharacters),
            responseLocale: AppLanguagePreference.aiLocaleIdentifier
        )
        return try await post("/v1/body-photos/analyze", body: request, responseType: BodyPhotoAIComment.self, timeout: Self.inferenceTimeout)
    }

    func analyzeBodyPhotos(
        _ photos: [BodyPhotoAnalysisInput],
        memo: String,
        context: BodyPhotoAnalysisContext? = nil,
        previousPhotos: [BodyPhotoAnalysisInput] = []
    ) async throws -> BodyPhotoAIComment {
        guard !photos.isEmpty else { throw AIClientError.invalidImage }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--stub-body-photo-ai") {
            try await Task.sleep(for: .milliseconds(250))
            return BodyPhotoAIComment(
                summary: L10n.string("health_meals_body_ai.f2d1aefd4747", fallback: "複数方向の写真をまとめて確認しました。撮影条件を揃えて継続すると比較しやすくなります。"),
                abdomen: L10n.string("health_meals_body_ai.8381775621bd", fallback: "正面と横から腹部の状態を確認しました。"),
                waist: L10n.string("health_meals_body_ai.1f351a03b1e3", fallback: "正面と背面を合わせてウエストまわりを確認しました。"),
                posture: L10n.string("health_meals_body_ai.e4606eba2adb", fallback: "方向による姿勢の違いを確認しました。"),
                score: nil,
                confidence: "medium"
            )
        }
        #endif

        var requestPhotos: [BodyPhotoSetAnalysisPhotoRequest] = []
        for photo in photos.prefix(BodyPhotoAngle.allCases.count) {
            let uploadData = try await prepareImageForUpload(photo.imageData)
            requestPhotos.append(
                BodyPhotoSetAnalysisPhotoRequest(
                    imageBase64: uploadData.base64EncodedString(),
                    angle: photo.angle.rawValue
                )
            )
        }

        var comparisonPhotos: [BodyPhotoSetAnalysisPhotoRequest] = []
        for photo in previousPhotos.prefix(BodyPhotoAngle.allCases.count) {
            let uploadData = try await prepareImageForUpload(photo.imageData)
            comparisonPhotos.append(
                BodyPhotoSetAnalysisPhotoRequest(
                    imageBase64: uploadData.base64EncodedString(),
                    angle: photo.angle.rawValue
                )
            )
        }

        let request = BodyPhotoSetAnalysisRequest(
            photos: requestPhotos,
            comparisonPhotos: comparisonPhotos,
            memo: memo.aiCompactedForUpload(maximumCharacters: Self.maximumAIMemoCharacters),
            context: context,
            responseLocale: AppLanguagePreference.aiLocaleIdentifier
        )
        return try await post(
            "/v1/body-photos/analyze-set",
            body: request,
            responseType: BodyPhotoAIComment.self,
            timeout: Self.inferenceTimeout
        )
    }

    func generateWeeklyReport(payload: WeeklyReportRequest) async throws -> WeeklyReportResponse {
        return try await post("/v1/reports/weekly", body: payload, responseType: WeeklyReportResponse.self, timeout: Self.inferenceTimeout)
    }

    func generateMonthlyReport(payload: WeeklyReportRequest) async throws -> WeeklyReportResponse {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--stub-monthly-ai") {
            try await Task.sleep(for: .milliseconds(250))
            return WeeklyReportResponse(
                inputSummary: L10n.string("health_meals_body_ai.c80ab7033a1d", fallback: "直近30日の身体、食事、トレーニング記録を確認しました。"),
                outputComment: L10n.string("health_meals_body_ai.b869cf466465", fallback: "継続できたトレーニングを軸に、回復とのバランスを確認できました。"),
                actionSuggestion: L10n.string("health_meals_body_ai.86f4e09eea0c", fallback: "1. 週3回を維持\n2. たんぱく質目標を記録\n3. 月末に体型写真を比較")
            )
        }
        #endif
        return try await post("/v1/reports/monthly", body: payload, responseType: WeeklyReportResponse.self, timeout: Self.inferenceTimeout)
    }

    func chat(payload: CoachChatRequest) async throws -> CoachChatResponse {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--stub-ai-trainer") {
            try await Task.sleep(for: .milliseconds(250))
            if payload.message.contains("[BODYMODE_DAILY_JSON]") {
                let actionLines = payload.message
                    .split(separator: "\n")
                    .filter { $0.contains("id=") && $0.contains("category=") }
                let actions = actionLines.compactMap { line -> String? in
                    let text = String(line)
                    guard let idRange = text.range(of: "id="),
                          let categoryRange = text.range(of: ", category="),
                          let titleRange = text.range(of: ", title=") else { return nil }
                    let id = String(text[idRange.upperBound..<categoryRange.lowerBound])
                    let category = String(text[categoryRange.upperBound..<titleRange.lowerBound])
                    let remainder = text[titleRange.upperBound...]
                    let title = remainder.split(separator: ",", maxSplits: 1).first.map(String.init) ?? L10n.string("health_meals_body_ai.da700eb35e0e", fallback: "今日の行動")
                    return L10n.string(
                        "health_meals_body_ai.5ffda91dfa7a",
                        fallback: "{\"id\":\"{{value1}}\",\"category\":\"{{value2}}\",\"title\":\"{{value3}}\",\"target\":0,\"rationale\":\"記録と目標を確認しました\"}",
                        values: [id, category, title]
                    )
                }
                return CoachChatResponse(
                    reply: L10n.string(
                        "health_meals_body_ai.320cd1a54732",
                        fallback: "{\"keep_existing\":true,\"readiness_level\":\"normal\",\"summary\":\"今日の提案をこのまま進めましょう。\",\"change_reason\":\"\",\"actions\":[{{value1}}]}",
                        values: [actions.joined(separator: ",")]
                    ),
                    evidence: [
                        CoachEvidenceCitation(
                            id: "PMID:38705654",
                            title: "Resistance training prescription review",
                            year: 2024,
                            studyType: "systematic_review",
                            confidence: "moderate",
                            url: "https://pubmed.ncbi.nlm.nih.gov/38705654/",
                            doi: "",
                            relevance: 0.88
                        )
                    ],
                    evidenceStatus: CoachEvidenceStatus(
                        state: "ready",
                        confidence: "moderate",
                        lastUpdatedAt: "2026-08-19",
                        searchedDocuments: 2_836,
                        matchedDocuments: 1
                    )
                )
            }
            if payload.message.contains("[BODYMODE_PLAN_JSON]") {
                let stubPlan: [String: Any] = [
                    "name": L10n.string("health_meals_body_ai.646815b94145", fallback: "AI 全身バランス"),
                    "summary": L10n.string("health_meals_body_ai.776a04d597c7", fallback: "目標と利用できる器具に合わせた確認用プランです。"),
                    "exercises": [
                        ["exercise_name": L10n.string("health_meals_body_ai.a535761413f5", fallback: "チェストプレス"), "sets": 3, "reps": 10, "weight": 30, "rest_seconds": 90],
                        ["exercise_name": L10n.string("health_meals_body_ai.2bb02e3fab46", fallback: "ラットプルダウン"), "sets": 3, "reps": 10, "weight": 30, "rest_seconds": 90],
                        ["exercise_name": L10n.string("health_meals_body_ai.a1cf4f52b620", fallback: "レッグプレス"), "sets": 3, "reps": 12, "weight": 50, "rest_seconds": 120]
                    ]
                ]
                let stubData = try JSONSerialization.data(withJSONObject: stubPlan, options: [.sortedKeys])
                guard let stubReply = String(data: stubData, encoding: .utf8) else {
                    throw AIClientError.invalidResponse
                }
                return CoachChatResponse(
                    reply: stubReply
                )
            }
            return CoachChatResponse(
                reply: """
                次回は小刻みに重量を上げてもよさそうです。

                【判断】
                ・記録では余裕を持って完遂できています
                ・大幅な増量よりフォーム維持を優先します

                【次にやること】
                1. 重量を最小単位だけ上げる
                2. 各セットのRPEを確認する
                """,
                memoryCandidates: [
                    CoachMemoryCandidate(
                        content: L10n.string("health_meals_body_ai.513dcf9887ac", fallback: "重量は小刻みに上げたい"),
                        reason: L10n.string("health_meals_body_ai.3f6a42bf20f8", fallback: "今後の重量提案に役立つため")
                    )
                ],
                evidence: [
                    CoachEvidenceCitation(
                        id: "PMID:12345678",
                        title: "Resistance training volume and muscle hypertrophy",
                        year: 2025,
                        studyType: "systematic_review",
                        confidence: "high",
                        url: "https://pubmed.ncbi.nlm.nih.gov/12345678/",
                        doi: "10.1000/bodymode-test",
                        relevance: 0.91
                    )
                ],
                evidenceStatus: CoachEvidenceStatus(
                    state: "ready",
                    confidence: "high",
                    lastUpdatedAt: "2026-08-14T00:00:00Z",
                    searchedDocuments: 42
                )
            )
        }
        #endif

        let trimmedMessage = payload.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw AITrainerError.emptyMessage }
        guard trimmedMessage.count <= CoachChatRequest.maximumMessageCharacters else {
            throw AITrainerError.messageTooLong
        }

        var initialRequest = payload.constrainedForInitialRequest()
        initialRequest.message = trimmedMessage
        do {
            return try await post(
                "/v1/agents/chat",
                body: initialRequest,
                responseType: CoachChatResponse.self,
                timeout: Self.inferenceTimeout
            )
        } catch AIClientError.httpStatus(413) {
            var retryRequest = payload.compactedForRetry()
            retryRequest.message = trimmedMessage
            do {
                return try await post(
                    "/v1/agents/chat",
                    body: retryRequest,
                    responseType: CoachChatResponse.self,
                    timeout: Self.inferenceTimeout
                )
            } catch AIClientError.httpStatus(413) {
                throw AITrainerError.contextTooLarge
            } catch {
                throw trainerError(from: error)
            }
        } catch {
            throw trainerError(from: error)
        }
    }

    func makeBackgroundChatUpload(
        payload: CoachChatRequest,
        compacted: Bool,
        requestID: UUID? = nil
    ) async throws -> AIBackgroundChatUpload {
        guard settings.isEnabled else {
            throw AIClientError.disabled
        }
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.missingAPIKey
        }

        let trimmedMessage = payload.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw AITrainerError.emptyMessage }
        guard trimmedMessage.count <= CoachChatRequest.maximumMessageCharacters else {
            throw AITrainerError.messageTooLong
        }

        var preparedPayload = compacted
            ? payload.compactedForRetry()
            : payload.constrainedForInitialRequest()
        preparedPayload.message = trimmedMessage

        var request = URLRequest(url: try makeURL("/v1/agents/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.inferenceTimeout
        if let requestID {
            request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Request-ID")
        }
        try await applyHeaders(to: &request)
        return AIBackgroundChatUpload(
            request: request,
            body: try JSONEncoder.aiEncoder.encode(preparedPayload)
        )
    }

    private func get<Response: Decodable>(_ path: String, responseType: Response.Type, timeout: TimeInterval) async throws -> Response {
        guard settings.isEnabled else {
            throw AIClientError.disabled
        }
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.missingAPIKey
        }
        let url = try makeURL(path)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        try await applyHeaders(to: &request)
        do {
            return try await send(request, responseType: responseType)
        } catch AIClientError.httpStatus(401) where settings.usesSessionTokens {
            AIAuthenticationStore.shared.reset()
            try await applyHeaders(to: &request)
            return try await send(request, responseType: responseType)
        }
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, responseType: Response.Type, timeout: TimeInterval) async throws -> Response {
        guard settings.isEnabled else {
            throw AIClientError.disabled
        }
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.missingAPIKey
        }
        let url = try makeURL(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder.aiEncoder.encode(body)
        try await applyHeaders(to: &request)
        var transientRetryCount = 0

        while true {
            do {
                do {
                    return try await send(request, responseType: responseType)
                } catch AIClientError.httpStatus(401) where settings.usesSessionTokens {
                    AIAuthenticationStore.shared.reset()
                    try await applyHeaders(to: &request)
                    return try await send(request, responseType: responseType)
                }
            } catch let error as AIClientError where transientRetryCount < Self.maximumTransientInferenceRetries && error.isTransientInferenceFailure {
                transientRetryCount += 1
                let delay = error.transientRetryDelay(attempt: transientRetryCount)
                record(
                    error,
                    category: "ai.retry",
                    request: request,
                    additionalMetadata: [
                        "attempt": String(transientRetryCount),
                        "delay_seconds": String(delay)
                    ]
                )
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
        }
    }

    private func applyHeaders(to request: inout URLRequest) async throws {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.value(forHTTPHeaderField: "X-Request-ID") == nil {
            request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        }
        let channel = UsageDistributionChannel.current().rawValue
        request.setValue(channel, forHTTPHeaderField: Self.distributionChannelHeader)
        request.setValue(channel, forHTTPHeaderField: Self.distributionChannelFallbackHeader)
        request.setValue("Bearer \(try await authorizationCredential())", forHTTPHeaderField: "Authorization")
    }

    private func authorizationCredential() async throws -> String {
        guard settings.usesSessionTokens else { return settings.apiKey }
        let normalizedBaseURL = settings.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = AIAuthenticationStore.shared.usableToken(for: normalizedBaseURL) {
            return cached.value
        }

        if AIAccountPolicy.isRequired || SecureSettingsStore.hasAIAccount {
            throw AIClientError.accountSignInRequired
        }

        let cached = try await AIAuthenticationStore.shared.coordinatedToken(for: normalizedBaseURL) {
            try await requestAccessToken(normalizedBaseURL: normalizedBaseURL)
        }
        return cached.value
    }

    private func requestAccessToken(normalizedBaseURL: String) async throws -> AICachedAccessToken {
        var request = URLRequest(url: try makeURL("/v1/auth/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        request.httpBody = try JSONEncoder.aiEncoder.encode(
            AIAccessTokenRequest(
                installationID: SecureSettingsStore.installationID(),
                appVersion: version
            )
        )
        let response = try await send(request, responseType: AIAccessTokenResponse.self)
        let cached = AICachedAccessToken(
            value: response.accessToken,
            baseURLString: normalizedBaseURL,
            expiresAt: Date().addingTimeInterval(max(0, response.expiresIn))
        )
        return cached
    }

    private func makeURL(_ path: String) throws -> URL {
        guard let baseURL,
              let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.user == nil,
              baseURL.password == nil,
              let host = baseURL.host,
              !host.isEmpty else {
            throw AIClientError.invalidBaseURL
        }
        if scheme == "http", !host.isLocalAIHost {
            throw AIClientError.insecureRemoteHTTPHost
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let requestPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = "/" + [basePath, requestPath].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components?.url else {
            throw AIClientError.invalidBaseURL
        }
        return url
    }

    private func send<Response: Decodable>(_ request: URLRequest, responseType: Response.Type) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            let clientError = AIClientError.requestFailed(error)
            recordTransport(error, request: request)
            throw clientError
        } catch {
            let clientError = AIClientError.transport(error.localizedDescription)
            record(clientError, category: "ai.transport", request: request)
            throw clientError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let error = AIClientError.invalidResponse
            record(error, category: "ai.response", request: request)
            throw error
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let error = AIClientError.responseError(
                statusCode: httpResponse.statusCode,
                data: data
            )
            record(
                error,
                category: "ai.http",
                request: request,
                additionalMetadata: ["status_code": String(httpResponse.statusCode)]
            )
            throw error
        }

        do {
            return try JSONDecoder.aiDecoder.decode(Response.self, from: data)
        } catch {
            let clientError = AIClientError.decodingFailed(error.localizedDescription)
            record(clientError, category: "ai.decoding", request: request)
            throw clientError
        }
    }

    private func recordTransport(_ error: URLError, request: URLRequest) {
        record(
            AIClientError.requestFailed(error),
            category: "ai.transport",
            request: request,
            additionalMetadata: [
                "url_error_code": String(error.errorCode),
                "url_error_name": error.code.diagnosticName,
                "transport_detail": error.localizedDescription
            ]
        )
    }

    private func record(
        _ error: AIClientError,
        category: String,
        request: URLRequest,
        additionalMetadata: [String: String] = [:]
    ) {
        var metadata = additionalMetadata
        metadata["error"] = error.localizedDescription
        metadata["error_type"] = String(reflecting: type(of: error))
        metadata["path"] = request.url?.path ?? "unknown"
        metadata["method"] = request.httpMethod ?? "unknown"
        metadata["timeout_seconds"] = String(Int(request.timeoutInterval))
        metadata["request_id"] = request.value(forHTTPHeaderField: "X-Request-ID") ?? "unknown"
        AppDiagnostics.shared.record(
            category: category,
            message: "AI API request failed",
            metadata: metadata
        )
    }

    private func trainerError(from error: Error) -> Error {
        guard let clientError = error as? AIClientError else { return error }
        switch clientError {
        case .httpStatus(401), .disabled, .missingAPIKey, .invalidBaseURL,
             .insecureRemoteHTTPHost:
            return clientError
        case .httpStatus(413):
            return AITrainerError.contextTooLarge
        case .httpStatus(422):
            return AITrainerError.invalidRequest
        case .requestFailed, .transport:
            return AITrainerError.connection
        default:
            return clientError
        }
    }

    private func prepareImageForUpload(_ imageData: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try AIImageUploadProcessor.jpegData(from: imageData)
        }.value
    }
}

private extension URLError.Code {
    var diagnosticName: String {
        switch self {
        case .cancelled: "cancelled"
        case .timedOut: "timedOut"
        case .unsupportedURL: "unsupportedURL"
        case .cannotFindHost: "cannotFindHost"
        case .cannotConnectToHost: "cannotConnectToHost"
        case .networkConnectionLost: "networkConnectionLost"
        case .dnsLookupFailed: "dnsLookupFailed"
        case .notConnectedToInternet: "notConnectedToInternet"
        case .badURL: "badURL"
        default: "rawValue:\(rawValue)"
        }
    }
}

enum AIClientError: LocalizedError {
    case disabled
    case missingAPIKey
    case invalidBaseURL
    case insecureRemoteHTTPHost
    case invalidImage
    case emptyMealItems
    case invalidResponse
    case httpStatus(Int)
    case quotaExceeded(AIQuotaErrorDetail)
    case serverPolicy(AIServerPolicyErrorDetail)
    case requestFailed(URLError)
    case transport(String)
    case decodingFailed(String)
    case secureStorageFailed
    case accountSignInRequired
    case insufficientCredits(AICreditErrorDetail)
    case rewardedAdVerificationPending

    var isTransientInferenceFailure: Bool {
        switch self {
        case .serverPolicy(let detail):
            return ["server_busy", "model_unavailable", "burst_rate_limited"].contains(detail.code)
        case .httpStatus(let statusCode):
            return [429, 502, 503, 504, 525].contains(statusCode)
        case .requestFailed(let error):
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .networkConnectionLost, .notConnectedToInternet, .timedOut:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    func transientRetryDelay(attempt: Int) -> Int {
        let exponentialDelay = min(30, 1 << max(0, attempt - 1))
        if case .serverPolicy(let detail) = self, let retryAfter = detail.retryAfter {
            return min(60, max(exponentialDelay, retryAfter))
        }
        return exponentialDelay
    }

    var errorDescription: String? {
        switch self {
        case .disabled:
            L10n.string("health_meals_body_ai.35adcbc0257c", fallback: "AI利用設定がオフです。")
        case .missingAPIKey:
            L10n.string("health_meals_body_ai.7ab71e403577", fallback: "APIキーが設定されていません。")
        case .invalidBaseURL:
            L10n.string("health_meals_body_ai.1e8bd0778f84", fallback: "AIサーバーURLが不正です。")
        case .insecureRemoteHTTPHost:
            L10n.string("health_meals_body_ai.fda0d26cd60c", fallback: "外部サーバーへのHTTP接続は許可されていません。")
        case .invalidImage:
            L10n.string("health_meals_body_ai.f2264d502bc8", fallback: "選択した画像を解析用に変換できませんでした。")
        case .emptyMealItems:
            L10n.string("health_meals_body_ai.f60350613f0c", fallback: "食べたものを1件以上入力してください。")
        case .invalidResponse:
            L10n.string("health_meals_body_ai.b419c3f5c523", fallback: "AIサーバーの応答を読めませんでした。")
        case .httpStatus(let statusCode):
            httpStatusMessage(statusCode)
        case .quotaExceeded(let detail):
            detail.message
        case .serverPolicy(let detail):
            detail.message
        case .requestFailed(let error):
            requestFailureMessage(error)
        case .transport:
            L10n.string("health_meals_body_ai.a8806f356dd5", fallback: "AIサーバーに接続できません。時間をおいて再試行してください。")
        case .decodingFailed:
            L10n.string("health_meals_body_ai.59dc9f20a101", fallback: "AIサーバーのJSON形式がアプリの想定と違います。")
        case .secureStorageFailed:
            L10n.string("health_meals_body_ai.19d7834ec7ec", fallback: "AI接続情報を安全に保存できませんでした。")
        case .accountSignInRequired:
            L10n.string("ai_credit.sign_in_required", fallback: "AI機能を使うにはAppleで登録してください。")
        case .insufficientCredits(let detail):
            detail.message
        case .rewardedAdVerificationPending:
            L10n.string("ai_credit.reward_pending", fallback: "動画の確認に時間がかかっています。確認後にクレジットへ反映されます。")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .disabled:
            L10n.string("health_meals_body_ai.bff7fb34d198", fallback: "設定で「AI機能を使う」をオンにしてください。手動記録はこのまま保存できます。")
        case .missingAPIKey:
            L10n.string("health_meals_body_ai.c1902956ff42", fallback: "設定画面でAIサーバーのAPIキーを入力してください。")
        case .invalidBaseURL:
            L10n.string("health_meals_body_ai.8cffd32caabd", fallback: "URLはhttps://から始めてください。ローカル開発ではlocalhost、LAN IP、Tailscale名のHTTPも利用できます。")
        case .insecureRemoteHTTPHost:
            L10n.string("health_meals_body_ai.325f72991867", fallback: "HTTPはlocalhost、LAN、Tailscale内だけ利用できます。外部サーバーにはHTTPSを使用してください。")
        case .invalidImage:
            L10n.string("health_meals_body_ai.0a842afdf860", fallback: "JPEGまたはPNG画像を選び直してください。")
        case .emptyMealItems:
            L10n.string("health_meals_body_ai.39d757a8749c", fallback: "食品名と、分かれば量も入力してください。")
        case .invalidResponse:
            L10n.string("health_meals_body_ai.cbf6c6a18f68", fallback: "設定したサーバーURLが正しいか確認してください。")
        case .httpStatus(let statusCode):
            httpStatusRecovery(statusCode)
        case .quotaExceeded(let detail):
            detail.resetDescription
        case .serverPolicy(let detail):
            detail.recoveryDescription
        case .requestFailed(let error):
            requestFailureRecovery(error)
        case .transport:
            L10n.string("health_meals_body_ai.1a249c16e07b", fallback: "ネットワーク状態とサーバーURLを確認してから再試行してください。")
        case .decodingFailed(let message):
            L10n.string("health_meals_body_ai.b0dd483bd6a7", fallback: "APIサーバーのバージョンを確認してください。詳細: {{value1}}", values: [String(describing: message)])
        case .secureStorageFailed:
            L10n.string("health_meals_body_ai.ed052a8c3035", fallback: "端末を再起動してから再試行してください。")
        case .accountSignInRequired:
            L10n.string("ai_credit.sign_in_recovery", fallback: "AI画面からAppleで登録すると、初回クレジットを受け取れます。手動記録は登録なしで使えます。")
        case .insufficientCredits:
            L10n.string("ai_credit.insufficient_recovery", fallback: "広告を見て獲得するか、クレジットを購入してください。手動記録はそのまま使えます。")
        case .rewardedAdVerificationPending:
            L10n.string("ai_credit.reward_pending_recovery", fallback: "AI画面を開き直すと最新残高を確認できます。もう一度動画を見る必要はありません。")
        }
    }

    static func presentation(for error: Error) -> AIErrorPresentation {
        let localizedError = error as? LocalizedError
        return AIErrorPresentation(
            message: localizedError?.errorDescription ?? error.localizedDescription,
            recovery: localizedError?.recoverySuggestion
        )
    }

    static func responseError(statusCode: Int, data: Data) -> AIClientError {
        if statusCode == 402,
           let envelope = try? JSONDecoder.aiDecoder.decode(AICreditErrorEnvelope.self, from: data) {
            return .insufficientCredits(envelope.detail)
        }
        if statusCode == 429,
           let envelope = try? JSONDecoder.aiDecoder.decode(AIQuotaErrorEnvelope.self, from: data) {
            return .quotaExceeded(envelope.detail)
        }
        if let envelope = try? JSONDecoder.aiDecoder.decode(AIServerPolicyErrorEnvelope.self, from: data) {
            if envelope.detail.code == "account_sign_in_required" {
                return .accountSignInRequired
            }
            return .serverPolicy(envelope.detail)
        }
        return .httpStatus(statusCode)
    }

    private func httpStatusMessage(_ statusCode: Int) -> String {
        switch statusCode {
        case 401:
            L10n.string("health_meals_body_ai.033555b3e02e", fallback: "AIの認証情報が不正か、期限切れです。")
        case 429:
            L10n.string("health_meals_body_ai.ac02ca6a6ac9", fallback: "AIの利用が一時的に集中しています。")
        case 404:
            L10n.string("health_meals_body_ai.76691cf4f1f7", fallback: "AIサーバーに必要なAPIが見つかりません。")
        case 503:
            L10n.string("health_meals_body_ai.072ba0df4357", fallback: "AIモデルが利用できないか、画像解析に失敗しました。")
        case 500..<600:
            L10n.string("health_meals_body_ai.ccdad25cb2a2", fallback: "AIサーバー側でエラーが発生しました: {{value1}}", values: [String(describing: statusCode)])
        default:
            L10n.string("health_meals_body_ai.9cf22e4b7f64", fallback: "AIサーバーがエラーを返しました: {{value1}}", values: [String(describing: statusCode)])
        }
    }

    private func httpStatusRecovery(_ statusCode: Int) -> String {
        switch statusCode {
        case 401:
            L10n.string("health_meals_body_ai.b5035ba9b9f0", fallback: "設定画面の接続情報を確認して再試行してください。短期認証は自動更新されます。")
        case 429:
            L10n.string("health_meals_body_ai.859914a154e7", fallback: "1分ほど待ってから再試行してください。")
        case 404:
            L10n.string("health_meals_body_ai.9331cab52986", fallback: "Base URLとAPIサーバーのバージョンを確認してください。")
        case 503:
            L10n.string("health_meals_body_ai.9f8623da2f24", fallback: "時間をおいて再試行してください。続く場合はAIサーバーのモデル状態を確認してください。")
        case 500..<600:
            L10n.string("health_meals_body_ai.88e74f83b764", fallback: "時間をおいて再試行してください。続く場合はAIサーバーのログを確認してください。")
        default:
            L10n.string("health_meals_body_ai.5a4c72805744", fallback: "サーバーURL、APIキー、APIサーバーの稼働状態を確認してください。")
        }
    }

    private func requestFailureMessage(_ error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .networkConnectionLost, .notConnectedToInternet, .timedOut:
            L10n.string("health_meals_body_ai.a8806f356dd5", fallback: "AIサーバーに接続できません。時間をおいて再試行してください。")
        case .unsupportedURL, .badURL:
            L10n.string("health_meals_body_ai.1e8bd0778f84", fallback: "AIサーバーURLが不正です。")
        default:
            L10n.string("health_meals_body_ai.a8806f356dd5", fallback: "AIサーバーに接続できません。時間をおいて再試行してください。")
        }
    }

    private func requestFailureRecovery(_ error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .networkConnectionLost, .notConnectedToInternet, .timedOut:
            L10n.string("health_meals_body_ai.91022a59299a", fallback: "ネットワークとAIサーバーの稼働状態を確認してください。AI処理は最大240秒かかる場合があります。")
        case .unsupportedURL, .badURL:
            L10n.string("health_meals_body_ai.b8e6974a0b21", fallback: "URLはhttps://から始めてください。ローカル開発時のみhttp://も利用できます。")
        default:
            L10n.string("health_meals_body_ai.c85e8d637553", fallback: "ネットワーク状態とサーバーURLを確認してください。")
        }
    }
}

private extension String {
    func aiCompactedForUpload(maximumCharacters: Int) -> String {
        guard count > maximumCharacters else { return self }
        let marker = " … "
        let available = max(2, maximumCharacters - marker.count)
        let headCount = max(1, Int(Double(available) * 0.65))
        let tailCount = max(1, available - headCount)
        return String(prefix(headCount)) + marker + String(suffix(tailCount))
    }

    var isLocalAIHost: Bool {
        let normalized = lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        if normalized == "localhost"
            || normalized == "::1"
            || normalized.hasSuffix(".local")
            || !normalized.contains(".") {
            return true
        }

        if normalized.hasPrefix("fc")
            || normalized.hasPrefix("fd")
            || normalized.hasPrefix("fe80:") {
            return true
        }

        let parts = normalized.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ 0...255 ~= $0 }) else {
            return false
        }

        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (169, 254), (192, 168):
            return true
        case (172, 16...31), (100, 64...127):
            return true
        default:
            return false
        }
    }
}

struct AIErrorPresentation: Hashable {
    var message: String
    var recovery: String?
}

struct AIBackgroundChatUpload {
    var request: URLRequest
    var body: Data
}

struct AIHealthResponse: Codable, Hashable {
    var status: String
    var model: String
    var calorieModelAvailable: Bool?
    var ollamaReachable: Bool
    var modelAvailable: Bool?
    var message: String?

    var isReady: Bool {
        status.lowercased() == "ok"
            && (calorieModelAvailable ?? true)
            && ollamaReachable
            && (modelAvailable ?? true)
    }

    enum CodingKeys: String, CodingKey {
        case status
        case model
        case calorieModelAvailable = "calorie_model_available"
        case ollamaReachable = "ollama_reachable"
        case modelAvailable = "model_available"
        case message
    }
}

struct AIUsageSummary: Codable, Hashable {
    var generatedAt: String
    var enforced: Bool?
    var features: [AIUsageFeature]
    var credits: AICreditSummary?

    var isEnforced: Bool { enforced ?? true }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case enforced
        case features
        case credits
    }
}

struct AICreditErrorDetail: Codable, Hashable {
    var code: String
    var message: String
    var feature: String
    var cost: Int
    var balance: AICreditBalance
}

private struct AICreditErrorEnvelope: Decodable {
    var detail: AICreditErrorDetail
}

enum AIAccountPolicy {
    static var isRequired: Bool {
        if let value = Bundle.main.object(forInfoDictionaryKey: "BodyModeAIRequiresAccount") as? Bool {
            return value
        }
        return switch (Bundle.main.object(forInfoDictionaryKey: "BodyModeAIRequiresAccount") as? String)?.lowercased() {
        case "yes", "true", "1": true
        default: false
        }
    }
}

struct AIUsageFeature: Codable, Hashable, Identifiable {
    var feature: String
    var used: Int
    var limit: Int
    var remaining: Int
    var resetAt: String
    var windowSeconds: Int

    var id: String { feature }

    var displayName: String {
        switch feature {
        case "chat": L10n.string("health_meals_body_ai.bb243f7c92b4", fallback: "トレーナー相談")
        case "meal": L10n.string("health_meals_body_ai.3c90f2799f7f", fallback: "食事解析")
        case "body_photo": L10n.string("health_meals_body_ai.f47d6f2e6ec3", fallback: "体型写真")
        case "plan_generation": L10n.string("health_meals_body_ai.1c1f8aa404fd", fallback: "計画作成")
        case "daily_recommendation": L10n.string("health_meals_body_ai.8f9454672f34", fallback: "今日の提案")
        case "weekly_report": L10n.string("health_meals_body_ai.d9a3c67cccb6", fallback: "週次レポート")
        case "monthly_report": L10n.string("health_meals_body_ai.804513c997c7", fallback: "月次レポート")
        default: L10n.string("health_meals_body_ai.8883e756324e", fallback: "AI機能")
        }
    }

    enum CodingKeys: String, CodingKey {
        case feature, used, limit, remaining
        case resetAt = "reset_at"
        case windowSeconds = "window_seconds"
    }
}

struct AIQuotaErrorDetail: Codable, Hashable {
    var code: String
    var reason: String?
    var message: String
    var feature: String
    var limit: Int
    var remaining: Int
    var resetAt: String
    var windowSeconds: Int

    var resetDescription: String {
        guard let date = ISO8601DateFormatter().date(from: resetAt) else {
            return L10n.string("health_meals_body_ai.a91961dc43c1", fallback: "リセット後にもう一度お試しください。手動記録は引き続き利用できます。")
        }
        return L10n.string("health_meals_body_ai.f2a88880f646", fallback: "{{value1}}にリセットされます。手動記録は引き続き利用できます。", values: [String(describing: date.formatted(date: .abbreviated, time: .shortened))])
    }

    enum CodingKeys: String, CodingKey {
        case code, reason, message, feature, limit, remaining
        case resetAt = "reset_at"
        case windowSeconds = "window_seconds"
    }
}

private struct AIQuotaErrorEnvelope: Decodable {
    var detail: AIQuotaErrorDetail
}

struct AIServerPolicyErrorDetail: Codable, Hashable {
    var code: String
    var message: String
    var retryAfter: Int?

    var recoveryDescription: String {
        let wait = retryAfter.map { L10n.string("health_meals_body_ai.b9d2ae097ed2", fallback: "約{{value1}}秒待ってから", values: [String(describing: $0)]) } ?? L10n.string("health_meals_body_ai.1b8717eea915", fallback: "時間をおいて")
        switch code {
        case "burst_rate_limited":
            return L10n.string("health_meals_body_ai.35a91d364b5f", fallback: "{{value1}}再試行してください。手動記録は引き続き利用できます。", values: [String(describing: wait)])
        case "server_busy":
            return L10n.string("health_meals_body_ai.d0c704c61c9b", fallback: "現在は利用枠ではなくサーバー混雑です。{{value1}}再試行してください。", values: [String(describing: wait)])
        default:
            return L10n.string("health_meals_body_ai.a0a1a2fec576", fallback: "{{value1}}再試行してください。続く場合はAIサーバーの稼働状態を確認してください。", values: [String(describing: wait)])
        }
    }

    enum CodingKeys: String, CodingKey {
        case code, message
        case retryAfter = "retry_after"
    }
}

private struct AIServerPolicyErrorEnvelope: Decodable {
    var detail: AIServerPolicyErrorDetail
}

private struct MealAnalysisRequest: Encodable {
    var imageBase64: String
    var mealType: String
    var memo: String
    var coach: AIRequestCoachContext?
    var locale: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mealType = "meal_type"
        case memo
        case coach
        case locale
    }
}

private struct MealTextAnalysisRequest: Encodable {
    var items: [String]
    var mealType: String
    var memo: String
    var coach: AIRequestCoachContext?
    var locale: String

    enum CodingKeys: String, CodingKey {
        case items
        case mealType = "meal_type"
        case memo
        case coach
        case locale
    }
}

private struct BodyPhotoAnalysisRequest: Encodable {
    var imageBase64: String
    var angle: String
    var memo: String
    var responseLocale: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case angle
        case memo
        case responseLocale = "response_locale"
    }
}

private struct BodyPhotoSetAnalysisPhotoRequest: Encodable {
    var imageBase64: String
    var angle: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case angle
    }
}

private struct BodyPhotoSetAnalysisRequest: Encodable {
    var photos: [BodyPhotoSetAnalysisPhotoRequest]
    var comparisonPhotos: [BodyPhotoSetAnalysisPhotoRequest]
    var memo: String
    var context: BodyPhotoAnalysisContext?
    var responseLocale: String

    enum CodingKeys: String, CodingKey {
        case photos
        case comparisonPhotos = "comparison_photos"
        case memo
        case context
        case responseLocale = "response_locale"
    }
}

struct WeeklyReportRequest: Encodable {
    var profileGoal: String
    var coachID: String
    var coach: AIRequestCoachContext? = nil
    var experienceLevel: String
    var bodyLogs: [String]
    var meals: [String]
    var workouts: [String]
    var bodyPhotos: [String]
    var sensorMetrics: [String]
    var responseLocale: String = AppLanguagePreference.aiLocaleIdentifier

    enum CodingKeys: String, CodingKey {
        case profileGoal = "profile_goal"
        case coachID = "coach_id"
        case coach
        case experienceLevel = "experience_level"
        case bodyLogs = "body_logs"
        case meals
        case workouts
        case bodyPhotos = "body_photos"
        case sensorMetrics = "sensor_metrics"
        case responseLocale = "response_locale"
    }
}

struct WeeklyReportResponse: Codable, Hashable {
    var inputSummary: String
    var outputComment: String
    var actionSuggestion: String
    var goodPoints: [String]? = nil
    var challenges: [String]? = nil
    var rationales: [String]? = nil
    var nextActions: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case inputSummary = "input_summary"
        case outputComment = "output_comment"
        case actionSuggestion = "action_suggestion"
        case goodPoints = "good_points"
        case challenges
        case rationales
        case nextActions = "next_actions"
    }
}

private extension JSONEncoder {
    static var aiEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return encoder
    }
}

private extension JSONDecoder {
    static var aiDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}
