import Foundation

// MARK: - External app policy
/// Foundation-only so it can be unit-tested outside the app (tests/run.sh). A page that navigates
/// to a scheme WebKit cannot load (`zoommtg:`, `slack:`, `mailto:`, `spotify:`) is asking to open
/// another app. Onyx asks the user first, as Safari and Chrome do, because the link's target app
/// and arguments are chosen by the page.
enum ExternalAppPolicy {
    enum Decision: Equatable {
        /// WebKit loads this scheme itself; nothing to do.
        case notExternal
        /// Ask the user, then hand the URL to the app that owns the scheme.
        case prompt
        /// Drop it without asking (script-driven launch the user did not trigger, or a scheme that
        /// runs attacker-supplied code).
        case block
    }

    /// Schemes whose handler executes the URL's payload as a script.
    static let blockedSchemes: Set<String> = ["applescript", "vbscript"]

    /// `handledByWebKit` is `WKWebView.handlesURLScheme(_:)`, passed in so this stays testable.
    /// `userInitiated` is a link click or form submit; a main-frame navigation counts as the
    /// user's own (`location = "zoommtg://..."` after a click is how most sites do it), but a
    /// hidden iframe or redirect inside one is the drive-by launch to refuse.
    static func decide(scheme: String?, handledByWebKit: Bool, isMainFrame: Bool, userInitiated: Bool) -> Decision {
        guard let scheme = scheme?.lowercased(), !scheme.isEmpty, !handledByWebKit else { return .notExternal }
        if blockedSchemes.contains(scheme) { return .block }
        return isMainFrame || userInitiated ? .prompt : .block
    }
}
