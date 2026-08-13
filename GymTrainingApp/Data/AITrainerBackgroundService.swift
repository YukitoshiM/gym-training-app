import Combine
import Foundation
import UIKit
@preconcurrency import UserNotifications

final class AITrainerBackgroundService: NSObject, ObservableObject, AITrainerBackgroundResetting, @unchecked Sendable {
    static let shared = AITrainerBackgroundService()
    static let sessionIdentifier = "com.yukitoshim.gymtrainingapp.ai-trainer.background"

    @Published private(set) var pendingRequestCount = 0
    @Published private(set) var pendingChatRequestCount = 0
    @Published private(set) var latestFailure: AITrainerBackgroundFailure?
    @Published private(set) var pendingMemoryCandidates: [CoachMemoryCandidate] = []

    private weak var appStore: AppStore?
    private let fileManager: FileManager
    private let applicationSupportURL: URL
    private let injectedSessionConfiguration: URLSessionConfiguration?
    private let stateQueue = DispatchQueue(label: "com.yukitoshim.gymtrainingapp.ai-trainer.state")
    private var pendingRequests: [UUID: PendingRequest] = [:]
    private var completedOutcomes: [CompletedOutcome] = []
    private var responseDataByTaskID: [Int: Data] = [:]
    private var activeTasksByRequestID: [UUID: URLSessionTask] = [:]
    private var uploadPreparationTasksByRequestID: [UUID: Task<PreparedBackgroundUploads, Error>] = [:]
    private var resetGeneration: UInt64 = 0
    private var backgroundEventsCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let configuration = injectedSessionConfiguration ?? Self.productionSessionConfiguration()
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private lazy var uploadPreparationSession: URLSession = {
        guard let injectedSessionConfiguration else { return .shared }
        return URLSession(configuration: injectedSessionConfiguration)
    }()

    var isSending: Bool {
        pendingChatRequestCount > 0
    }

    private override init() {
        fileManager = .default
        applicationSupportURL = Self.defaultApplicationSupportURL
        injectedSessionConfiguration = nil
        super.init()
        prepareService()
    }

    init(
        sessionConfiguration: URLSessionConfiguration,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
        injectedSessionConfiguration = sessionConfiguration
        super.init()
        prepareService()
    }

    private func prepareService() {
        loadPersistedState()
        pendingRequestCount = pendingRequests.count
        pendingChatRequestCount = pendingRequests.values.filter(\.kind.isChat).count
        _ = session
    }

    private static func productionSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        return configuration
    }

    @MainActor
    func bind(appStore: AppStore) {
        self.appStore = appStore
        applyCompletedOutcomesIfPossible()
        refreshPendingTaskCount()
    }

    @MainActor
    func reset() {
        let tasks = stateQueue.sync { () -> (
            uploads: [URLSessionTask],
            preparations: [Task<PreparedBackgroundUploads, Error>],
            requestIDs: Set<UUID>
        ) in
            resetGeneration &+= 1
            let requestIDs = Set(pendingRequests.keys).union(activeTasksByRequestID.keys)
            let uploads = Array(activeTasksByRequestID.values)
            let preparations = Array(uploadPreparationTasksByRequestID.values)
            pendingRequests.removeAll()
            completedOutcomes.removeAll()
            responseDataByTaskID.removeAll()
            activeTasksByRequestID.removeAll()
            uploadPreparationTasksByRequestID.removeAll()
            removePersistedArtifactsLocked()
            return (uploads, preparations, requestIDs)
        }

        tasks.preparations.forEach { $0.cancel() }
        tasks.uploads.forEach { $0.cancel() }
        let requestIDsToCancel = tasks.requestIDs
        session.getAllTasks { [weak self] sessionTasks in
            guard let self else { return }
            let currentRequestIDs = stateQueue.sync { Set(pendingRequests.keys) }
            for task in sessionTasks {
                let requestID = task.taskDescription.flatMap(UUID.init(uuidString:))
                let belongsToReset = requestID.map(requestIDsToCancel.contains) ?? true
                let isCurrentRequest = requestID.map(currentRequestIDs.contains) ?? false
                if belongsToReset || !isCurrentRequest {
                    task.cancel()
                }
            }
        }

        pendingRequestCount = 0
        pendingChatRequestCount = 0
        latestFailure = nil
        pendingMemoryCandidates = []
        AppDiagnostics.shared.record(
            level: "info",
            category: "ai.background",
            message: "AI trainer background state reset"
        )
    }

    @MainActor
    func submit(
        payload: CoachChatRequest,
        transmissionID: UUID,
        settings: AISettings
    ) async throws {
        try await enqueue(payload: payload, transmissionID: transmissionID, settings: settings, kind: .chat)
    }

    @MainActor
    func submitDailyRecommendation(
        payload: CoachChatRequest,
        transmissionID: UUID,
        settings: AISettings,
        date: Date
    ) async throws {
        try await enqueue(
            payload: payload,
            transmissionID: transmissionID,
            settings: settings,
            kind: .dailyRecommendation(date: Calendar.current.startOfDay(for: date))
        )
    }

    @MainActor
    private func enqueue(
        payload: CoachChatRequest,
        transmissionID: UUID,
        settings: AISettings,
        kind: AIBackgroundRequestKind
    ) async throws {
        if kind.isChat, isSending {
            return
        }

        latestFailure = nil
        if kind.isChat {
            requestNotificationAuthorization()
        }
        let generation = stateQueue.sync { resetGeneration }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--stub-ai-trainer") {
            pendingRequestCount += 1
            if kind.isChat {
                pendingChatRequestCount += 1
            }
            Task { [weak self] in
                do {
                    let response = try await AIAPIClient(settings: settings).chat(payload: payload)
                    self?.persist(
                        outcome: CompletedOutcome(
                            requestID: UUID(),
                            transmissionID: transmissionID,
                            originalMessage: payload.message,
                            response: response,
                            failure: nil,
                            kind: kind
                        ),
                        generation: generation
                    )
                } catch {
                    self?.persist(
                        outcome: CompletedOutcome(
                            requestID: UUID(),
                            transmissionID: transmissionID,
                            originalMessage: payload.message,
                            response: nil,
                            failure: Self.failure(for: error),
                            kind: kind
                        ),
                        generation: generation
                    )
                }
                await MainActor.run {
                    guard self?.stateQueue.sync(execute: { self?.resetGeneration == generation }) == true else {
                        AIAuthenticationStore.shared.reset()
                        SecureSettingsStore.deleteInstallationID()
                        return
                    }
                    self?.pendingRequestCount = max(0, (self?.pendingRequestCount ?? 1) - 1)
                    if kind.isChat {
                        self?.pendingChatRequestCount = max(0, (self?.pendingChatRequestCount ?? 1) - 1)
                    }
                    self?.applyCompletedOutcomesIfPossible()
                }
            }
            return
        }
        #endif

        let requestID = UUID()
        let client = AIAPIClient(settings: settings, session: uploadPreparationSession)
        let preparationTask = Task {
            let initial = try await client.makeBackgroundChatUpload(payload: payload, compacted: false)
            let retry = try await client.makeBackgroundChatUpload(payload: payload, compacted: true)
            return PreparedBackgroundUploads(initial: initial, retry: retry)
        }
        stateQueue.sync {
            uploadPreparationTasksByRequestID[requestID] = preparationTask
        }

        let prepared: PreparedBackgroundUploads
        do {
            prepared = try await withTaskCancellationHandler {
                try await preparationTask.value
            } onCancel: {
                preparationTask.cancel()
            }
        } catch {
            let wasReset = stateQueue.sync { () -> Bool in
                uploadPreparationTasksByRequestID.removeValue(forKey: requestID)
                return resetGeneration != generation
            }
            if wasReset {
                AIAuthenticationStore.shared.reset()
                SecureSettingsStore.deleteInstallationID()
                throw CancellationError()
            }
            throw error
        }

        let shouldEnqueue = stateQueue.sync { () -> Bool in
            uploadPreparationTasksByRequestID.removeValue(forKey: requestID)
            return resetGeneration == generation
        }
        try Task.checkCancellation()
        guard shouldEnqueue else {
            AIAuthenticationStore.shared.reset()
            SecureSettingsStore.deleteInstallationID()
            throw CancellationError()
        }

        let initialUpload = prepared.initial
        let retryUpload = prepared.retry
        let initialFile = try writeUploadBody(initialUpload.body, requestID: requestID, suffix: "initial")
        let retryFile = try writeUploadBody(retryUpload.body, requestID: requestID, suffix: "retry")
        let pending = PendingRequest(
            id: requestID,
            transmissionID: transmissionID,
            originalMessage: payload.message,
            initialBodyFileName: initialFile.lastPathComponent,
            retryBodyFileName: retryFile.lastPathComponent,
            hasRetriedWithCompactedContext: false,
            createdAt: Date(),
            kind: kind
        )

        stateQueue.sync {
            pendingRequests[requestID] = pending
            persistStateLocked()
        }

        var request = initialUpload.request
        request.httpBody = nil
        let task = session.uploadTask(with: request, fromFile: initialFile)
        task.taskDescription = requestID.uuidString
        let shouldStart = stateQueue.sync { () -> Bool in
            guard pendingRequests[requestID] != nil else { return false }
            activeTasksByRequestID[requestID] = task
            return true
        }
        guard shouldStart else {
            task.cancel()
            removeUploadFiles(for: pending)
            return
        }
        pendingRequestCount = stateQueue.sync { pendingRequests.count }
        pendingChatRequestCount = stateQueue.sync {
            pendingRequests.values.filter(\.kind.isChat).count
        }
        AppDiagnostics.shared.record(
            level: "info",
            category: "ai.background",
            message: "AI trainer background request queued",
            metadata: ["request_id": requestID.uuidString]
        )
        task.resume()
    }

    @MainActor
    func takeLatestFailure() -> AITrainerBackgroundFailure? {
        defer { latestFailure = nil }
        return latestFailure
    }

    @MainActor
    func takeMemoryCandidates() -> [CoachMemoryCandidate] {
        defer { pendingMemoryCandidates = [] }
        return pendingMemoryCandidates
    }

    func handleEvents(
        forBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == Self.sessionIdentifier else {
            completionHandler()
            return
        }
        _ = session
        stateQueue.sync {
            backgroundEventsCompletionHandler = completionHandler
        }
    }

    @MainActor
    private func applyCompletedOutcomesIfPossible() {
        guard let appStore else { return }

        let outcomes = stateQueue.sync { () -> [CompletedOutcome] in
            let outcomes = completedOutcomes
            completedOutcomes = []
            persistStateLocked()
            return outcomes
        }

        for outcome in outcomes {
            if let response = outcome.response {
                appStore.updateAITransmission(id: outcome.transmissionID, status: .completed)
                switch outcome.kind {
                case .chat:
                    appStore.appendCoachChatMessage(
                        CoachChatMessage(
                            role: .assistant,
                            content: CoachReplyPolicy.limitingFollowUpQuestions(response.reply),
                            evidence: response.evidence
                        )
                    )
                    pendingMemoryCandidates = appStore.newCoachMemoryCandidates(response.memoryCandidates)
                    notifyCompletionIfNeeded(success: true)
                case .dailyRecommendation(let date):
                    appStore.applyDailyAIResponse(response.reply, for: date)
                    notifyDailyRecommendationCompletionIfNeeded()
                }
            } else if let failure = outcome.failure {
                appStore.updateAITransmission(id: outcome.transmissionID, status: .failed)
                switch outcome.kind {
                case .chat:
                    latestFailure = AITrainerBackgroundFailure(
                        originalMessage: outcome.originalMessage,
                        presentation: AIErrorPresentation(
                            message: failure.message,
                            recovery: failure.recovery
                        )
                    )
                    notifyCompletionIfNeeded(success: false)
                case .dailyRecommendation:
                    break
                }
            }
        }
    }

    @MainActor
    private func refreshPendingTaskCount() {
        let generation = stateQueue.sync { resetGeneration }
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            guard stateQueue.sync(execute: { resetGeneration == generation }) else { return }
            let activeRequestIDs = Set(tasks.compactMap { task in
                task.taskDescription.flatMap(UUID.init(uuidString:))
            })
            let orphaned = stateQueue.sync {
                pendingRequests.values.filter { !activeRequestIDs.contains($0.id) }
            }
            for pending in orphaned {
                finish(
                    pending: pending,
                    response: nil,
                    failure: PersistedFailure(
                        message: "前回のAIトレーナー送信を再開できませんでした。",
                        recovery: "同じ内容をもう一度送信してください。"
                    )
                )
            }
            let storedCounts = stateQueue.sync {
                (
                    all: pendingRequests.count,
                    chat: pendingRequests.values.filter(\.kind.isChat).count
                )
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard stateQueue.sync(execute: { resetGeneration == generation }) else { return }
                pendingRequestCount = max(tasks.count, storedCounts.all)
                pendingChatRequestCount = storedCounts.chat
                applyCompletedOutcomesIfPossible()
            }
        }
    }

    private func complete(task: URLSessionTask, error: Error?) {
        let data = stateQueue.sync {
            responseDataByTaskID.removeValue(forKey: task.taskIdentifier) ?? Data()
        }
        guard let description = task.taskDescription,
              let requestID = UUID(uuidString: description),
              let pending = stateQueue.sync(execute: { pendingRequests[requestID] }) else {
            return
        }

        if let error {
            finish(pending: pending, response: nil, failure: Self.failure(for: error))
            return
        }

        guard let response = task.response as? HTTPURLResponse else {
            finish(
                pending: pending,
                response: nil,
                failure: Self.failure(for: AIClientError.invalidResponse)
            )
            return
        }

        if response.statusCode == 413, !pending.hasRetriedWithCompactedContext {
            retryWithCompactedContext(pending: pending, originalTask: task)
            return
        }

        guard 200..<300 ~= response.statusCode else {
            let error: Error
            switch response.statusCode {
            case 413:
                error = AITrainerError.contextTooLarge
            case 422:
                error = AITrainerError.invalidRequest
            default:
                error = AIClientError.httpStatus(response.statusCode)
            }
            finish(pending: pending, response: nil, failure: Self.failure(for: error))
            return
        }

        do {
            let response = try JSONDecoder().decode(CoachChatResponse.self, from: data)
            finish(pending: pending, response: response, failure: nil)
        } catch {
            finish(
                pending: pending,
                response: nil,
                failure: Self.failure(for: AIClientError.decodingFailed(error.localizedDescription))
            )
        }
    }

    private func retryWithCompactedContext(pending: PendingRequest, originalTask: URLSessionTask) {
        guard var request = originalTask.originalRequest else {
            finish(pending: pending, response: nil, failure: Self.failure(for: AITrainerError.contextTooLarge))
            return
        }
        let retryURL = uploadDirectoryURL.appendingPathComponent(pending.retryBodyFileName)
        guard fileManager.fileExists(atPath: retryURL.path) else {
            finish(pending: pending, response: nil, failure: Self.failure(for: AITrainerError.contextTooLarge))
            return
        }

        request.httpBody = nil
        let retryTask = session.uploadTask(with: request, fromFile: retryURL)
        retryTask.taskDescription = pending.id.uuidString
        let shouldRetry = stateQueue.sync { () -> Bool in
            guard pendingRequests[pending.id] != nil else { return false }
            var updated = pending
            updated.hasRetriedWithCompactedContext = true
            pendingRequests[pending.id] = updated
            activeTasksByRequestID[pending.id] = retryTask
            persistStateLocked()
            return true
        }
        guard shouldRetry else {
            retryTask.cancel()
            return
        }
        AppDiagnostics.shared.record(
            level: "info",
            category: "ai.background",
            message: "Retrying AI trainer request with compacted context",
            metadata: ["request_id": pending.id.uuidString]
        )
        retryTask.resume()
    }

    private func finish(
        pending: PendingRequest,
        response: CoachChatResponse?,
        failure: PersistedFailure?
    ) {
        let outcome = CompletedOutcome(
                requestID: pending.id,
                transmissionID: pending.transmissionID,
                originalMessage: pending.originalMessage,
                response: response,
                failure: failure,
                kind: pending.kind
            )
        let accepted = stateQueue.sync { () -> Bool in
            guard pendingRequests[pending.id] != nil else { return false }
            completedOutcomes.append(outcome)
            pendingRequests.removeValue(forKey: pending.id)
            activeTasksByRequestID.removeValue(forKey: pending.id)
            persistStateLocked()
            return true
        }
        guard accepted else { return }
        removeUploadFiles(for: pending)

        AppDiagnostics.shared.record(
            level: failure == nil ? "info" : "error",
            category: "ai.background",
            message: failure == nil ? "AI trainer background request completed" : "AI trainer background request failed",
            metadata: ["request_id": pending.id.uuidString]
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            pendingRequestCount = stateQueue.sync { pendingRequests.count }
            pendingChatRequestCount = stateQueue.sync {
                pendingRequests.values.filter(\.kind.isChat).count
            }
            applyCompletedOutcomesIfPossible()
        }
    }

    private func persist(outcome: CompletedOutcome, generation: UInt64) {
        stateQueue.sync {
            guard resetGeneration == generation else { return }
            completedOutcomes.append(outcome)
            persistStateLocked()
        }
    }

    private func writeUploadBody(_ data: Data, requestID: UUID, suffix: String) throws -> URL {
        try fileManager.createDirectory(
            at: uploadDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = uploadDirectoryURL
        try directory.setResourceValues(values)

        let url = uploadDirectoryURL
            .appendingPathComponent("\(requestID.uuidString)-\(suffix)")
            .appendingPathExtension("json")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    private func removeUploadFiles(for pending: PendingRequest) {
        for fileName in [pending.initialBodyFileName, pending.retryBodyFileName] {
            try? fileManager.removeItem(at: uploadDirectoryURL.appendingPathComponent(fileName))
        }
    }

    private func loadPersistedState() {
        stateQueue.sync {
            guard let data = try? Data(contentsOf: stateFileURL),
                  let state = try? JSONDecoder.backgroundAI.decode(PersistedState.self, from: data) else {
                return
            }
            pendingRequests = Dictionary(uniqueKeysWithValues: state.pendingRequests.map { ($0.id, $0) })
            completedOutcomes = state.completedOutcomes
        }
    }

    private func persistStateLocked() {
        guard !pendingRequests.isEmpty || !completedOutcomes.isEmpty else {
            try? fileManager.removeItem(at: stateFileURL)
            return
        }
        do {
            try fileManager.createDirectory(
                at: stateFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            let state = PersistedState(
                pendingRequests: Array(pendingRequests.values),
                completedOutcomes: completedOutcomes
            )
            try JSONEncoder.backgroundAI.encode(state).write(
                to: stateFileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            AppDiagnostics.shared.record(
                error: error,
                category: "ai.background.persistence",
                message: "Failed to persist background AI state"
            )
        }
    }

    private func removePersistedArtifactsLocked() {
        try? fileManager.removeItem(at: stateFileURL)
        try? fileManager.removeItem(at: uploadDirectoryURL)
    }

    private func requestNotificationAuthorization() {
        guard !ProcessInfo.processInfo.arguments.contains("--reset-ui-test-data") else {
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    private func notifyCompletionIfNeeded(success: Bool) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = success ? "AIトレーナーから回答が届きました" : "AIトレーナーへ送信できませんでした"
        content.body = success ? "BodyModeを開いて回答を確認できます。" : "アプリを開いて再試行してください。"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "bodymode.ai-trainer.\(UUID().uuidString)", content: content, trigger: nil)
        )
    }

    @MainActor
    private func notifyDailyRecommendationCompletionIfNeeded() {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "今日の提案を更新しました"
        content.body = "新しい記録を反映しました。"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "bodymode.daily-recommendation.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }

    private static func failure(for error: Error) -> PersistedFailure {
        let presentation = AIClientError.presentation(for: error)
        return PersistedFailure(message: presentation.message, recovery: presentation.recovery)
    }

    private var stateFileURL: URL {
        applicationSupportURL.appendingPathComponent("ai-trainer-background-state.json")
    }

    private var uploadDirectoryURL: URL {
        applicationSupportURL.appendingPathComponent("AITrainerUploads", isDirectory: true)
    }

    private static var defaultApplicationSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GymTraining", isDirectory: true)
    }
}

extension AITrainerBackgroundService: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stateQueue.sync {
            guard let description = dataTask.taskDescription,
                  let requestID = UUID(uuidString: description),
                  pendingRequests[requestID] != nil else {
                return
            }
            responseDataByTaskID[dataTask.taskIdentifier, default: Data()].append(data)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        complete(task: task, error: error)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = stateQueue.sync { () -> (() -> Void)? in
            defer { backgroundEventsCompletionHandler = nil }
            return backgroundEventsCompletionHandler
        }
        DispatchQueue.main.async {
            completion?()
        }
    }
}

struct AITrainerBackgroundFailure: Equatable {
    var originalMessage: String
    var presentation: AIErrorPresentation
}

private enum AIBackgroundRequestKind: Codable {
    case chat
    case dailyRecommendation(date: Date)

    var isChat: Bool {
        if case .chat = self { return true }
        return false
    }
}

private struct PendingRequest: Codable {
    var id: UUID
    var transmissionID: UUID
    var originalMessage: String
    var initialBodyFileName: String
    var retryBodyFileName: String
    var hasRetriedWithCompactedContext: Bool
    var createdAt: Date
    var kind: AIBackgroundRequestKind

    private enum CodingKeys: String, CodingKey {
        case id, transmissionID, originalMessage, initialBodyFileName, retryBodyFileName
        case hasRetriedWithCompactedContext, createdAt, kind
    }

    init(
        id: UUID,
        transmissionID: UUID,
        originalMessage: String,
        initialBodyFileName: String,
        retryBodyFileName: String,
        hasRetriedWithCompactedContext: Bool,
        createdAt: Date,
        kind: AIBackgroundRequestKind
    ) {
        self.id = id
        self.transmissionID = transmissionID
        self.originalMessage = originalMessage
        self.initialBodyFileName = initialBodyFileName
        self.retryBodyFileName = retryBodyFileName
        self.hasRetriedWithCompactedContext = hasRetriedWithCompactedContext
        self.createdAt = createdAt
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        transmissionID = try container.decode(UUID.self, forKey: .transmissionID)
        originalMessage = try container.decode(String.self, forKey: .originalMessage)
        initialBodyFileName = try container.decode(String.self, forKey: .initialBodyFileName)
        retryBodyFileName = try container.decode(String.self, forKey: .retryBodyFileName)
        hasRetriedWithCompactedContext = try container.decode(Bool.self, forKey: .hasRetriedWithCompactedContext)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decodeIfPresent(AIBackgroundRequestKind.self, forKey: .kind) ?? .chat
    }
}

private struct PersistedFailure: Codable {
    var message: String
    var recovery: String?
}

private struct CompletedOutcome: Codable {
    var requestID: UUID
    var transmissionID: UUID
    var originalMessage: String
    var response: CoachChatResponse?
    var failure: PersistedFailure?
    var kind: AIBackgroundRequestKind

    private enum CodingKeys: String, CodingKey {
        case requestID, transmissionID, originalMessage, response, failure, kind
    }

    init(
        requestID: UUID,
        transmissionID: UUID,
        originalMessage: String,
        response: CoachChatResponse?,
        failure: PersistedFailure?,
        kind: AIBackgroundRequestKind
    ) {
        self.requestID = requestID
        self.transmissionID = transmissionID
        self.originalMessage = originalMessage
        self.response = response
        self.failure = failure
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        transmissionID = try container.decode(UUID.self, forKey: .transmissionID)
        originalMessage = try container.decode(String.self, forKey: .originalMessage)
        response = try container.decodeIfPresent(CoachChatResponse.self, forKey: .response)
        failure = try container.decodeIfPresent(PersistedFailure.self, forKey: .failure)
        kind = try container.decodeIfPresent(AIBackgroundRequestKind.self, forKey: .kind) ?? .chat
    }
}

private struct PersistedState: Codable {
    var pendingRequests: [PendingRequest]
    var completedOutcomes: [CompletedOutcome]
}

private struct PreparedBackgroundUploads: @unchecked Sendable {
    var initial: AIBackgroundChatUpload
    var retry: AIBackgroundChatUpload
}

private extension JSONEncoder {
    static var backgroundAI: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var backgroundAI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
