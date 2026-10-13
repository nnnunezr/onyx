import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Dedicated Settings Tab & Native Bridge
    @objc func openSettingsTab() {
        if let idx = tabs.firstIndex(where: { isSettingsURL($0.url) }) {
            selectTab(at: idx)
            return
        }
        if activeTab.url.isFileURL && activeTab.url.path.contains("startpage.html") && tabs.count == 1 {
            loadURL(settingsPageURL)
        } else {
            createNewTab(url: settingsPageURL, switchTo: true)
        }
    }
    
    @objc func menuOpenSettings() {
        openSettingsTab()
    }
    
    func sendSettingsPayload(to webView: WKWebView) {
        let defaults = UserDefaults.standard
        let startup = defaults.string(forKey: "OnyxStartupBehavior") ?? "startpage"
        let showBookmarks = defaults.object(forKey: "OnyxShowBookmarksBar") as? Bool ?? true
        let newsEnabled = defaults.object(forKey: "OnyxNewsEnabled") as? Bool ?? true
        let offerSavePasswords = defaults.object(forKey: "OnyxOfferSavePasswords") as? Bool ?? true
        let downloadsPath = (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path) ?? "~/Downloads"
        
        let profList: [[String: Any]] = profiles.map { p in
            let tCount = (p.id == activeProfile.id) ? tabs.count : (profileTabs[p.id]?.count ?? 0)
            return [
                "id": p.id,
                "name": p.name,
                "colorHex": p.colorHex,
                "tabCount": tCount,
                "isActive": (p.id == activeProfile.id),
                "isDefault": p.isDefault || p.id == "personal"
            ]
        }
        
        let payload: [String: Any] = [
            "searchEngine": SearchEngines.current,
            "startup": startup,
            "showBookmarksBar": showBookmarks,
            "adBlockEnabled": isAdBlockEnabled,
            "newsEnabled": newsEnabled,
            "offerSavePasswords": offerSavePasswords,
            "downloadsPath": downloadsPath,
            "profiles": profList,
            "activeProfileId": activeProfile.id,
            "ramUsage": String(format: "%.1f MB", getResidentMemoryMB())
        ]
        
        guard let json = JS.literal(payload) else { return }
        let js = "if (window.renderSettings) window.renderSettings(\(json));"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
    
    func getResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        }
        return 38.4
    }
    
    func handleSettingsMessage(_ dict: [String: Any], from webView: WKWebView?) {
        guard let action = dict["action"] as? String else { return }
        let defaults = UserDefaults.standard
        
        switch action {
        case "getSettings":
            break
            
        case "setSearchEngine":
            if let engine = dict["engine"] as? String {
                setLiveSearchEngine(engine)
            }
            
        case "setStartup":
            if let mode = dict["mode"] as? String, ["startpage", "restore", "blank"].contains(mode) {
                defaults.set(mode, forKey: "OnyxStartupBehavior")
                saveSession()
            }
            
        case "setShowBookmarksBar":
            if let enabled = dict["enabled"] as? Bool {
                setBookmarksBarVisible(enabled)
            }
            
        case "setAdBlockEnabled":
            if let enabled = dict["enabled"] as? Bool {
                defaults.set(enabled, forKey: "OnyxAdBlockEnabled")
                applyAdBlockSetting()
            }
            
        case "setNewsEnabled":
            if let enabled = dict["enabled"] as? Bool {
                defaults.set(enabled, forKey: "OnyxNewsEnabled")
                for tab in tabs where isStartPageURL(tab.url) {
                    tab.webView.evaluateJavaScript(startPageNewsScript(), completionHandler: nil)
                }
            }
            
        case "setOfferSavePasswords":
            if let enabled = dict["enabled"] as? Bool {
                defaults.set(enabled, forKey: "OnyxOfferSavePasswords")
            }
            
        case "switchWorkspace":
            if let profId = dict["id"] as? String, let prof = profiles.first(where: { $0.id == profId }) {
                switchToProfile(prof)
            }
            
        case "createWorkspace":
            if let name = dict["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let colorHex = (dict["colorHex"] as? String).flatMap { NSColor(hex: $0) != nil ? $0 : nil }
                addCustomProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), hex: colorHex)
            }
            
        case "deleteWorkspace":
            if let profId = dict["id"] as? String {
                deleteCustomProfile(id: profId)
            }
            
        case "clearCache":
            clearActiveProfileCache()
            
        case "openDownloads":
            if let url = try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
                NSWorkspace.shared.open(url)
            }
            
        case "openPasswords":
            togglePasswordsPopover()
            
        default:
            return
        }
        
        // Every action re-syncs the page so it always reflects native state.
        if let webView = webView {
            sendSettingsPayload(to: webView)
        }
    }
    
    func startPageNewsScript() -> String {
        let enabled = UserDefaults.standard.object(forKey: "OnyxNewsEnabled") as? Bool ?? true
        return "if (window.setNewsEnabled) window.setNewsEnabled(\(enabled));"
    }
    
    // MARK: - Script Message Routing & Sender Verification
    /// Where a script message came from. Privileged bridges only answer Onyx's own pages;
    /// everything else on the web is untrusted and may post any message it likes.
    private func messageSource(_ message: WKScriptMessage) -> (isInternal: Bool, isSearchPage: Bool, url: URL?) {
        let frameURL = message.frameInfo.request.url
        guard message.frameInfo.isMainFrame else { return (false, false, frameURL) }
        return (isInternalPageURL(frameURL), isSearchURL(frameURL) || isResearchURL(frameURL), frameURL)
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let source = messageSource(message)
        let body = message.body as? [String: Any]
        
        switch message.name {
        // Onyx's context-menu probe. Registered only in Onyx's own content world, so page
        // scripts cannot post it; any frame is fine.
        case "onyxContextMenu":
            guard let dict = body, let webView = message.webView as? OnyxWebView else { return }
            handleContextMenuMessage(dict, from: webView)
        // Posted by pages Onyx injects into web content: allowed from the web, but scoped.
        case "onyxSavePasswordPrompt":
            guard message.frameInfo.isMainFrame, let dict = body, let webView = message.webView else { return }
            handleSavePasswordPromptMessage(dict, from: webView)
        case "bypassBotChallenge":
            guard source.isSearchPage, let webView = message.webView else { return }
            handleBotChallenge(in: webView)
        case "openProfileManager":
            guard source.isInternal || source.isSearchPage else { return }
            showProfileManagerPopover()
            
        // Privileged bridges: Onyx's bundled start page and settings page only.
        default:
            guard source.isInternal else {
                OnyxLog.security.notice("blocked \(message.name, privacy: .public) from untrusted frame \(source.url?.absoluteString ?? "nil", privacy: .private)")
                return
            }
            switch message.name {
            case "onyxSettings":
                if let dict = body { handleSettingsMessage(dict, from: message.webView) }
            case "onyxNavigate", "onyxSwitchWorkspace":
                if let urlStr = body?["url"] as? String, !urlStr.isEmpty {
                    let target = resolveQuery(urlStr)
                    // The start page may only send the tab to the web or back to Onyx pages.
                    guard ["http", "https"].contains(target.scheme?.lowercased() ?? "") || isInternalPageURL(target) else { return }
                    if let tab = tabs.first(where: { $0.webView == message.webView }) {
                        noteTypedGuess(tab: tab, input: urlStr, url: target)
                        loadTabURL(tab: tab, url: target)
                    } else {
                        loadURL(target)
                    }
                }
            case "onyxOpenSettings":
                openSettingsTab()
            case "onyxSetSearchEngine":
                if let engine = body?["engine"] as? String { setLiveSearchEngine(engine) }
            case "onyxFetchSuggestions":
                if let query = body?["query"] as? String, let reqId = body?["reqId"] as? String {
                    fetchSuggestionsForWeb(query: query, reqId: reqId, from: message.webView)
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Start Page Feed Proxy
    /// The start page runs from file://, which (correctly) cannot read cross-origin feeds that
    /// lack CORS headers. This proxies an allowlisted set of feed hosts for Onyx's own pages only.
    static let feedHostAllowlist: Set<String> = ["news.google.com", "hn.algolia.com"]
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.name == "onyxFetchFeed" else { return replyHandler(nil, "unknown handler") }
        guard messageSource(message).isInternal else { return replyHandler(nil, "untrusted sender") }
        guard let urlStr = (message.body as? [String: Any])?["url"] as? String,
              let url = URL(string: urlStr), url.scheme == "https",
              let host = url.host?.lowercased(), BrowserController.feedHostAllowlist.contains(host) else {
            return replyHandler(nil, "url not allowed")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        request.setValue("application/json, text/xml, */*", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let ok = ((response as? HTTPURLResponse)?.statusCode ?? 0) < 400
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            DispatchQueue.main.async {
                if error == nil, ok, let text = text {
                    replyHandler(text, nil)
                } else {
                    replyHandler(nil, error?.localizedDescription ?? "fetch failed")
                }
            }
        }.resume()
    }
}
