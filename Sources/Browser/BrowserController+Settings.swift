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
        let defaultEngine = UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo"
        let startup = UserDefaults.standard.string(forKey: "OnyxStartupBehavior") ?? "startpage"
        let showBookmarks = UserDefaults.standard.object(forKey: "OnyxShowBookmarksBar") as? Bool ?? true
        let adBlock = UserDefaults.standard.object(forKey: "OnyxAdBlockEnabled") as? Bool ?? true
        let theme = UserDefaults.standard.string(forKey: "OnyxTheme") ?? "pitch-black"
        let downloadsPath = (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path) ?? "~/Downloads"
        
        var profList: [[String: Any]] = []
        for p in profiles {
            let tCount = (p.id == activeProfile.id) ? tabs.count : (profileTabs[p.id]?.count ?? 0)
            profList.append([
                "id": p.id,
                "name": p.name,
                "colorHex": p.colorHex,
                "tabCount": tCount,
                "isActive": (p.id == activeProfile.id)
            ])
        }
        
        let memMB = getResidentMemoryMB()
        let ramFormatted = String(format: "%.1f MB", memMB)
        
        let payload: [String: Any] = [
            "searchEngine": defaultEngine,
            "startup": startup,
            "showBookmarksBar": showBookmarks,
            "adBlockEnabled": adBlock,
            "theme": theme,
            "downloadsPath": downloadsPath,
            "profiles": profList,
            "ramUsage": ramFormatted
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let jsonStr = String(data: data, encoding: .utf8) {
            let js = "if (window.renderSettings) window.renderSettings(\(jsonStr));"
            DispatchQueue.main.async {
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
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
        
        switch action {
        case "getSettings":
            if let webView = webView {
                sendSettingsPayload(to: webView)
            }
            
        case "setSearchEngine":
            if let engine = dict["engine"] as? String {
                setLiveSearchEngine(engine)
            }
            
        case "setStartup":
            if let mode = dict["mode"] as? String {
                UserDefaults.standard.set(mode, forKey: "OnyxStartupBehavior")
            }
            
        case "setShowBookmarksBar":
            if let enabled = dict["enabled"] as? Bool {
                setBookmarksBarVisible(enabled)
            }
            
        case "setAdBlockEnabled":
            if let enabled = dict["enabled"] as? Bool {
                UserDefaults.standard.set(enabled, forKey: "OnyxAdBlockEnabled")
                if let ruleList = adBlockRuleList {
                    if enabled {
                        sharedConfiguration.userContentController.add(ruleList)
                        for (_, cfg) in profileConfigurations {
                            cfg.userContentController.add(ruleList)
                        }
                    } else {
                        sharedConfiguration.userContentController.remove(ruleList)
                        for (_, cfg) in profileConfigurations {
                            cfg.userContentController.remove(ruleList)
                        }
                    }
                }
            }
            
        case "switchWorkspace":
            if let profId = dict["id"] as? String, let prof = profiles.first(where: { $0.id == profId }) {
                switchToProfile(prof)
                if let webView = webView {
                    sendSettingsPayload(to: webView)
                }
            }
            
        case "createWorkspace":
            if let name = dict["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let colorHex = dict["colorHex"] as? String
                addCustomProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), hex: colorHex)
                if let webView = webView {
                    sendSettingsPayload(to: webView)
                }
            }
            
        case "deleteWorkspace":
            if let profId = dict["id"] as? String {
                deleteCustomProfile(id: profId)
                if let webView = webView {
                    sendSettingsPayload(to: webView)
                }
            }
            
        case "clearCache":
            clearActiveProfileCache()
            if let webView = webView {
                sendSettingsPayload(to: webView)
            }
            
        case "openDownloads":
            if let url = try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
                NSWorkspace.shared.open(url)
            }
            
        case "openPasswords":
            togglePasswordsPopover()
            
        default:
            break
        }
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "openProfileManager" {
            showProfileManagerPopover()
        } else if message.name == "onyxSettings", let dict = message.body as? [String: Any] {
            handleSettingsMessage(dict, from: message.webView)
        } else if message.name == "bypassBotChallenge" {
            handleBotChallenge(in: activeWebView)
        } else if message.name == "onyxSavePasswordPrompt", let dict = message.body as? [String: Any] {
            handleSavePasswordPromptMessage(dict)
        } else if message.name == "onyxNavigate", let dict = message.body as? [String: Any], let urlStr = dict["url"] as? String {
            let targetURL = resolveQuery(urlStr)
            loadURL(targetURL)
        } else if message.name == "onyxSwitchWorkspace", let dict = message.body as? [String: Any], let urlStr = dict["url"] as? String {
            if let targetURL = URL(string: urlStr) {
                loadURL(targetURL)
            }
        } else if message.name == "onyxOpenSettings" {
            openSettingsTab()
        } else if message.name == "onyxSetSearchEngine", let dict = message.body as? [String: Any], let engine = dict["engine"] as? String {
            setLiveSearchEngine(engine)
        } else if message.name == "onyxFetchSuggestions", let dict = message.body as? [String: Any], let query = dict["query"] as? String, let reqId = dict["reqId"] as? String {
            fetchSuggestionsForWeb(query: query, reqId: reqId, from: message.webView)
        }
    }
}
