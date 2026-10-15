import Cocoa
import WebKit

// MARK: - External app requests (zoommtg:, slack:, mailto:, spotify: ...)
extension BrowserController {
    /// True when the navigation targets a scheme WebKit cannot load. It has then been handled
    /// (prompted, opened or dropped) and the caller must cancel it; WebKit would otherwise fail
    /// the load and show nothing.
    func handleExternalAppRequest(_ navigationAction: WKNavigationAction, in webView: WKWebView) -> Bool {
        guard let url = navigationAction.request.url else { return false }
        let type = navigationAction.navigationType
        let decision = ExternalAppPolicy.decide(
            scheme: url.scheme,
            handledByWebKit: WKWebView.handlesURLScheme(url.scheme ?? ""),
            isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
            userInitiated: type == .linkActivated || type == .formSubmitted
        )
        switch decision {
        case .notExternal:
            return false
        case .block:
            OnyxLog.security.notice("external app request dropped: scheme=\(url.scheme ?? "?", privacy: .public)")
            return true
        case .prompt:
            promptToOpenExternalApp(url, from: webView)
            return true
        }
    }

    private func promptToOpenExternalApp(_ url: URL, from webView: WKWebView) {
        let scheme = url.scheme ?? ""
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            showVaultToastHUD(icon: "questionmark.app", title: "NO APP FOUND", message: "Nothing on this Mac opens \(scheme): links")
            return
        }
        // One question at a time: a page that fires the same launch in a loop must not stack sheets.
        guard !externalAppPromptActive else { return }
        externalAppPromptActive = true

        let appName = appURL.deletingPathExtension().lastPathComponent
        let alert = NSAlert()
        alert.messageText = "Open “\(appName)”?"
        alert.informativeText = "\(webView.url?.host ?? "This page") wants to open this link in \(appName)."
        alert.alertStyle = .informational
        alert.icon = NSWorkspace.shared.icon(forFile: appURL.path)
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.externalAppPromptActive = false
            self?.activeJSDialogSheet = nil
            guard response == .alertFirstButtonReturn else { return }
            OnyxLog.security.notice("external app opened: scheme=\(scheme, privacy: .public) app=\(appName, privacy: .public)")
            NSWorkspace.shared.open(url)
        }
        if let window = self.window {
            // Same hook as a page's alert(): Cmd+W cancels the sheet and closes the tab.
            trackJSDialog(alert, from: webView)
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}
