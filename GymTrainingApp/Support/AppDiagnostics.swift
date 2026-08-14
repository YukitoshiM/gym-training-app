import Foundation
import MetricKit
import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class AppDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = AppDiagnostics()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yukitoshim.gymtrainingapp",
        category: "Diagnostics"
    )
    private let queue = DispatchQueue(label: "com.yukitoshim.gymtrainingapp.diagnostics")
    private var isStarted = false
    private static let retentionInterval: TimeInterval = 14 * 24 * 60 * 60
    private static let maximumEventCount = 1_000
    private static let maximumLogBytes = 2 * 1_024 * 1_024

    private override init() {
        super.init()
    }

    func start() {
        queue.sync {
            guard !isStarted else { return }
            isStarted = true
            MXMetricManager.shared.add(self)
            pruneLog()
        }
        record(level: "info", category: "lifecycle", message: "App diagnostics started")
    }

    func record(
        timestamp: Date = Date(),
        level: String = "error",
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        logger.log(level: level == "error" ? .error : .info, "\(category, privacy: .public): \(message, privacy: .public)")

        let event = DiagnosticEvent(
            timestamp: timestamp,
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )
        guard let data = try? JSONEncoder.diagnostic.encode(event) else { return }
        appendLine(data)
    }

    func importWatchEvents(_ events: [WatchDiagnosticEvent]) {
        for event in events {
            var metadata = event.metadata
            metadata["source"] = "apple_watch"
            metadata["watch_event_id"] = event.id.uuidString
            record(
                timestamp: event.timestamp,
                level: event.level,
                category: "watch.\(event.category)",
                message: event.message,
                metadata: metadata
            )
        }
    }

    func eventCount(categoryPrefix: String? = nil) -> Int {
        queue.sync {
            pruneLog()
            guard let data = try? Data(contentsOf: Self.logURL) else { return 0 }
            return data.split(separator: 0x0A).reduce(into: 0) { count, bytes in
                guard let event = try? JSONDecoder.diagnostic.decode(
                    DiagnosticEvent.self,
                    from: Data(bytes)
                ) else {
                    return
                }
                guard let categoryPrefix else {
                    count += 1
                    return
                }
                if event.category.hasPrefix(categoryPrefix) { count += 1 }
            }
        }
    }

    func record(error: Error, category: String, message: String) {
        record(
            category: category,
            message: message,
            metadata: [
                "error": error.localizedDescription,
                "error_type": String(reflecting: type(of: error))
            ]
        )
    }

    func exportData() -> Data {
        let storedData = queue.sync {
            pruneLog()
            return (try? Data(contentsOf: Self.logURL)) ?? Data()
        }

        let contextEvent = DiagnosticEvent(
            timestamp: Date(),
            level: "info",
            category: "export.context",
            message: "BodyMode diagnostic export",
            metadata: [
                "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "build_number": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                "os_version": ProcessInfo.processInfo.operatingSystemVersionString
            ]
        )
        var output = (try? JSONEncoder.diagnostic.encode(contextEvent)) ?? Data()
        output.append(0x0A)
        output.append(storedData)
        return output
    }

    func makeShareFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bodymode-diagnostics-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("jsonl")
        try exportData().write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        return url
    }

    func deleteData() {
        queue.sync {
            try? FileManager.default.removeItem(at: Self.logURL)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            appendMetricKitPayload(payload.jsonRepresentation(), payloadType: "diagnostic")
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            appendMetricKitPayload(payload.jsonRepresentation(), payloadType: "metric")
        }
    }

    private func appendMetricKitPayload(_ data: Data, payloadType: String) {
        let rawPayload = String(data: data, encoding: .utf8) ?? "{}"
        let payloadString = String(rawPayload.prefix(200_000))
        record(
            level: "info",
            category: "metrickit.\(payloadType)",
            message: "MetricKit payload received",
            metadata: ["payload": payloadString]
        )
    }

    private func appendLine(_ data: Data) {
        queue.async {
            do {
                try FileManager.default.createDirectory(
                    at: Self.logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                )
                try self.excludeDirectoryFromBackup()
                if !FileManager.default.fileExists(atPath: Self.logURL.path) {
                    FileManager.default.createFile(
                        atPath: Self.logURL.path,
                        contents: nil,
                        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                    )
                }
                let handle = try FileHandle(forWritingTo: Self.logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data([0x0A]))
                try handle.close()
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: Self.logURL.path
                )
                self.pruneLog()
            } catch {
                self.logger.error("Failed to persist diagnostics: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func pruneLog() {
        guard let rawData = try? Data(contentsOf: Self.logURL), !rawData.isEmpty else { return }

        let cutoff = Date().addingTimeInterval(-Self.retentionInterval)
        var retained = rawData
            .split(separator: 0x0A)
            .compactMap { bytes -> (timestamp: Date, data: Data)? in
                let line = Data(bytes)
                guard let event = try? JSONDecoder.diagnostic.decode(DiagnosticEvent.self, from: line),
                      event.timestamp >= cutoff else {
                    return nil
                }
                return (event.timestamp, line)
            }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(Self.maximumEventCount)
            .map(\.data)

        var totalBytes = retained.reduce(0) { $0 + $1.count + 1 }
        while retained.count > 1, totalBytes > Self.maximumLogBytes {
            totalBytes -= retained.removeFirst().count + 1
        }

        var output = Data()
        for line in retained {
            output.append(line)
            output.append(0x0A)
        }

        do {
            try output.write(
                to: Self.logURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            logger.error("Failed to prune diagnostics: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func excludeDirectoryFromBackup() throws {
        var directoryURL = Self.logURL.deletingLastPathComponent()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directoryURL.setResourceValues(values)
    }

    private static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("GymTraining", isDirectory: true)
            .appendingPathComponent("diagnostics.jsonl")
    }
}

private struct DiagnosticEvent: Codable {
    let timestamp: Date
    let level: String
    let category: String
    let message: String
    let metadata: [String: String]
}

private extension JSONEncoder {
    static var diagnostic: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var diagnostic: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct DiagnosticLogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data = Data()

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct DiagnosticSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityShareView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum UsageEventName: String, Codable {
    case analyticsEnabled = "analytics_enabled"
    case appOpened = "app_opened"
    case tabSelected = "tab_selected"
    case planSaved = "plan_saved"
    case workoutCompleted = "workout_completed"
    case bodyMetricSaved = "body_metric_saved"
    case mealSaved = "meal_saved"
    case bodyPhotoSaved = "body_photo_saved"
    case legalAccepted = "legal_accepted"
    case tutorialViewed = "tutorial_viewed"
    case dailyRecommendationGenerated = "daily_recommendation_generated"
    case dailyRecommendationChanged = "daily_recommendation_changed"
    case dailyActionCompleted = "daily_action_completed"
    case notificationOpened = "notification_opened"
    case notificationDisabled = "notification_disabled"
    case coachRecommendationAccepted = "coach_recommendation_accepted"
    case coachSelectionChanged = "coach_selection_changed"
    case coachResponseHelpful = "coach_response_helpful"
    case coachResponseNeedsImprovement = "coach_response_needs_improvement"
}

enum CoachResponseRating: String, Codable {
    case helpful
    case needsImprovement = "needs_improvement"
}

private struct UsageEvent: Codable {
    let timestamp: Date
    let name: UsageEventName
    let dimension: String?
    let appVersion: String
}

/// Stores coarse feature-use events on this device. It never sends data over the network.
final class UsageAnalytics: @unchecked Sendable {
    static let shared = UsageAnalytics()

    private static let enabledKey = "bodymode.usageAnalytics.enabled"
    private static let eventsKey = "bodymode.usageAnalytics.events"
    private static let coachResponseRatingsKey = "bodymode.usageAnalytics.coachResponseRatings"

    private let queue = DispatchQueue(label: "com.yukitoshim.gymtrainingapp.usage-analytics")
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let maximumEventCount = 1_000
    private let maximumCoachResponseRatingCount = 500
    private let retentionInterval: TimeInterval = 90 * 24 * 60 * 60
    private var cachedEvents: [UsageEvent]
    private var cachedCoachResponseRatings: [String: String]
    private var persistenceGeneration: UInt = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cachedEvents = Self.decodeEvents(defaults.data(forKey: Self.eventsKey))
        cachedCoachResponseRatings = defaults.dictionary(forKey: Self.coachResponseRatingsKey) as? [String: String] ?? [:]
    }

    var isCollectionEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    func setCollectionEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.enabledKey)
        if isEnabled {
            record(.analyticsEnabled)
        }
    }

    func record(_ name: UsageEventName, dimension: String? = nil) {
        let generation = lock.withLock { persistenceGeneration }
        queue.async {
            guard self.defaults.bool(forKey: Self.enabledKey) else { return }
            guard let events = self.appendEvent(
                name,
                dimension: dimension,
                generation: generation
            ) else { return }
            self.saveEvents(events)
        }
    }

    func coachResponseRating(for messageID: UUID) -> CoachResponseRating? {
        lock.withLock {
            guard let rawValue = cachedCoachResponseRatings[messageID.uuidString] else { return nil }
            return CoachResponseRating(rawValue: rawValue)
        }
    }

    func coachResponseRatings(for messageIDs: [UUID]) -> [UUID: CoachResponseRating] {
        lock.withLock {
            Dictionary(uniqueKeysWithValues: messageIDs.compactMap { messageID in
                guard let rawValue = cachedCoachResponseRatings[messageID.uuidString],
                      let rating = CoachResponseRating(rawValue: rawValue) else { return nil }
                return (messageID, rating)
            })
        }
    }

    func recordCoachResponseRating(
        messageID: UUID,
        rating: CoachResponseRating,
        coachType: String
    ) {
        let generation: UInt? = lock.withLock {
            guard cachedCoachResponseRatings[messageID.uuidString] != rating.rawValue else {
                return nil
            }
            cachedCoachResponseRatings[messageID.uuidString] = rating.rawValue
            if cachedCoachResponseRatings.count > maximumCoachResponseRatingCount {
                let retainedKeys = cachedCoachResponseRatings.keys.sorted().suffix(maximumCoachResponseRatingCount)
                cachedCoachResponseRatings = Dictionary(uniqueKeysWithValues: retainedKeys.compactMap { key in
                    cachedCoachResponseRatings[key].map { (key, $0) }
                })
            }
            return persistenceGeneration
        }
        guard let generation else { return }
        let shouldRecordEvent = isCollectionEnabled
        if shouldRecordEvent {
            _ = appendEvent(
                rating == .helpful ? .coachResponseHelpful : .coachResponseNeedsImprovement,
                dimension: coachType,
                generation: generation
            )
        }
        queue.async {
            let current: ([String: String], [UsageEvent])? = self.lock.withLock {
                guard self.persistenceGeneration == generation else { return nil }
                return (self.cachedCoachResponseRatings, self.cachedEvents)
            }
            guard let current else { return }
            self.defaults.set(current.0, forKey: Self.coachResponseRatingsKey)
            if shouldRecordEvent {
                self.saveEvents(current.1)
            }
        }
    }

    func exportData() -> Data {
        lock.withLock {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return (try? encoder.encode(cachedEvents)) ?? Data("[]".utf8)
        }
    }

    func deleteData() {
        lock.withLock {
            persistenceGeneration &+= 1
            cachedEvents = []
            cachedCoachResponseRatings = [:]
        }
        queue.async {
            self.defaults.removeObject(forKey: Self.eventsKey)
            self.defaults.removeObject(forKey: Self.coachResponseRatingsKey)
        }
    }

    func reset() {
        defaults.removeObject(forKey: Self.enabledKey)
        deleteData()
    }

    private static func decodeEvents(_ data: Data?) -> [UsageEvent] {
        guard let data else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageEvent].self, from: data)) ?? []
    }

    private func appendEvent(
        _ name: UsageEventName,
        dimension: String?,
        generation: UInt
    ) -> [UsageEvent]? {
        let now = Date()
        return lock.withLock {
            guard persistenceGeneration == generation else { return nil }
            cachedEvents.append(
                UsageEvent(
                    timestamp: now,
                    name: name,
                    dimension: dimension.map { String($0.prefix(40)) },
                    appVersion: LegalConfiguration.appVersion
                )
            )
            cachedEvents = cachedEvents
                .filter { now.timeIntervalSince($0.timestamp) <= retentionInterval }
                .suffix(maximumEventCount)
                .map { $0 }
            return cachedEvents
        }
    }

    private func saveEvents(_ events: [UsageEvent]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events) else { return }
        defaults.set(data, forKey: Self.eventsKey)
    }

}
