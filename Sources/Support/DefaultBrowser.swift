import Cocoa
import os

// MARK: - Default browser
/// Asks macOS to route http and https links to Onyx. The system shows its own confirmation
/// dialog, so nothing changes until the user approves it there.
enum DefaultBrowser {
    private static let schemes = ["http", "https"]

    /// True when macOS currently sends both http and https links to this app.
    static var isDefault: Bool {
        schemes.allSatisfy { scheme in
            guard let probe = URL(string: "\(scheme)://example.com"),
                  let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
            return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
                || Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
    }

    /// Requests the switch for each scheme. `completion` runs on the main queue with the final state.
    static func request(completion: @escaping (_ isDefault: Bool, _ error: Error?) -> Void) {
        let appURL = Bundle.main.bundleURL
        let group = DispatchGroup()
        var firstError: Error?
        for scheme in schemes {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
                if let error = error {
                    OnyxLog.security.error("default browser request for \(scheme, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    DispatchQueue.main.async { if firstError == nil { firstError = error } }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(isDefault, firstError)
        }
    }
}
