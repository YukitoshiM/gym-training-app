import Foundation
import OSLog

final class WatchDiagnostics: @unchecked Sendable {
    static let shared = WatchDiagnostics()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yukitoshim.gymtrainingapp.watchkitapp",
        category: "Diagnostics"
    )
    private let queue = DispatchQueue(label: "com.yukitoshim.gymtrainingapp.watch-diagnostics")
    private let defaults = UserDefaults.standard
    private let storageKey = "bodymode.watch.diagnostics.events"
    private let maximumEventCount = 500
    private let retentionInterval: TimeInterval = 14 * 24 * 60 * 60

    private init() {
        queue.sync {
            save(pruned(load()))
        }
    }

    func record(
        level: String = "info",
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        if level == "error" {
            logger.error("\(category, privacy: .public): \(message, privacy: .public)")
        } else {
            logger.info("\(category, privacy: .public): \(message, privacy: .public)")
        }

        let event = WatchDiagnosticEvent(
            level: level,
            category: String(category.prefix(80)),
            message: String(message.prefix(500)),
            metadata: metadata.reduce(into: [:]) { result, entry in
                result[String(entry.key.prefix(80))] = String(entry.value.prefix(500))
            }
        )
        queue.sync {
            var events = load()
            events.append(event)
            save(pruned(events))
        }
    }

    func pendingBatch(maximum: Int = 100) -> [WatchDiagnosticEvent] {
        queue.sync {
            Array(pruned(load()).prefix(max(1, maximum)))
        }
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        queue.sync {
            save(load().filter { !ids.contains($0.id) })
        }
    }

    func restore(_ events: [WatchDiagnosticEvent]) {
        guard !events.isEmpty else { return }
        queue.sync {
            let existing = load()
            let existingIDs = Set(existing.map(\.id))
            save(pruned(events.filter { !existingIDs.contains($0.id) } + existing))
        }
    }

    private func load() -> [WatchDiagnosticEvent] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WatchDiagnosticEvent].self, from: data)) ?? []
    }

    private func save(_ events: [WatchDiagnosticEvent]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func pruned(_ events: [WatchDiagnosticEvent]) -> [WatchDiagnosticEvent] {
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        return events
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(maximumEventCount)
            .map { $0 }
    }
}
