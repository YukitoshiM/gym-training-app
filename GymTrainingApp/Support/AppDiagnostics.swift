import Foundation
import MetricKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

final class AppDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = AppDiagnostics()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yukitoshim.gymtrainingapp",
        category: "Diagnostics"
    )
    private let queue = DispatchQueue(label: "com.yukitoshim.gymtrainingapp.diagnostics")
    private var isStarted = false

    private override init() {
        super.init()
    }

    func start() {
        queue.sync {
            guard !isStarted else { return }
            isStarted = true
            MXMetricManager.shared.add(self)
        }
        record(level: "info", category: "lifecycle", message: "App diagnostics started")
    }

    func record(
        level: String = "error",
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        logger.log(level: level == "error" ? .error : .info, "\(category, privacy: .public): \(message, privacy: .public)")

        let event = DiagnosticEvent(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )
        guard let data = try? JSONEncoder.diagnostic.encode(event) else { return }
        appendLine(data)
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
        queue.sync {
            (try? Data(contentsOf: Self.logURL)) ?? Data()
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
        let payloadString = String(data: data, encoding: .utf8) ?? "{}"
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
                    withIntermediateDirectories: true
                )
                if !FileManager.default.fileExists(atPath: Self.logURL.path) {
                    FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: Self.logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data([0x0A]))
                try handle.close()
            } catch {
                self.logger.error("Failed to persist diagnostics: \(error.localizedDescription, privacy: .public)")
            }
        }
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
