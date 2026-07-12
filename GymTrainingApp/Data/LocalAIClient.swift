import Foundation

struct LocalAIClient {
    let settings: AISettings

    private var baseURL: URL? {
        URL(string: settings.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func health() async throws -> AIHealthResponse {
        try await get("/v1/health", responseType: AIHealthResponse.self)
    }

    func analyzeMealImage(imageData: Data, mealType: MealType, memo: String) async throws -> MealAIDraft {
        let request = MealAnalysisRequest(
            imageBase64: imageData.base64EncodedString(),
            mealType: mealType.rawValue,
            memo: memo
        )
        return try await post("/v1/meals/analyze-image", body: request, responseType: MealAIDraft.self)
    }

    func analyzeBodyPhoto(imageData: Data, angle: BodyPhotoAngle, memo: String) async throws -> BodyPhotoAIComment {
        let request = BodyPhotoAnalysisRequest(
            imageBase64: imageData.base64EncodedString(),
            angle: angle.rawValue,
            memo: memo
        )
        return try await post("/v1/body-photos/analyze", body: request, responseType: BodyPhotoAIComment.self)
    }

    func generateWeeklyReport(payload: WeeklyReportRequest) async throws -> WeeklyReportResponse {
        try await post("/v1/reports/weekly", body: payload, responseType: WeeklyReportResponse.self)
    }

    private func get<Response: Decodable>(_ path: String, responseType: Response.Type) async throws -> Response {
        guard settings.isEnabled else {
            throw AIClientError.disabled
        }
        guard let url = makeURL(path) else {
            throw AIClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return try await send(request, responseType: responseType)
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, responseType: Response.Type) async throws -> Response {
        guard settings.isEnabled else {
            throw AIClientError.disabled
        }
        guard let url = makeURL(path) else {
            throw AIClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw AIClientError.httpStatus(httpResponse.statusCode)
        }
        return try JSONDecoder.aiDecoder.decode(Response.self, from: data)
    }
}

enum AIClientError: LocalizedError {
    case disabled
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .disabled:
            "AI利用設定がオフです。"
        case .invalidBaseURL:
            "ローカルLLMサーバーURLが不正です。"
        case .invalidResponse:
            "ローカルLLMサーバーの応答を読めませんでした。"
        case .httpStatus(let statusCode):
            "ローカルLLMサーバーがエラーを返しました: \(statusCode)"
        }
    }
}

struct AIHealthResponse: Codable, Hashable {
    var status: String
    var model: String
    var ollamaReachable: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case model
        case ollamaReachable = "ollama_reachable"
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

    enum CodingKeys: String, CodingKey {
        case profileGoal = "profile_goal"
        case bodyLogs = "body_logs"
        case meals
        case workouts
        case bodyPhotos = "body_photos"
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
