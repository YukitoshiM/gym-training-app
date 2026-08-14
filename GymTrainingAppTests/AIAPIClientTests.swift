import UIKit
import XCTest
@testable import GymTrainingApp

final class AIAPIClientTests: XCTestCase {
    override func tearDown() {
        MockAIURLProtocol.requestHandler = nil
        MockAIURLProtocol.lastRequest = nil
        MockAIURLProtocol.lastRequestBody = nil
        MockAIURLProtocol.requests = []
        MockAIURLProtocol.requestBodies = []
        AIAuthenticationStore.shared.reset()
        super.tearDown()
    }

    func testHealthAddsBearerAuthenticationAndDecodesResponse() async throws {
        MockAIURLProtocol.requestHandler = { request in
            let data = Data(#"""
            {
                "status":"ok",
                "model":"CalorieCLIP",
                "calorie_model_available":true,
                "ollama_reachable":true,
                "model_available":true,
                "message":"ready"
            }
            """#.utf8)
            return (Self.response(for: request, statusCode: 200), data)
        }

        let health = try await makeClient().health()

        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(health.model, "CalorieCLIP")
        XCTAssertTrue(health.isReady)
        XCTAssertEqual(MockAIURLProtocol.lastRequest?.url?.path, "/v1/health")
        XCTAssertEqual(MockAIURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(MockAIURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testSessionAuthenticationExchangesEnrollmentKeyAndReusesAccessToken() async throws {
        MockAIURLProtocol.requestHandler = { request in
            if request.url?.path == "/v1/auth/token" {
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Authorization"),
                    "Bearer enrollment-key"
                )
                return (
                    Self.response(for: request, statusCode: 200),
                    Data(#"{"access_token":"short-lived-token","token_type":"Bearer","expires_in":3600}"#.utf8)
                )
            }
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer short-lived-token"
            )
            return (
                Self.response(for: request, statusCode: 200),
                Data(#"{"status":"ok","model":"CalorieCLIP","calorie_model_available":true,"ollama_reachable":true,"model_available":true,"message":"ready"}"#.utf8)
            )
        }

        let client = makeClient(apiKey: "enrollment-key", usesSessionTokens: true)
        _ = try await client.health()
        _ = try await client.health()

        XCTAssertEqual(MockAIURLProtocol.requests.map(\.url?.path), ["/v1/auth/token", "/v1/health", "/v1/health"])
    }

    func testTransportDiagnosticsIncludeRequestContextWithoutSecrets() async throws {
        AppDiagnostics.shared.deleteData()
        MockAIURLProtocol.requestHandler = { _ in
            throw URLError(.cannotFindHost)
        }

        do {
            _ = try await makeClient().health()
            XCTFail("Expected transport failure")
        } catch {
            XCTAssertEqual(
                AIClientError.presentation(for: error).message,
                "AIサーバーに接続できません。時間をおいて再試行してください。"
            )
        }

        let exportedData = AppDiagnostics.shared.exportData()
        let events = exportedData.split(separator: 0x0A).compactMap {
            try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
        }
        let transportEvent = try XCTUnwrap(events.first { $0["category"] as? String == "ai.transport" })
        let metadata = try XCTUnwrap(transportEvent["metadata"] as? [String: String])
        XCTAssertEqual(metadata["host"], "example.com")
        XCTAssertEqual(metadata["path"], "/v1/health")
        XCTAssertEqual(metadata["url_error_code"], "-1003")
        XCTAssertEqual(metadata["url_error_name"], "cannotFindHost")
        XCTAssertFalse(String(decoding: exportedData, as: UTF8.self).contains("test-api-key"))
    }

    func testCoachesDecodesAllServerFields() async throws {
        MockAIURLProtocol.requestHandler = { request in
            let data = Data(#"""
            [{
                "id":"body_recomposition",
                "name":"ボディメイクコーチ",
                "identity":"バランス型コーチ",
                "priorities":["腹囲","筋力"]
            }]
            """#.utf8)
            return (Self.response(for: request, statusCode: 200), data)
        }

        let coaches = try await makeClient().coaches()

        XCTAssertEqual(coaches.first?.id, "body_recomposition")
        XCTAssertEqual(coaches.first?.priorities, ["腹囲", "筋力"])
        XCTAssertEqual(MockAIURLProtocol.lastRequest?.url?.path, "/v1/coaches")
    }

    func testMealAnalysisDownsamplesImageAndUses240SecondTimeout() async throws {
        MockAIURLProtocol.requestHandler = { request in
            let data = Data(#"""
            {
                "meal_name":"鶏むね肉定食",
                "calories":650,
                "protein":30,
                "fat":20,
                "carbs":75,
                "confidence":"medium",
                "comment":"確認してください",
                "items":[]
            }
            """#.utf8)
            return (Self.response(for: request, statusCode: 200), data)
        }
        let sourceData = makeImageData(size: CGSize(width: 3_200, height: 1_200))

        let draft = try await makeClient().analyzeMealImage(
            imageData: sourceData,
            mealType: .lunch,
            memo: "テスト",
            coach: AIRequestCoachContext(profile: coachTestProfile)
        )

        XCTAssertEqual(draft.calories, 650)
        let request = try XCTUnwrap(MockAIURLProtocol.lastRequest)
        XCTAssertEqual(request.timeoutInterval, 240, accuracy: 0.1)
        let body = try XCTUnwrap(MockAIURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let encodedImage = try XCTUnwrap(json["image_base64"] as? String)
        XCTAssertFalse(encodedImage.hasPrefix("data:image"))
        let uploadedData = try XCTUnwrap(Data(base64Encoded: encodedImage))
        XCTAssertLessThanOrEqual(uploadedData.count, AIImageUploadProcessor.maximumUploadBytes)
        let uploadedImage = try XCTUnwrap(UIImage(data: uploadedData))
        XCTAssertEqual(uploadedImage.size.width, 1_600, accuracy: 1)
        XCTAssertEqual(uploadedImage.size.height, 600, accuracy: 1)
        XCTAssertEqual(json["meal_type"] as? String, "lunch")
        let coach = try XCTUnwrap(json["coach"] as? [String: Any])
        XCTAssertEqual(coach["coach_name"] as? String, "Maya")
        XCTAssertEqual(coach["coach_id"] as? String, "hypertrophy")
        XCTAssertEqual(coach["coaching_style"] as? String, CoachingStyle.encouraging.promptDescription)
        XCTAssertEqual(coach["focus_areas"] as? [String], ["筋肥大", "回復", "食事・栄養"])
    }

    func testMealTextAnalysisSendsFoodListAndUses240SecondTimeout() async throws {
        MockAIURLProtocol.requestHandler = { request in
            let data = Data(#"""
            {
                "meal_name":"白ごはん・鶏むね肉・味噌汁",
                "calories":427,
                "protein":33.9,
                "fat":3.4,
                "carbs":56,
                "confidence":"medium",
                "comment":"量を確認してください",
                "items":[
                    {"name":"白ごはん","amount":"150g","calories":234,"protein":3.9,"fat":0.5,"carbs":53},
                    {"name":"鶏むね肉（皮なし）","amount":"120g","calories":163,"protein":28,"fat":2.4,"carbs":0},
                    {"name":"味噌汁","amount":"1杯","calories":30,"protein":2,"fat":0.5,"carbs":3}
                ]
            }
            """#.utf8)
            return (Self.response(for: request, statusCode: 200), data)
        }

        let draft = try await makeClient().analyzeMealText(
            items: [" 白ごはん 150g ", "", "鶏むね肉 皮なし 120g", "味噌汁 1杯"],
            mealType: .dinner,
            memo: "夕食",
            coach: AIRequestCoachContext(profile: coachTestProfile)
        )

        XCTAssertEqual(draft.calories, 427)
        let request = try XCTUnwrap(MockAIURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/v1/meals/analyze-text")
        XCTAssertEqual(request.timeoutInterval, 240, accuracy: 0.1)
        let body = try XCTUnwrap(MockAIURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(
            json["items"] as? [String],
            ["白ごはん 150g", "鶏むね肉 皮なし 120g", "味噌汁 1杯"]
        )
        XCTAssertEqual(json["meal_type"] as? String, "dinner")
        XCTAssertEqual(json["memo"] as? String, "夕食")
        XCTAssertEqual((json["coach"] as? [String: Any])?["coach_name"] as? String, "Maya")
    }

    func testMealItemTotalsReplaceMateriallyInconsistentServerTotals() async throws {
        MockAIURLProtocol.requestHandler = { request in
            let data = Data(#"""
            {
                "meal_name":"定食",
                "calories":900,
                "protein":10,
                "fat":40,
                "carbs":100,
                "confidence":"medium",
                "comment":"確認してください",
                "items":[
                    {"name":"ごはん","amount":"150g","calories":234,"protein":3.9,"fat":0.5,"carbs":53},
                    {"name":"鶏むね肉","amount":"120g","calories":163,"protein":28,"fat":2.4,"carbs":0}
                ]
            }
            """#.utf8)
            return (Self.response(for: request, statusCode: 200), data)
        }

        let draft = try await makeClient().analyzeMealText(
            items: ["ごはん 150g", "鶏むね肉 120g"],
            mealType: .lunch,
            memo: ""
        )

        XCTAssertEqual(draft.calories, 397, accuracy: 0.001)
        XCTAssertEqual(draft.protein, 31.9, accuracy: 0.001)
        XCTAssertEqual(draft.fat, 2.9, accuracy: 0.001)
        XCTAssertEqual(draft.carbs, 53, accuracy: 0.001)
        XCTAssertTrue(draft.comment.contains("内訳を合計"))
    }

    func testWeeklyReportDecodesStructuredSectionsAndKeepsLegacyCompatibility() throws {
        let structured = try JSONDecoder().decode(
            WeeklyReportResponse.self,
            from: Data(#"""
            {
                "input_summary":"7日分の記録",
                "output_comment":"継続できています。",
                "action_suggestion":"次週も続けましょう。",
                "good_points":["週3回運動できた"],
                "challenges":["睡眠記録が少ない"],
                "rationales":["運動履歴3件を確認"],
                "next_actions":["睡眠を3日記録する"]
            }
            """#.utf8)
        )
        XCTAssertEqual(structured.goodPoints, ["週3回運動できた"])
        XCTAssertEqual(structured.challenges, ["睡眠記録が少ない"])
        XCTAssertEqual(structured.rationales, ["運動履歴3件を確認"])
        XCTAssertEqual(structured.nextActions, ["睡眠を3日記録する"])

        let legacy = try JSONDecoder().decode(
            WeeklyReportResponse.self,
            from: Data(#"{"input_summary":"要約","output_comment":"評価","action_suggestion":"提案"}"#.utf8)
        )
        XCTAssertNil(legacy.goodPoints)
        XCTAssertNil(legacy.nextActions)
    }

    func testServerErrorsUseUserFacingMessages() async {
        MockAIURLProtocol.requestHandler = { request in
            (Self.response(for: request, statusCode: 503), Data())
        }

        do {
            _ = try await makeClient().health()
            XCTFail("Expected a server error")
        } catch {
            XCTAssertEqual(
                AIClientError.presentation(for: error).message,
                "AIモデルが利用できないか、画像解析に失敗しました。"
            )
        }
    }

    func testInvalidImageIsRejectedBeforeUpload() async {
        do {
            _ = try await makeClient().analyzeBodyPhoto(
                imageData: Data("not-an-image".utf8),
                angle: .front,
                memo: ""
            )
            XCTFail("Expected invalid image error")
        } catch {
            XCTAssertEqual(
                AIClientError.presentation(for: error).message,
                "選択した画像を解析用に変換できませんでした。"
            )
        }
    }

    func testBodyPhotoSetAnalysisUploadsContactSheetsWith240SecondTimeout() async throws {
        MockAIURLProtocol.requestHandler = { request in
            let data = Data(#"""
            {
                "summary":"2方向を確認しました",
                "abdomen":"腹部",
                "waist":"ウエスト",
                "posture":"姿勢",
                "score":null,
                "confidence":"medium"
            }
            """#.utf8)
            return (Self.response(for: request, statusCode: 200), data)
        }

        let comment = try await makeClient().analyzeBodyPhotos(
            [
                BodyPhotoAnalysisInput(angle: .front, imageData: makeImageData(size: CGSize(width: 2_000, height: 1_000))),
                BodyPhotoAnalysisInput(angle: .side, imageData: makeImageData(size: CGSize(width: 1_000, height: 2_000)))
            ],
            memo: "自然光",
            context: BodyPhotoAnalysisContext(
                profileGoal: "体型改善",
                outcomeStyle: "Vシェイプ",
                focusAreas: ["肩", "背中"],
                experienceLevel: "中級者",
                currentMetrics: ["体重: 70 kg"],
                previousCaptureDate: "2026-08-01",
                previousSummary: "前回要約",
                previousMetrics: BodyPhotoAnalysisMetrics(
                    weightKG: 70.4,
                    waistCM: 82.1,
                    bodyFatPercentage: 16.0
                ),
                metricDeltas: BodyPhotoAnalysisMetrics(
                    weightKG: -0.4,
                    waistCM: -1.1,
                    bodyFatPercentage: -0.8
                ),
                coach: AIRequestCoachContext(profile: coachTestProfile)
            ),
            previousPhotos: [
                BodyPhotoAnalysisInput(angle: .front, imageData: makeImageData(size: CGSize(width: 800, height: 1_200)))
            ]
        )

        XCTAssertEqual(comment.summary, "2方向を確認しました")
        let request = try XCTUnwrap(MockAIURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/v1/body-photos/analyze-set")
        XCTAssertEqual(request.timeoutInterval, 240, accuracy: 0.1)
        let body = try XCTUnwrap(MockAIURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let photos = try XCTUnwrap(json["photos"] as? [[String: Any]])
        XCTAssertEqual(photos.compactMap { $0["angle"] as? String }, ["capture_set_2"])
        XCTAssertEqual(json["memo"] as? String, "自然光")
        let context = try XCTUnwrap(json["context"] as? [String: Any])
        XCTAssertEqual(context["profile_goal"] as? String, "体型改善")
        XCTAssertEqual(context["outcome_style"] as? String, "Vシェイプ")
        XCTAssertEqual(context["focus_areas"] as? [String], ["肩", "背中"])
        let previousMetrics = try XCTUnwrap(context["previous_metrics"] as? [String: Any])
        XCTAssertEqual(previousMetrics["weight_kg"] as? Double, 70.4)
        XCTAssertEqual(previousMetrics["waist_cm"] as? Double, 82.1)
        XCTAssertEqual(previousMetrics["body_fat_percent"] as? Double, 16.0)
        let metricDeltas = try XCTUnwrap(context["metric_deltas"] as? [String: Any])
        XCTAssertEqual(metricDeltas["weight_kg"] as? Double, -0.4)
        XCTAssertEqual(metricDeltas["waist_cm"] as? Double, -1.1)
        XCTAssertEqual(metricDeltas["body_fat_percent"] as? Double, -0.8)
        XCTAssertEqual((context["coach"] as? [String: Any])?["coach_name"] as? String, "Maya")
        let comparisonPhotos = try XCTUnwrap(json["comparison_photos"] as? [[String: Any]])
        XCTAssertEqual(comparisonPhotos.compactMap { $0["angle"] as? String }, ["capture_set_1"])
        XCTAssertTrue(photos.allSatisfy { photo in
            guard let encoded = photo["image_base64"] as? String else { return false }
            return !encoded.hasPrefix("data:image") && Data(base64Encoded: encoded) != nil
        })
    }

    func testBodyPhotoAnalysisContextKeepsLegacyPayloadWhenComparisonMetricsAreMissing() throws {
        let context = BodyPhotoAnalysisContext(
            profileGoal: "健康維持",
            outcomeStyle: "",
            focusAreas: [],
            experienceLevel: "初心者",
            currentMetrics: [],
            previousCaptureDate: nil,
            previousSummary: nil
        )

        let data = try JSONEncoder().encode(context)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["previous_metrics"])
        XCTAssertNil(json["metric_deltas"])
        XCTAssertEqual(json["profile_goal"] as? String, "健康維持")
    }

    func testWeeklyReportCarriesTheSameCoachIdentityStyleAndBoundaries() throws {
        let request = WeeklyReportRequest(
            profileGoal: "筋肥大",
            coachID: CoachType.hypertrophy.rawValue,
            coach: AIRequestCoachContext(profile: coachTestProfile),
            experienceLevel: ExperienceLevel.intermediate.rawValue,
            bodyLogs: [],
            meals: [],
            workouts: [],
            bodyPhotos: [],
            sensorMetrics: []
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let coach = try XCTUnwrap(json["coach"] as? [String: Any])

        XCTAssertEqual(json["coach_id"] as? String, "hypertrophy")
        XCTAssertEqual(coach["coach_name"] as? String, "Maya")
        XCTAssertTrue((coach["boundaries"] as? [String])?.contains("見た目だけで体脂肪率を断定しない") == true)
    }

    func testMonthlyReportUsesDedicatedEndpointAnd240SecondTimeout() async throws {
        MockAIURLProtocol.requestHandler = { request in
            let data = Data(#"{"input_summary":"30日分","output_comment":"月次差分","action_suggestion":"翌月目標案"}"#.utf8)
            return (Self.response(for: request, statusCode: 200), data)
        }
        let payload = WeeklyReportRequest(
            profileGoal: "筋肥大",
            coachID: CoachType.hypertrophy.rawValue,
            coach: AIRequestCoachContext(profile: coachTestProfile),
            experienceLevel: ExperienceLevel.intermediate.rawValue,
            bodyLogs: [],
            meals: [],
            workouts: [],
            bodyPhotos: [],
            sensorMetrics: []
        )

        let response = try await makeClient().generateMonthlyReport(payload: payload)

        XCTAssertEqual(response.actionSuggestion, "翌月目標案")
        XCTAssertEqual(MockAIURLProtocol.lastRequest?.url?.path, "/v1/reports/monthly")
        XCTAssertEqual(MockAIURLProtocol.lastRequest?.timeoutInterval ?? 0, 240, accuracy: 0.1)
    }

    func testBodyPhotoLegacyResponseDecodesWithoutStructuredAdvice() throws {
        let data = Data(#"""
        {
            "summary":"旧形式",
            "abdomen":"腹部",
            "waist":"ウエスト",
            "posture":"姿勢",
            "score":null,
            "confidence":"low"
        }
        """#.utf8)

        let comment = try JSONDecoder().decode(BodyPhotoAIComment.self, from: data)

        XCTAssertEqual(comment.summary, "旧形式")
        XCTAssertNil(comment.goalRelevance)
        XCTAssertNil(comment.nextActions)
    }

    func testTrainerChatLimitsHistoryAndDecodesMemoryCandidates() async throws {
        MockAIURLProtocol.requestHandler = { request in
            let data = Data(#"""
            {
                "reply":"次回は1kgだけ上げてみましょう。",
                "memory_candidates":[{
                    "content":"重量は小刻みに上げたい",
                    "reason":"今後の提案に役立つため"
                }],
                "evidence":[{
                    "id":"PMID:12345678",
                    "title":"Resistance training volume and muscle hypertrophy",
                    "year":2025,
                    "study_type":"systematic_review",
                    "confidence":"high",
                    "url":"https://pubmed.ncbi.nlm.nih.gov/12345678/",
                    "doi":"10.1000/bodymode-test",
                    "relevance":0.91
                }],
                "evidence_status":{
                    "state":"ready",
                    "confidence":"high",
                    "last_updated_at":"2026-08-14T00:00:00Z",
                    "searched_documents":42
                }
            }
            """#.utf8)
            return (Self.response(for: request, statusCode: 200), data)
        }
        let history = (0..<25).map {
            CoachChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, content: "message-\($0)")
        }
        let request = CoachChatRequest(
            coachID: "hypertrophy",
            message: "次回は重量を上げてもいい？",
            context: Self.emptyCoachContext(memories: ["重量は小刻みに上げたい"]),
            recentMessages: history
        )

        let response = try await makeClient().chat(payload: request)

        XCTAssertEqual(response.reply, "次回は1kgだけ上げてみましょう。")
        XCTAssertEqual(response.memoryCandidates.first?.content, "重量は小刻みに上げたい")
        XCTAssertEqual(response.evidence.first?.id, "PMID:12345678")
        XCTAssertEqual(response.evidence.first?.studyTypeLabel, "系統的レビュー")
        XCTAssertEqual(response.evidenceStatus.searchedDocuments, 42)
        let sentRequest = try XCTUnwrap(MockAIURLProtocol.lastRequest)
        XCTAssertEqual(sentRequest.url?.path, "/v1/agents/chat")
        XCTAssertEqual(sentRequest.timeoutInterval, 240, accuracy: 0.1)
        let body = try XCTUnwrap(MockAIURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["coach_id"] as? String, "hypertrophy")
        let sentMessages = try XCTUnwrap(json["recent_messages"] as? [[String: Any]])
        XCTAssertEqual(sentMessages.count, CoachChatRequest.maximumSentRecentMessages)
        XCTAssertTrue(sentMessages.allSatisfy { Set($0.keys) == ["role", "content"] })
        let context = try XCTUnwrap(json["context"] as? [String: Any])
        XCTAssertEqual(context["memories"] as? [String], ["重量は小刻みに上げたい"])
    }

    func testBackgroundTrainerUploadBuildsAuthenticatedFileRequest() async throws {
        let upload = try await makeClient().makeBackgroundChatUpload(
            payload: CoachChatRequest(
                coachID: "hypertrophy",
                message: "次回の重量を相談したい",
                context: Self.emptyCoachContext(memories: ["重量は小刻みに上げたい"]),
                recentMessages: []
            ),
            compacted: false
        )

        XCTAssertEqual(upload.request.url?.path, "/v1/agents/chat")
        XCTAssertEqual(upload.request.httpMethod, "POST")
        XCTAssertEqual(upload.request.timeoutInterval, 240, accuracy: 0.1)
        XCTAssertEqual(
            upload.request.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-api-key"
        )
        XCTAssertNil(upload.request.httpBody)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: upload.body) as? [String: Any])
        XCTAssertEqual(json["coach_id"] as? String, "hypertrophy")
        XCTAssertEqual(json["message"] as? String, "次回の重量を相談したい")
        let context = try XCTUnwrap(json["context"] as? [String: Any])
        XCTAssertEqual(context["memories"] as? [String], ["重量は小刻みに上げたい"])
    }

    func testWatchDiagnosticsAreImportedIntoShareableLog() {
        AppDiagnostics.shared.deleteData()
        let timestamp = Date().addingTimeInterval(-60)
        AppDiagnostics.shared.importWatchEvents([
            WatchDiagnosticEvent(
                timestamp: timestamp,
                category: "set.completed",
                message: "Set completed",
                metadata: ["reps": "10"]
            )
        ])

        XCTAssertEqual(AppDiagnostics.shared.eventCount(categoryPrefix: "watch."), 1)
        let exported = String(decoding: AppDiagnostics.shared.exportData(), as: UTF8.self)
        XCTAssertTrue(exported.contains("watch.set.completed"))
        XCTAssertTrue(exported.contains("apple_watch"))
        XCTAssertTrue(exported.contains("Set completed"))
    }

    func testTrainerChatRetriesOnceWithCompactedPayloadAfter413() async throws {
        MockAIURLProtocol.requestHandler = { request in
            if MockAIURLProtocol.requests.count == 1 {
                return (Self.response(for: request, statusCode: 413), Data())
            }
            return (
                Self.response(for: request, statusCode: 200),
                Data(#"{"reply":"圧縮後の回答","memory_candidates":[]}"#.utf8)
            )
        }
        let longText = String(repeating: "記録データ", count: 200)
        let context = CoachContext(
            recent7Days: Dictionary(uniqueKeysWithValues: (0..<20).map { ("exercise-\($0)", [longText, longText]) }),
            recent4Weeks: ["summary": [longText, longText, longText]],
            longTermTrends: ["trend": [longText]],
            personalRecords: Array(repeating: longText, count: 12),
            goals: ["筋肥大"],
            preferences: ["小刻みに増量"],
            memories: Array(repeating: longText, count: 30),
            previousSuggestion: [:],
            suggestionResult: [:]
        )
        let history = (0..<20).map {
            CoachChatMessage(role: .user, content: "\($0)-\(longText)")
        }

        let response = try await makeClient().chat(
            payload: CoachChatRequest(
                coachID: "hypertrophy",
                message: "相談",
                context: context,
                recentMessages: history
            )
        )

        XCTAssertEqual(response.reply, "圧縮後の回答")
        XCTAssertEqual(MockAIURLProtocol.requests.count, 2)
        XCTAssertEqual(MockAIURLProtocol.requestBodies.count, 2)
        XCTAssertLessThan(MockAIURLProtocol.requestBodies[1].count, MockAIURLProtocol.requestBodies[0].count)

        let initialJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: MockAIURLProtocol.requestBodies[0]) as? [String: Any]
        )
        let initialMessages = try XCTUnwrap(initialJSON["recent_messages"] as? [[String: Any]])
        XCTAssertLessThanOrEqual(initialMessages.count, CoachChatRequest.maximumSentRecentMessages)
        XCTAssertTrue(initialMessages.allSatisfy { message in
            Set(message.keys) == ["role", "content"]
                && ((message["content"] as? String)?.count ?? .max) <= 600
        })
        let initialContext = try XCTUnwrap(initialJSON["context"] as? [String: Any])
        let initialRecentValues = (initialContext["recent_7_days"] as? [String: [String]])?.values.flatMap { $0 } ?? []
        XCTAssertTrue(initialRecentValues.allSatisfy { $0.count <= 240 })

        let retryJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: MockAIURLProtocol.requestBodies[1]) as? [String: Any]
        )
        let retryMessages = try XCTUnwrap(retryJSON["recent_messages"] as? [[String: Any]])
        XCTAssertLessThanOrEqual(retryMessages.count, 4)
        XCTAssertTrue(retryMessages.allSatisfy { message in
            Set(message.keys) == ["role", "content"]
                && ((message["content"] as? String)?.count ?? .max) <= 300
        })
        let retryContext = try XCTUnwrap(retryJSON["context"] as? [String: Any])
        let retryRecentValues = (retryContext["recent_7_days"] as? [String: [String]])?.values.flatMap { $0 } ?? []
        XCTAssertTrue(retryRecentValues.allSatisfy { $0.count <= 120 })
    }

    func testTrainerChatMaps422ToInvalidRequest() async {
        MockAIURLProtocol.requestHandler = { request in
            (Self.response(for: request, statusCode: 422), Data())
        }

        do {
            _ = try await makeClient().chat(
                payload: CoachChatRequest(
                    coachID: "wellness",
                    message: "相談",
                    context: Self.emptyCoachContext(),
                    recentMessages: []
                )
            )
            XCTFail("Expected invalid request")
        } catch {
            XCTAssertEqual(
                AIClientError.presentation(for: error).message,
                "AIトレーナーへ送る内容の形式が正しくありません。"
            )
        }
    }

    private func makeClient(
        apiKey: String = "test-api-key",
        usesSessionTokens: Bool = false
    ) -> AIAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAIURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return AIAPIClient(
            settings: AISettings(
                isEnabled: true,
                baseURLString: "https://example.com",
                apiKey: apiKey,
                usesSessionTokens: usesSessionTokens
            ),
            session: session
        )
    }

    private func makeImageData(size: CGSize) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }

    private static func response(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func emptyCoachContext(memories: [String] = []) -> CoachContext {
        CoachContext(
            recent7Days: [:],
            recent4Weeks: [:],
            longTermTrends: [:],
            personalRecords: [],
            goals: [],
            preferences: [],
            memories: memories,
            previousSuggestion: [:],
            suggestionResult: [:]
        )
    }
}

private extension AIAPIClientTests {
    var coachTestProfile: UserProfile {
        var profile = UserProfile.default
        profile.goalType = .muscleGain
        profile.coachType = .hypertrophy
        profile.coachPersona = .maya
        profile.coachingStyle = .encouraging
        return profile
    }
}

private final class MockAIURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var requestBodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        Self.requests.append(request)
        if let lastRequestBody = Self.lastRequestBody {
            Self.requestBodies.append(lastRequestBody)
        }
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
