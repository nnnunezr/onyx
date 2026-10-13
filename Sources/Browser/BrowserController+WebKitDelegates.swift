import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView == activeWebView {
            progressBar.isHidden = false
            progressBar.alphaValue = 1.0
            if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Stop") {
                reloadButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            }
            let targetURL = webView.url ?? activeTab.url
            if isSearchURL(targetURL) {
                searchThinkingOrb.stopAnimation()
                searchThinkingOrb.isHidden = true
                searchFaviconView.image = nil
                searchFaviconView.isHidden = true
            } else {
                searchFaviconView.isHidden = true
                searchThinkingOrb.startAnimation(mode: .orbits)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let matchingTab = tabs.first(where: { $0.webView == webView }),
           let host = (webView.url ?? matchingTab.url).host, !(webView.url ?? matchingTab.url).isFileURL {
            if let cached = FaviconManager.shared.cachedFavicon(for: host) {
                updateTabFavicon(for: matchingTab, favicon: cached)
            }
        }
        // Search and research pages are themed only by the document-start/end user scripts
        // (installSearchThemeScripts). The evaluateJavaScript re-injections from here and
        // didFinish (up to 7 per search) are gone.
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let matchingTab = tabs.first(where: { $0.webView == webView }) {
            fetchFavicon(for: matchingTab)
        }
        if let url = webView.url, !url.isFileURL {
            addBrowsingHistory(title: webView.title ?? "", url: url)
        }
        if isStartPageURL(webView.url) {
            webView.evaluateJavaScript(startPageProfileScript(), completionHandler: nil)
            let engineJS = "if (window.setSearchEngine) window.setSearchEngine(\(JS.string(SearchEngines.current)));"
            webView.evaluateJavaScript(engineJS, completionHandler: nil)
            webView.evaluateJavaScript(startPageNewsScript(), completionHandler: nil)
        }
        scheduleSessionSave()
        
        if let url = webView.url, isSettingsURL(url) {
            sendSettingsPayload(to: webView)
        }
        
        if isResearchURL(webView.url) {
            if webView == activeWebView {
                // Loaded: stop the orb (it used to start here and spin at 60 Hz indefinitely).
                searchThinkingOrb.stopAnimation()
                searchFaviconView.isHidden = false
                updateSearchFavicon(for: webView.url ?? activeTab.url)
            }
        } else if isSearchURL(webView.url) {
            // Auto-detect and disable bot verification for a seamless private search experience
            webView.evaluateJavaScript("document.querySelector('.anomaly-modal, [class*=\"anomaly-modal\"], #anomaly-detected') !== null") { [weak self] (res, _) in
                if (res as? Bool) == true {
                    self?.handleBotChallenge(in: webView)
                }
            }
            if webView == activeWebView {
                searchThinkingOrb.stopAnimation()
                searchThinkingOrb.isHidden = true
                searchFaviconView.image = nil
                searchFaviconView.isHidden = true
            }
        } else {
            if webView == activeWebView {
                searchThinkingOrb.stopAnimation()
                searchFaviconView.isHidden = false
                updateSearchFavicon(for: webView.url ?? activeTab.url)
            }
        }
        
        if webView == activeWebView {
            if let img = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") {
                reloadButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            }
            backButton.isEnabled = webView.canGoBack
            forwardButton.isEnabled = webView.canGoForward
            
            if isResearchURL(webView.url) {
                let q = extractResearchQuery(from: webView.url)
                let cleanTitle = q.isEmpty ? "✦ Onyx Research" : "✦ \(q)"
                activeTab.title = cleanTitle
                self.window?.title = cleanTitle
                renderTabs()
                updateSearchField(url: webView.url ?? activeTab.url)
            } else if isSearchURL(webView.url) {
                let q = extractSearchQuery(from: webView.url)
                let cleanTitle = q.isEmpty ? "✦ Onyx Search" : "✦ \(q) — Search"
                activeTab.title = cleanTitle
                self.window?.title = cleanTitle
                renderTabs()
                updateSearchField(url: webView.url ?? activeTab.url)
            }
        }
        
        if webView == activeWebView {
            updatePasswordsBadge(for: webView.url)
        }
        injectPasswordSaveListener(into: webView)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsErr = error as NSError
        let isCancellation = (nsErr.domain == "WebKitErrorDomain" && (nsErr.code == 102 || nsErr.code == 101)) ||
                             (nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled)
        // Stop, a download hand-off (102) or a superseded load still has to reset the loading UI;
        // only skip it when a newer navigation is already running in this view.
        if isCancellation && webView.isLoading { return }
        if webView == activeWebView {
            progressBar.isHidden = true
            searchThinkingOrb.stopAnimation()
            searchFaviconView.isHidden = false
            updateSearchFavicon(for: webView.url ?? activeTab.url)
            if let img = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") {
                reloadButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsErr = error as NSError
        let isCancellation = (nsErr.domain == "WebKitErrorDomain" && (nsErr.code == 102 || nsErr.code == 101)) ||
                             (nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled)
        // Stop, a download hand-off (102) or a superseded load still has to reset the loading UI;
        // only skip it when a newer navigation is already running in this view.
        if isCancellation && webView.isLoading { return }
        if webView == activeWebView {
            progressBar.isHidden = true
            searchThinkingOrb.stopAnimation()
            searchFaviconView.isHidden = false
            updateSearchFavicon(for: webView.url ?? activeTab.url)
            if let img = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") {
                reloadButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            }
        }
    }
    
    // MARK: - WKNavigationDelegate Policy Decisions & Download Handover
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        // ⌘-click on a link: open it in a background tab (no opener relationship needed)
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command),
           let url = navigationAction.request.url {
            createNewTab(url: url, switchTo: navigationAction.modifierFlags.contains(.shift))
            decisionHandler(.cancel, preferences)
            return
        }
        
        // target="_blank" and window.open() are handled by webView(_:createWebViewWith:...) so
        // popups keep their window.opener link (required by OAuth / "Sign in with..." flows).
        
        // <a download> and Option-click: the page asked for a file, so always save it, whatever
        // the navigation type. Script-driven downloads (`a.click()` on a blob: or data: link, as
        // Drive, Docs exports and most "Export CSV" buttons do) arrive as .other; an early
        // `.other -> allow` return used to load them as a page. The old extension allowlist also
        // sent every .pdf, .png, .csv or extensionless link inline.
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }
        
        decisionHandler(.allow, preferences)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let http = navigationResponse.response as? HTTPURLResponse
        let decision = DownloadPolicy.decideResponse(
            statusCode: http?.statusCode,
            contentDisposition: http?.value(forHTTPHeaderField: "Content-Disposition"),
            isMainFrame: navigationResponse.isForMainFrame,
            canShowMIMEType: navigationResponse.canShowMIMEType
        )
        switch decision {
        case .allow: decisionHandler(.allow)
        case .download: decisionHandler(.download)
        case .cancel: decisionHandler(.cancel)
        }
    }
    
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        registerDownload(download: download, sourceURL: navigationAction.request.url)
    }
    
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        registerDownload(download: download, sourceURL: navigationResponse.response.url)
    }

    /// Right-click > Download Linked File / Download Image / Download Video. WebKit creates these
    /// downloads itself and hands them only to this private WKUIDelegate hook; with no one claiming
    /// them they get no delegate and nothing is saved. If a future WebKit stops calling it, the
    /// menu items just go back to doing nothing.
    @objc(_webView:contextMenuDidCreateDownload:)
    func webView(_ webView: WKWebView, contextMenuDidCreateDownload download: WKDownload) {
        download.delegate = self
        registerDownload(download: download, sourceURL: download.originalRequest?.url)
    }
    
    // MARK: - WebContent Process Crash Recovery
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let allTabs = tabs + profileTabs.values.flatMap { $0 }
        guard let tab = allTabs.first(where: { $0.webView == webView }) else { return }
        
        let now = Date()
        tab.recentCrashes = tab.recentCrashes.filter { now.timeIntervalSince($0) < 60 } + [now]
        let isCrashLoop = tab.recentCrashes.count >= 2
        OnyxLog.crash.error("WebContent process terminated for \(tab.url.host ?? "?", privacy: .private) (active: \(webView == self.activeWebView, privacy: .public), crash loop: \(isCrashLoop, privacy: .public))")
        
        guard webView == activeWebView else {
            // Background tab: reload lazily when it is next shown.
            tab.needsReload = true
            return
        }
        
        progressBar.isHidden = true
        searchThinkingOrb.stopAnimation()
        searchFaviconView.isHidden = false
        updateSearchFavicon(for: webView.url ?? tab.url)
        if let img = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") {
            reloadButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        }
        
        if isCrashLoop {
            // Don't loop: let the user decide when to try again. Move focus off the dead view:
            // a WKWebView without a process swallows key equivalents, so ⌘R would do nothing.
            tab.needsReload = false
            window?.makeFirstResponder(searchField)
            showVaultToastHUD(icon: "exclamationmark.triangle.fill", title: "PAGE CRASHED AGAIN", message: "Press ⌘R to try reloading \(tab.url.host ?? "this page")")
        } else {
            reloadAfterCrash(tab)
            showVaultToastHUD(icon: "arrow.clockwise", title: "PAGE RELOADED", message: "\(tab.url.host ?? "This page") stopped responding and was reloaded")
        }
    }
    
    func reloadAfterCrash(_ tab: BrowserTab) {
        tab.needsReload = false
        // reload() relaunches the process and reloads the current back/forward item (keeping history
        // and scroll) even though webView.url is nil after a crash. It returns nil only when there
        // is no current item, in which case start a fresh load.
        if tab.webView.reload() == nil {
            loadTabURL(tab: tab, url: tab.url)
        }
    }
    
    // MARK: - WKUIDelegate (New Windows / Popups)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // WebKit requires the returned view to use exactly this configuration (same process pool,
        // same data store as the opener) and loads the request into it itself.
        let url = navigationAction.request.url ?? URL(string: "about:blank")!
        let tab = BrowserTab(url: url, configuration: configuration)
        attachTab(tab)
        selectTab(at: tabs.count - 1)
        return tab.webView
    }
    
    func webViewDidClose(_ webView: WKWebView) {
        // Popups (e.g. OAuth windows) call window.close() when finished.
        if let tab = tabs.first(where: { $0.webView == webView }) {
            closeTab(tab: tab)
        }
    }
    
    // MARK: - WKUIDelegate (File Uploads & Dialogs)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canChooseDirectories = parameters.allowsDirectories
        openPanel.canChooseFiles = true
        openPanel.resolvesAliases = true
        openPanel.prompt = "Upload"
        let host = frame.request.url?.host ?? "Web Page"
        openPanel.message = "Select file(s) to upload to \(host)"
        
        if let window = self.window {
            openPanel.beginSheetModal(for: window) { response in
                if response == .OK {
                    completionHandler(openPanel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        } else {
            openPanel.begin { response in
                if response == .OK {
                    completionHandler(openPanel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        let host = frame.request.url?.host ?? "Web Page"
        alert.messageText = "\(host)"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let window = self.window {
            trackJSDialog(alert, from: webView)
            alert.beginSheetModal(for: window) { [weak self] _ in
                self?.activeJSDialogSheet = nil
                completionHandler()
            }
        } else {
            alert.runModal()
            completionHandler()
        }
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        let host = frame.request.url?.host ?? "Web Page"
        alert.messageText = "\(host)"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if let window = self.window {
            trackJSDialog(alert, from: webView)
            alert.beginSheetModal(for: window) { [weak self] response in
                self?.activeJSDialogSheet = nil
                completionHandler(response == .alertFirstButtonReturn)
            }
        } else {
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn)
        }
    }
    
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        let host = frame.request.url?.host ?? "Web Page"
        alert.messageText = "\(host)"
        alert.informativeText = prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        inputField.stringValue = defaultText ?? ""
        alert.accessoryView = inputField
        
        if let window = self.window {
            trackJSDialog(alert, from: webView)
            alert.beginSheetModal(for: window) { [weak self] response in
                self?.activeJSDialogSheet = nil
                if response == .alertFirstButtonReturn {
                    completionHandler(inputField.stringValue)
                } else {
                    completionHandler(nil)
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                completionHandler(inputField.stringValue)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    private func trackJSDialog(_ alert: NSAlert, from webView: WKWebView) {
        activeJSDialogSheet = alert.window
        activeJSDialogWebView = webView
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        searchField.onFocusChanged?(false)
    }
}
