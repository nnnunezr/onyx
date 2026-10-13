import Foundation

// MARK: - User agent
/// Onyx claims to be the Safari that ships on this Mac. A hard-coded "Version/18.3" on the
/// macOS 27 engine made Google (and other UA-sniffing sites) serve layouts and polyfills for a
/// browser years older than the one actually rendering them.
enum UserAgent {
    static let safariVersion: String = {
        let plist = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        if let info = NSDictionary(contentsOf: plist),
           let version = info["CFBundleShortVersionString"] as? String, !version.isEmpty {
            return version
        }
        return "27.0"
    }()

    /// Appended by WebKit to its own platform prefix (set as applicationNameForUserAgent).
    static var applicationName: String { "Version/\(safariVersion) Safari/605.1.15" }

    /// Full string, for requests Onyx makes outside a web view (favicons).
    static var full: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) \(applicationName)"
    }
}
