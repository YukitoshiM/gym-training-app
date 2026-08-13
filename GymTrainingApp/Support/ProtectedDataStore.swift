import Foundation

/// Persists private app records with iOS file protection and without device backup.
final class ProtectedDataStore: @unchecked Sendable {
    static let shared = ProtectedDataStore()

    private let fileManager: FileManager
    private let directoryURL: URL
    private let queue = DispatchQueue(label: "com.yukitoshim.gymtrainingapp.protected-data")

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directoryURL = baseURL
            .appendingPathComponent("BodyMode", isDirectory: true)
            .appendingPathComponent("PrivateRecords", isDirectory: true)
    }

    func data(forKey key: String) -> Data? {
        queue.sync {
            let url = fileURL(forKey: key)
            if let data = try? Data(contentsOf: url) {
                return data
            }

            guard let legacyData = UserDefaults.standard.data(forKey: key) else {
                return nil
            }

            do {
                try write(legacyData, to: url)
                UserDefaults.standard.removeObject(forKey: key)
            } catch {
                AppDiagnostics.shared.record(
                    error: error,
                    category: "storage.migration",
                    message: "Failed to migrate protected data for \(key)"
                )
            }
            return legacyData
        }
    }

    func set(_ data: Data, forKey key: String) throws {
        try queue.sync {
            try write(data, to: fileURL(forKey: key))
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func removeValue(forKey key: String) {
        queue.sync {
            try? fileManager.removeItem(at: fileURL(forKey: key))
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func removeAll(keys: [String]) {
        queue.sync {
            for key in keys {
                try? fileManager.removeItem(at: fileURL(forKey: key))
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        try prepareDirectory()
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = directoryURL
        try mutableURL.setResourceValues(values)
    }

    private func fileURL(forKey key: String) -> URL {
        let safeName = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return directoryURL.appendingPathComponent("\(safeName).json", isDirectory: false)
    }
}
