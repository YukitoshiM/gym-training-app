import XCTest
@testable import GymTrainingApp

final class AISettingsMigrationTests: XCTestCase {
    private let bundled = AISettings(
        isEnabled: true,
        baseURLString: "https://current.example.com",
        apiKey: "current-key",
        usesSessionTokens: true,
        managedConfigurationVersion: 3
    )

    func testRetiredBundledURLMigratesWithoutChangingUserPreferences() {
        let sharing = AIDataSharingSettings(
            bodyMetrics: true,
            meals: false,
            workouts: true,
            bodyPhotos: false,
            sleepAndRecovery: true,
            dailyActivity: false,
            gymVisits: true,
            workoutSensors: false
        )
        let stored = AISettings(
            isEnabled: false,
            baseURLString: "http://127.0.0.1:8765/",
            apiKey: "old-key",
            dataSharing: sharing
        )

        let migrated = stored.migratingManagedConfiguration(to: bundled)

        XCTAssertFalse(migrated.isEnabled)
        XCTAssertEqual(migrated.dataSharing, sharing)
        XCTAssertEqual(migrated.baseURLString, bundled.baseURLString)
        XCTAssertEqual(migrated.apiKey, bundled.apiKey)
        XCTAssertTrue(migrated.usesSessionTokens)
        XCTAssertEqual(migrated.managedConfigurationVersion, 3)
    }

    func testExpiredQuickTunnelURLAlsoMigrates() {
        let stored = AISettings(
            isEnabled: true,
            baseURLString: "https://alike-generate-ghz-seo.trycloudflare.com",
            apiKey: "old-key"
        )

        XCTAssertEqual(stored.migratingManagedConfiguration(to: bundled).baseURLString, bundled.baseURLString)
    }

    func testBuildNineQuickTunnelMigratesToBuildTenConfiguration() {
        let stored = AISettings(
            isEnabled: true,
            baseURLString: "https://christopher-using-organisations-hull.trycloudflare.com",
            apiKey: "build-nine-key",
            managedConfigurationVersion: 2
        )

        let migrated = stored.migratingManagedConfiguration(to: bundled)

        XCTAssertEqual(migrated.baseURLString, bundled.baseURLString)
        XCTAssertEqual(migrated.apiKey, bundled.apiKey)
        XCTAssertEqual(migrated.usesSessionTokens, bundled.usesSessionTokens)
        XCTAssertEqual(migrated.managedConfigurationVersion, 3)
    }

    func testOlderManagedConfigurationMigratesToCurrentVersion() {
        let stored = AISettings(
            isEnabled: true,
            baseURLString: "https://previous.example.com",
            apiKey: "previous-key",
            managedConfigurationVersion: 1
        )

        XCTAssertEqual(stored.migratingManagedConfiguration(to: bundled).baseURLString, bundled.baseURLString)
    }

    func testUnversionedBundledConfigurationAdoptsManagedFields() {
        let stored = AISettings(
            isEnabled: false,
            baseURLString: bundled.baseURLString,
            apiKey: bundled.apiKey,
            usesSessionTokens: false,
            dataSharing: .default
        )

        let migrated = stored.migratingManagedConfiguration(to: bundled)

        XCTAssertFalse(migrated.isEnabled)
        XCTAssertEqual(migrated.baseURLString, bundled.baseURLString)
        XCTAssertEqual(migrated.apiKey, bundled.apiKey)
        XCTAssertEqual(migrated.usesSessionTokens, bundled.usesSessionTokens)
        XCTAssertEqual(migrated.managedConfigurationVersion, bundled.managedConfigurationVersion)
    }

    func testChangedManagedConfigurationMigratesEvenWhenVersionWasNotBumped() {
        var sameVersionBundled = bundled
        sameVersionBundled.managedConfigurationVersion = 2
        let stored = AISettings(
            isEnabled: true,
            baseURLString: "https://previous-managed.example.com",
            apiKey: "previous-key",
            managedConfigurationVersion: 2
        )

        let migrated = stored.migratingManagedConfiguration(to: sameVersionBundled)

        XCTAssertEqual(migrated.baseURLString, sameVersionBundled.baseURLString)
        XCTAssertEqual(migrated.apiKey, sameVersionBundled.apiKey)
        XCTAssertEqual(migrated.managedConfigurationVersion, 2)
    }

    func testCustomServerIsNotOverwritten() {
        let stored = AISettings(
            isEnabled: true,
            baseURLString: "https://user-tailnet.example.com",
            apiKey: "user-key",
            usesSessionTokens: false
        )

        XCTAssertEqual(stored.migratingManagedConfiguration(to: bundled), stored)
    }

    func testPersistenceMarksBundledConfigurationAndUnmarksCustomConfiguration() {
        XCTAssertEqual(
            bundled.normalizedForPersistence(relativeTo: bundled).managedConfigurationVersion,
            3
        )

        var custom = bundled
        custom.baseURLString = "https://custom.example.com"
        XCTAssertNil(custom.normalizedForPersistence(relativeTo: bundled).managedConfigurationVersion)
    }

    @MainActor
    func testDeleteAllInvokesInjectedBackgroundResetBeforeClearingAppData() {
        let repository = TestAppDataRepository()
        repository.coachChatMessages = [CoachChatMessage(role: .assistant, content: "削除前の回答")]
        let store = AppStore(storage: repository)
        let resetter = BackgroundResetSpy()

        store.resetAllData(backgroundAIService: resetter)

        XCTAssertEqual(resetter.resetCallCount, 1)
        XCTAssertTrue(store.coachChatMessages.isEmpty)
        XCTAssertTrue(store.aiTransmissionHistory.isEmpty)
    }

    @MainActor
    func testDeleteAllClearsAIIdentityWithInjectedRepository() {
        SecureSettingsStore.resetAIIdentity()
        defer { SecureSettingsStore.resetAIIdentity() }

        let token = AICachedAccessToken(
            value: "app-store-reset-token",
            baseURLString: "https://reset.example.com",
            expiresAt: Date().addingTimeInterval(3_600)
        )
        XCTAssertTrue(SecureSettingsStore.saveAPIKey("app-store-reset-key"))
        AIAuthenticationStore.shared.save(token)
        let previousInstallationID = SecureSettingsStore.installationID()
        let store = AppStore(storage: TestAppDataRepository())

        store.resetAllData(backgroundAIService: BackgroundResetSpy())

        XCTAssertNil(SecureSettingsStore.loadAPIKey())
        XCTAssertNil(SecureSettingsStore.loadAccessToken())
        XCTAssertNil(AIAuthenticationStore.shared.usableToken(for: token.baseURLString))
        XCTAssertNotEqual(SecureSettingsStore.installationID(), previousInstallationID)
    }

    func testLocalStorageResetDeletesAIKeyTokenAndInstallationIdentity() throws {
        SecureSettingsStore.resetAIIdentity()
        defer { SecureSettingsStore.resetAIIdentity() }

        XCTAssertTrue(SecureSettingsStore.saveAPIKey("reset-test-api-key"))
        let token = AICachedAccessToken(
            value: "reset-test-token",
            baseURLString: "https://reset.example.com",
            expiresAt: Date().addingTimeInterval(3_600)
        )
        AIAuthenticationStore.shared.save(token)
        let previousInstallationID = SecureSettingsStore.installationID()

        LocalJSONStorage().reset()

        XCTAssertNil(SecureSettingsStore.loadAPIKey())
        XCTAssertNil(SecureSettingsStore.loadAccessToken())
        XCTAssertNil(AIAuthenticationStore.shared.usableToken(for: token.baseURLString))
        let replacementInstallationID = SecureSettingsStore.installationID()
        XCTAssertNotEqual(replacementInstallationID, previousInstallationID)
        XCTAssertFalse(replacementInstallationID.isEmpty)
    }

    @MainActor
    func testBackgroundResetRemovesQueuedFilesAndRejectsLateResponse() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-background-reset-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        DelayedBackgroundAIURLProtocol.responseDelay = 0.35
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedBackgroundAIURLProtocol.self]
        let service = AITrainerBackgroundService(
            sessionConfiguration: configuration,
            applicationSupportURL: root
        )
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        service.bind(appStore: store)

        try await service.submit(
            payload: Self.chatRequest,
            transmissionID: UUID(),
            settings: Self.testAISettings
        )

        let stateURL = root.appendingPathComponent("ai-trainer-background-state.json")
        let uploadURL = root.appendingPathComponent("AITrainerUploads", isDirectory: true)
        XCTAssertEqual(service.pendingRequestCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: uploadURL.path).count, 2)

        service.reset()

        XCTAssertEqual(service.pendingRequestCount, 0)
        XCTAssertEqual(service.pendingChatRequestCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: uploadURL.path))

        try await Task.sleep(for: .milliseconds(550))
        XCTAssertTrue(store.coachChatMessages.isEmpty)
        XCTAssertTrue(store.aiTransmissionHistory.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    @MainActor
    func testBackgroundResetRemovesPersistedCompletedOutcomeBeforeBinding() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-background-completed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        DelayedBackgroundAIURLProtocol.responseDelay = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedBackgroundAIURLProtocol.self]
        let service = AITrainerBackgroundService(
            sessionConfiguration: configuration,
            applicationSupportURL: root
        )

        try await service.submit(
            payload: Self.chatRequest,
            transmissionID: UUID(),
            settings: Self.testAISettings
        )
        try await Self.waitUntil { service.pendingRequestCount == 0 }

        let stateURL = root.appendingPathComponent("ai-trainer-background-state.json")
        let stateData = try Data(contentsOf: stateURL)
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: stateData) as? [String: Any])
        XCTAssertEqual((state["completedOutcomes"] as? [Any])?.count, 1)

        service.reset()
        let store = AppStore(storage: TestAppDataRepository())
        service.bind(appStore: store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertTrue(store.coachChatMessages.isEmpty)
    }

    @MainActor
    func testDeleteAllDuringTokenPreparationCannotRepopulateAIState() async throws {
        SecureSettingsStore.resetAIIdentity()
        defer { SecureSettingsStore.resetAIIdentity() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-background-auth-reset-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        DelayedAuthenticationURLProtocol.tokenRequestStarted = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedAuthenticationURLProtocol.self]
        let service = AITrainerBackgroundService(
            sessionConfiguration: configuration,
            applicationSupportURL: root
        )
        let store = AppStore(storage: TestAppDataRepository())
        service.bind(appStore: store)
        let previousInstallationID = SecureSettingsStore.installationID()
        var tokenSettings = Self.testAISettings
        tokenSettings.usesSessionTokens = true

        let submission = Task { @MainActor in
            try? await service.submit(
                payload: Self.chatRequest,
                transmissionID: UUID(),
                settings: tokenSettings
            )
        }
        try await Self.waitUntil { DelayedAuthenticationURLProtocol.tokenRequestStarted }

        store.resetAllData(backgroundAIService: service)
        await submission.value
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(service.pendingRequestCount, 0)
        XCTAssertNil(SecureSettingsStore.loadAccessToken())
        XCTAssertNotEqual(SecureSettingsStore.installationID(), previousInstallationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("AITrainerUploads").path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("ai-trainer-background-state.json").path
            )
        )
        XCTAssertTrue(store.coachChatMessages.isEmpty)
        XCTAssertTrue(store.aiTransmissionHistory.isEmpty)
    }

    private static let testAISettings = AISettings(
        isEnabled: true,
        baseURLString: "https://background-reset.example.com",
        apiKey: "test-key"
    )

    private static let chatRequest = CoachChatRequest(
        coachID: "wellness",
        message: "削除テスト",
        context: CoachContext(
            recent7Days: [:],
            recent4Weeks: [:],
            longTermTrends: [:],
            personalRecords: [],
            goals: [],
            preferences: [],
            memories: [],
            previousSuggestion: [:],
            suggestionResult: [:]
        ),
        recentMessages: []
    )

    @MainActor
    private static func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for background AI state")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class BackgroundResetSpy: AITrainerBackgroundResetting {
    private(set) var resetCallCount = 0

    func reset() {
        resetCallCount += 1
    }
}

private final class DelayedBackgroundAIURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseDelay: TimeInterval = 0
    private var responseWorkItem: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://background-reset.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = Data(#"{"reply":"削除後に届いた回答","memory_candidates":[]}"#.utf8)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        responseWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.responseDelay, execute: workItem)
    }

    override func stopLoading() {
        // Intentionally allow the callback to run so the reset generation guard is exercised.
    }
}

private final class DelayedAuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var tokenRequestStarted = false
    private var responseWorkItem: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isTokenRequest = request.url?.path.hasSuffix("/v1/auth/token") == true
        if isTokenRequest {
            Self.tokenRequestStarted = true
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://background-reset.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = isTokenRequest
            ? Data(#"{"access_token":"late-token","token_type":"bearer","expires_in":3600}"#.utf8)
            : Data(#"{"reply":"late reply","memory_candidates":[]}"#.utf8)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        responseWorkItem = workItem
        DispatchQueue.global().asyncAfter(
            deadline: .now() + (isTokenRequest ? 0.35 : 0),
            execute: workItem
        )
    }

    override func stopLoading() {
        // Keep the delayed callback scheduled to exercise the post-reset generation barrier.
    }
}
