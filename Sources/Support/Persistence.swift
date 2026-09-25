import Foundation
import os

// MARK: - Logging
/// Unified-log channels. Read with:
///   log stream --predicate 'subsystem == "com.company.onyx"'
/// Only persistence fallbacks, vault failures, crash recovery and blocked bridge calls log here.
enum OnyxLog {
    static let persistence = Logger(subsystem: "com.company.onyx", category: "persistence")
    static let vault = Logger(subsystem: "com.company.onyx", category: "vault")
    static let crash = Logger(subsystem: "com.company.onyx", category: "crash")
    static let security = Logger(subsystem: "com.company.onyx", category: "security")
    static let webkit = Logger(subsystem: "com.company.onyx", category: "webkit")
}

// MARK: - Safe loading of stored lists
/// Loads Codable lists from UserDefaults without ever silently discarding what is stored.
/// If the stored bytes do not decode cleanly, they are first copied to
/// ~/Library/Application Support/Onyx/recovery/, then whatever items still decode are returned.
enum Persistence {
    struct LoadResult<T> {
        var items: [T]
        /// Nil when the stored value decoded cleanly (or nothing was stored).
        var problem: Problem?
    }

    struct Problem {
        let key: String
        let recoveredCount: Int
        let backupURL: URL?

        /// Short text for a toast (the HUD is about 440 pt wide).
        var userMessage: String {
            let label = Persistence.label(for: key)
            guard backupURL != nil else { return "\(label.prefix(1).uppercased() + label.dropFirst()) unreadable; backup failed" }
            return recoveredCount > 0
                ? "Kept \(recoveredCount) \(label); backup in Onyx/recovery"
                : "\(label.prefix(1).uppercased() + label.dropFirst()) unreadable; backup in Onyx/recovery"
        }
    }

    static var recoveryDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Onyx/recovery", isDirectory: true)
    }

    static func loadList<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults = .standard) -> LoadResult<T> {
        guard let data = defaults.data(forKey: key) else {
            // Something other than Data under this key is also a problem worth preserving.
            if let other = defaults.object(forKey: key) {
                let backup = writeBackup(Data(String(describing: other).utf8), key: key)
                OnyxLog.persistence.error("\(key, privacy: .public): stored value is not data; backed up")
                return LoadResult(items: [], problem: Problem(key: key, recoveredCount: 0, backupURL: backup))
            }
            return LoadResult(items: [], problem: nil)
        }
        if let items = try? JSONDecoder().decode([T].self, from: data) {
            return LoadResult(items: items, problem: nil)
        }
        let backup = writeBackup(data, key: key)
        let salvaged = (try? JSONDecoder().decode([Salvage<T>].self, from: data))?.compactMap { $0.value } ?? []
        OnyxLog.persistence.error("\(key, privacy: .public): decode failed, salvaged \(salvaged.count) item(s), backup \(backup?.path ?? "FAILED", privacy: .public)")
        return LoadResult(items: salvaged, problem: Problem(key: key, recoveredCount: salvaged.count, backupURL: backup))
    }

    /// Copies raw stored bytes to the recovery folder before anything can overwrite them.
    @discardableResult
    static func writeBackup(_ data: Data, key: String) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = recoveryDirectory.appendingPathComponent("\(key)-\(formatter.string(from: Date())).json")
        do {
            try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            OnyxLog.persistence.fault("\(key, privacy: .public): could not write recovery backup: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func label(for key: String) -> String {
        switch key {
        case "OnyxBookmarks": return "bookmarks"
        case "OnyxBrowsingHistory": return "history"
        case "OnyxProfiles": return "workspaces"
        case "OnyxSessionTabs": return "session tabs"
        default: return key
        }
    }

    /// Decodes one array element, turning a bad element into nil instead of failing the whole array.
    private struct Salvage<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }
}
