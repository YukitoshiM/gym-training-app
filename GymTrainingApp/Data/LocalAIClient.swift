import Foundation

struct LocalAIClient {
    let settings: AISettings

    private var baseURL: URL? {
        URL(string: settings.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func health() async throws -> AIHealthResponse {
        try await get("/v1/health", responseType: AIHealthResponse.self, timeout: 6)
    }

    @discardableResult
    func ensureReady() async throws -> AIHealthResponse {
        let health = try await health()
        guard health.ollamaReachable else {
            throw AIClientError.ollamaUnavailable(model: health.model)
        }

        if health.modelAvailable == false {
            throw AIClientError.ollamaModelUnavailable(model: health.model)
        }

        return health
    }

    func analyzeMealImage(imageData: Data, mealType: MealType, memo: String) async throws -> MealAIDraft {
        try await ensureReady()
        let request = MealAnalysisRequest(
            imageBase64: imageData.base64EncodedString(),
            mealType: mealType.rawValue,
            memo: memo
        )
        return try await post("/v1/meals/analyze-image", body: request, responseType: MealAIDraft.self, timeout: 120)
    }

    func analyzeBodyPhoto(imageData: Data, angle: BodyPhotoAngle, memo: String) async throws -> BodyPhotoAIComment {
        try await ensureReady()
        let request = BodyPhotoAnalysisRequest(
            imageBase64: imageData.base64EncodedString(),
            angle: angle.rawValue,
            memo: memo
        )
        return try await post("/v1/body-photos/analyze", body: request, responseType: BodyPhotoAIComment.self, timeout: 120)
    }

    func generateWeeklyReport(payload: WeeklyReportRequest) async throws -> WeeklyReportResponse {
        try await ensureReady()
        return try await post("/v1/reports/weekly", body: payload, responseType: WeeklyReportResponse.self, timeout: 120)
    }

    private func get<Response: Decodable>(_ path: String, responseType: Response.Type, timeout: TimeInterval) async throws -> Response {
        guard settings.isEnabled else {
            throw AIClientError.disabled
        }
        guard let url = makeURL(path) else {
            throw AIClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        applyHeaders(to: &request)
        return try await send(request, responseType: responseType)
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, responseType: Response.Type, timeout: TimeInterval) async throws -> Response {
        guard settings.isEnabled else {
            throw AIClientError.disabled
        }
        guard let url = makeURL(path) else {
            throw AIClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder.aiEncoder.encode(body)
        applyHeaders(to: &request)
        return try await send(request, responseType: responseType)
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private func makeURL(_ path: String) -> URL? {
        guard let baseURL else {
            return nil
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let requestPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = "/" + [basePath, requestPath].filter { !$0.isEmpty }.joined(separator: "/")
        return components?.url
    }

    private func send<Response: Decodable>(_ request: URLRequest, responseType: Response.Type) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw AIClientError.requestFailed(error)
        } catch {
            throw AIClientError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw AIClientError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder.aiDecoder.decode(Response.self, from: data)
        } catch {
            throw AIClientError.decodingFailed(error.localizedDescription)
        }
    }
}

enum AIClientError: LocalizedError {
    case disabled
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)
    case requestFailed(URLError)
    case transport(String)
    case decodingFailed(String)
    case ollamaUnavailable(model: String)
    case ollamaModelUnavailable(model: String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            "AI利用設定がオフです。"
        case .invalidBaseURL:
            "ローカルLLMサーバーURLが不正です。"
        case .invalidResponse:
            "ローカルLLMサーバーの応答を読めませんでした。"
        case .httpStatus(let statusCode):
            httpStatusMessage(statusCode)
        case .requestFailed(let error):
            requestFailureMessage(error)
        case .transport(let message):
            "ローカルLLMとの通信に失敗しました: \(message)"
        case .decodingFailed:
            "ローカルLLMサーバーのJSON形式がアプリの想定と違います。"
        case .ollamaUnavailable:
            "ローカルLLM APIは起動していますが、Ollamaに接続できません。"
        case .ollamaModelUnavailable(let model):
            "Ollamaにモデル \(model) が見つかりません。"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .disabled:
            "設定で「AI機能を使う」をオンにしてください。手動記録はこのまま保存できます。"
        case .invalidBaseURL:
            "Simulatorでは http://127.0.0.1:8765、実機ではMacのLAN IPまたはTailscale名を入力してください。"
        case .invalidResponse:
            "local_llm_server が起動中か、アプリのサーバーURLが正しいか確認してください。"
        case .httpStatus(let statusCode):
            httpStatusRecovery(statusCode)
        case .requestFailed(let error):
            requestFailureRecovery(error)
        case .transport:
            "ネットワーク状態、サーバーURL、local_llm_server の起動状態を確認してください。"
        case .decodingFailed(let message):
            "local_llm_server を最新のコードで再起動してください。詳細: \(message)"
        case .ollamaUnavailable:
            "Mac miniで `ollama serve` を起動し、設定画面の接続確認をもう一度実行してください。"
        case .ollamaModelUnavailable(let model):
            "Mac miniで `ollama pull \(model)` を実行するか、local_llm_server の OLLAMA_MODEL を利用中のモデル名に変更してください。"
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
            "APIキーが一致していません。"
        case 404:
            "ローカルLLMサーバーに必要なAPIが見つかりません。"
        case 500..<600:
            "ローカルLLMサーバー側でエラーが発生しました: \(statusCode)"
        default:
            "ローカルLLMサーバーがエラーを返しました: \(statusCode)"
        }
    }

    private func httpStatusRecovery(_ statusCode: Int) -> String {
        switch statusCode {
        case 401:
            "アプリ設定のAPIキーと local_llm_server の LOCAL_AI_API_KEY を同じ値にしてください。"
        case 404:
            "アプリと local_llm_server のコードが同じリポジトリ最新版か確認し、サーバーを再起動してください。"
        case 500..<600:
            "local_llm_server のターミナルログを確認してください。Ollamaモデル名や画像対応モデルの有無が原因になりやすいです。"
        default:
            "サーバーURL、APIキー、local_llm_server の起動状態を確認してください。"
        }
    }

    private func requestFailureMessage(_ error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            "ローカルLLMサーバーに接続できません。"
        case .timedOut:
            "ローカルLLMサーバーの応答がタイムアウトしました。"
        case .unsupportedURL, .badURL:
            "ローカルLLMサーバーURLが不正です。"
        default:
            "ローカルLLMとの通信に失敗しました: \(error.localizedDescription)"
        }
    }

    private func requestFailureRecovery(_ error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            "local_llm_server を起動してください。Simulatorなら http://127.0.0.1:8765、実機ならMacのLAN IPまたはTailscale名を使います。"
        case .timedOut:
            "初回生成でモデル読み込み中の可能性があります。Ollamaのターミナルログを確認してから再試行してください。"
        case .unsupportedURL, .badURL:
            "URLは http:// または https:// から始めてください。例: http://127.0.0.1:8765"
        default:
            "ネットワーク状態、サーバーURL、local_llm_server の起動状態を確認してください。"
        }
    }
}

struct AIErrorPresentation: Hashable {
    var message: String
    var recovery: String?
}

struct AIHealthResponse: Codable, Hashable {
    var status: String
    var model: String
    var ollamaReachable: Bool
    var modelAvailable: Bool?
    var message: String?

    var isReady: Bool {
        ollamaReachable && (modelAvailable ?? true)
    }

    enum CodingKeys: String, CodingKey {
        case status
        case model
        case ollamaReachable = "ollama_reachable"
        case modelAvailable = "model_available"
        case message
    }
}

private struct MealAnalysisRequest: Encodable {
    var imageBase64: String
    var mealType: String
    var memo: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mealType = "meal_type"
        case memo
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

struct WeeklyReportRequest: Encodable {
    var profileGoal: String
    var bodyLogs: [String]
    var meals: [String]
    var workouts: [String]
    var bodyPhotos: [String]
    var sensorMetrics: [String]

    enum CodingKeys: String, CodingKey {
        case profileGoal = "profile_goal"
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

    enum CodingKeys: String, CodingKey {
        case inputSummary = "input_summary"
        case outputComment = "output_comment"
        case actionSuggestion = "action_suggestion"
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
