import Foundation

struct AIAPIClient {
    private static let inferenceTimeout: TimeInterval = 240

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

    func analyzeMealImage(
        imageData: Data,
        mealType: MealType,
        memo: String,
        coach: AIRequestCoachContext? = nil
    ) async throws -> MealAIDraft {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--stub-meal-ai") {
            return MealAIDraft(
                mealName: "鶏むね肉定食",
                calories: 483,
                protein: 34,
                fat: 14,
                carbs: 55,
                confidence: "medium",
                comment: "テスト用の推定値です。",
                items: []
            )
        }
        #endif

        let uploadData = try await prepareImageForUpload(imageData)
        let request = MealAnalysisRequest(
            imageBase64: uploadData.base64EncodedString(),
            mealType: mealType.rawValue,
            memo: memo,
            coach: coach
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
                mealName: "白ごはん・鶏むね肉・味噌汁",
                calories: 427,
                protein: 33.9,
                fat: 3.4,
                carbs: 56,
                confidence: "high",
                comment: "テスト用の推定値です。",
                items: [
                    MealAIDraftItem(
                        name: "白ごはん",
                        amount: "150g",
                        calories: 234,
                        protein: 3.9,
                        fat: 0.5,
                        carbs: 53
                    ),
                    MealAIDraftItem(
                        name: "鶏むね肉（皮なし）",
                        amount: "120g",
                        calories: 163,
                        protein: 28,
                        fat: 2.4,
                        carbs: 0
                    ),
                    MealAIDraftItem(
                        name: "味噌汁",
                        amount: "1杯",
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
        guard !normalizedItems.isEmpty else { throw AIClientError.emptyMealItems }

        let request = MealTextAnalysisRequest(
            items: Array(normalizedItems.prefix(20)),
            mealType: mealType.rawValue,
            memo: memo,
            coach: coach
        )
        let draft = try await post("/v1/meals/analyze-text", body: request, responseType: MealAIDraft.self, timeout: Self.inferenceTimeout)
        return draft.reconciledFromItems()
    }

    func analyzeBodyPhoto(imageData: Data, angle: BodyPhotoAngle, memo: String) async throws -> BodyPhotoAIComment {
        let uploadData = try await prepareImageForUpload(imageData)
        let request = BodyPhotoAnalysisRequest(
            imageBase64: uploadData.base64EncodedString(),
            angle: angle.rawValue,
            memo: memo
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
                summary: "複数方向の写真をまとめて確認しました。撮影条件を揃えて継続すると比較しやすくなります。",
                abdomen: "正面と横から腹部の状態を確認しました。",
                waist: "正面と背面を合わせてウエストまわりを確認しました。",
                posture: "方向による姿勢の違いを確認しました。",
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
            memo: memo,
            context: context
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
                inputSummary: "直近30日の身体、食事、トレーニング記録を確認しました。",
                outputComment: "継続できたトレーニングを軸に、回復とのバランスを確認できました。",
                actionSuggestion: "1. 週3回を維持\n2. たんぱく質目標を記録\n3. 月末に体型写真を比較"
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
                    let title = remainder.split(separator: ",", maxSplits: 1).first.map(String.init) ?? "今日の行動"
                    return "{\"id\":\"\(id)\",\"category\":\"\(category)\",\"title\":\"\(title)\",\"target\":0,\"rationale\":\"記録と目標を確認しました\"}"
                }
                return CoachChatResponse(
                    reply: "{\"keep_existing\":true,\"readiness_level\":\"normal\",\"summary\":\"今日の提案をこのまま進めましょう。\",\"change_reason\":\"\",\"actions\":[\(actions.joined(separator: ","))]}"
                )
            }
            if payload.message.contains("[BODYMODE_PLAN_JSON]") {
                return CoachChatResponse(
                    reply: """
                    {
                      "name": "AI 全身バランス",
                      "summary": "目標と利用できる器具に合わせた確認用プランです。",
                      "exercises": [
                        {"exercise_name":"チェストプレス","sets":3,"reps":10,"weight":30,"rest_seconds":90},
                        {"exercise_name":"ラットプルダウン","sets":3,"reps":10,"weight":30,"rest_seconds":90},
                        {"exercise_name":"レッグプレス","sets":3,"reps":12,"weight":50,"rest_seconds":120}
                      ]
                    }
                    """
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
                        content: "重量は小刻みに上げたい",
                        reason: "今後の重量提案に役立つため"
                    )
                ]
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
        compacted: Bool
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
        do {
            return try await send(request, responseType: responseType)
        } catch AIClientError.httpStatus(401) where settings.usesSessionTokens {
            AIAuthenticationStore.shared.reset()
            try await applyHeaders(to: &request)
            return try await send(request, responseType: responseType)
        }
    }

    private func applyHeaders(to request: inout URLRequest) async throws {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(try await authorizationCredential())", forHTTPHeaderField: "Authorization")
    }

    private func authorizationCredential() async throws -> String {
        guard settings.usesSessionTokens else { return settings.apiKey }
        let normalizedBaseURL = settings.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = AIAuthenticationStore.shared.usableToken(for: normalizedBaseURL) {
            return cached.value
        }

        var request = URLRequest(url: try makeURL("/v1/auth/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
        AIAuthenticationStore.shared.save(cached)
        return cached.value
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
            let error = AIClientError.httpStatus(httpResponse.statusCode)
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
        metadata["host"] = request.url?.host ?? "unknown"
        metadata["path"] = request.url?.path ?? "unknown"
        metadata["method"] = request.httpMethod ?? "unknown"
        metadata["timeout_seconds"] = String(Int(request.timeoutInterval))
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
    case requestFailed(URLError)
    case transport(String)
    case decodingFailed(String)
    case secureStorageFailed

    var errorDescription: String? {
        switch self {
        case .disabled:
            "AI利用設定がオフです。"
        case .missingAPIKey:
            "APIキーが設定されていません。"
        case .invalidBaseURL:
            "AIサーバーURLが不正です。"
        case .insecureRemoteHTTPHost:
            "外部サーバーへのHTTP接続は許可されていません。"
        case .invalidImage:
            "選択した画像を解析用に変換できませんでした。"
        case .emptyMealItems:
            "食べたものを1件以上入力してください。"
        case .invalidResponse:
            "AIサーバーの応答を読めませんでした。"
        case .httpStatus(let statusCode):
            httpStatusMessage(statusCode)
        case .requestFailed(let error):
            requestFailureMessage(error)
        case .transport:
            "AIサーバーに接続できません。時間をおいて再試行してください。"
        case .decodingFailed:
            "AIサーバーのJSON形式がアプリの想定と違います。"
        case .secureStorageFailed:
            "AI接続情報を安全に保存できませんでした。"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .disabled:
            "設定で「AI機能を使う」をオンにしてください。手動記録はこのまま保存できます。"
        case .missingAPIKey:
            "設定画面でAIサーバーのAPIキーを入力してください。"
        case .invalidBaseURL:
            "URLはhttps://から始めてください。ローカル開発ではlocalhost、LAN IP、Tailscale名のHTTPも利用できます。"
        case .insecureRemoteHTTPHost:
            "HTTPはlocalhost、LAN、Tailscale内だけ利用できます。外部サーバーにはHTTPSを使用してください。"
        case .invalidImage:
            "JPEGまたはPNG画像を選び直してください。"
        case .emptyMealItems:
            "食品名と、分かれば量も入力してください。"
        case .invalidResponse:
            "設定したサーバーURLが正しいか確認してください。"
        case .httpStatus(let statusCode):
            httpStatusRecovery(statusCode)
        case .requestFailed(let error):
            requestFailureRecovery(error)
        case .transport:
            "ネットワーク状態とサーバーURLを確認してから再試行してください。"
        case .decodingFailed(let message):
            "APIサーバーのバージョンを確認してください。詳細: \(message)"
        case .secureStorageFailed:
            "端末を再起動してから再試行してください。"
        }
    }

    static func presentation(for error: Error) -> AIErrorPresentation {
        let localizedError = error as? LocalizedError
        return AIErrorPresentation(
            message: localizedError?.errorDescription ?? error.localizedDescription,
            recovery: localizedError?.recoverySuggestion
        )
    }

    private func httpStatusMessage(_ statusCode: Int) -> String {
        switch statusCode {
        case 401:
            "AIの認証情報が不正か、期限切れです。"
        case 429:
            "AIの利用が一時的に集中しています。"
        case 404:
            "AIサーバーに必要なAPIが見つかりません。"
        case 503:
            "AIモデルが利用できないか、画像解析に失敗しました。"
        case 500..<600:
            "AIサーバー側でエラーが発生しました: \(statusCode)"
        default:
            "AIサーバーがエラーを返しました: \(statusCode)"
        }
    }

    private func httpStatusRecovery(_ statusCode: Int) -> String {
        switch statusCode {
        case 401:
            "設定画面の接続情報を確認して再試行してください。短期認証は自動更新されます。"
        case 429:
            "1分ほど待ってから再試行してください。"
        case 404:
            "Base URLとAPIサーバーのバージョンを確認してください。"
        case 503:
            "時間をおいて再試行してください。続く場合はAIサーバーのモデル状態を確認してください。"
        case 500..<600:
            "時間をおいて再試行してください。続く場合はAIサーバーのログを確認してください。"
        default:
            "サーバーURL、APIキー、APIサーバーの稼働状態を確認してください。"
        }
    }

    private func requestFailureMessage(_ error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .networkConnectionLost, .notConnectedToInternet, .timedOut:
            "AIサーバーに接続できません。時間をおいて再試行してください。"
        case .unsupportedURL, .badURL:
            "AIサーバーURLが不正です。"
        default:
            "AIサーバーに接続できません。時間をおいて再試行してください。"
        }
    }

    private func requestFailureRecovery(_ error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .networkConnectionLost, .notConnectedToInternet, .timedOut:
            "ネットワークとAIサーバーの稼働状態を確認してください。AI処理は最大240秒かかる場合があります。"
        case .unsupportedURL, .badURL:
            "URLはhttps://から始めてください。ローカル開発時のみhttp://も利用できます。"
        default:
            "ネットワーク状態とサーバーURLを確認してください。"
        }
    }
}

private extension String {
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

private struct MealAnalysisRequest: Encodable {
    var imageBase64: String
    var mealType: String
    var memo: String
    var coach: AIRequestCoachContext?

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mealType = "meal_type"
        case memo
        case coach
    }
}

private struct MealTextAnalysisRequest: Encodable {
    var items: [String]
    var mealType: String
    var memo: String
    var coach: AIRequestCoachContext?

    enum CodingKeys: String, CodingKey {
        case items
        case mealType = "meal_type"
        case memo
        case coach
    }
}

private struct BodyPhotoAnalysisRequest: Encodable {
    var imageBase64: String
    var angle: String
    var memo: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case angle
        case memo
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

    enum CodingKeys: String, CodingKey {
        case photos
        case comparisonPhotos = "comparison_photos"
        case memo
        case context
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
