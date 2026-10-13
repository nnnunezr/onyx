import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Profile Manager Architecture
    func websiteDataStore(for profile: BrowserProfile) -> WKWebsiteDataStore {
        if #available(macOS 14.0, *) {
            let uuidString: String
            switch profile.id {
            case "personal":
                uuidString = "E1A8B2C3-4D5E-6F70-8192-A3B4C5D6E7F8"
            case "research":
                uuidString = "F2B9C3D4-5E6F-7081-92A3-B4C5D6E7F801"
            case "trading":
                uuidString = "A3C0D4E5-6F70-8192-A3B4-C5D6E7F80123"
            case "campus":
                uuidString = "B4D1E5F6-7081-92A3-B4C5-D6E7F8012345"
            default:
                if let uuid = UUID(uuidString: profile.id) {
                    uuidString = uuid.uuidString
                } else {
                    // String.hashValue is re-seeded every launch, so derive a stable
                    // 48-bit suffix with FNV-1a to keep this workspace's storage across restarts.
                    var hash: UInt64 = 0xcbf29ce484222325
                    for byte in profile.id.utf8 {
                        hash ^= UInt64(byte)
                        hash = hash &* 0x100000001b3
                    }
                    uuidString = String(format: "C5E2F6A7-8192-A3B4-C5D6-%012llX", hash & 0xFFFFFFFFFFFF)
                }
            }
            if let uuid = UUID(uuidString: uuidString) {
                return WKWebsiteDataStore(forIdentifier: uuid)
            }
        }
        return WKWebsiteDataStore.default()
    }
    
    func configuration(for profile: BrowserProfile) -> WKWebViewConfiguration {
        if let existing = profileConfigurations[profile.id] {
            return existing
        }
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        // macOS defaults this to true: any script could open tabs with no click. Popups opened
        // from a click (OAuth "Sign in with Google", target=_blank) still work.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.suppressesIncrementalRendering = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = websiteDataStore(for: profile)
        // No customUserAgent on the web views: WebKit builds the platform part, this adds the Safari tail.
        config.applicationNameForUserAgent = UserAgent.applicationName
        // Private preference (Web Inspector context menu). KVC on a key WebKit no longer
        // implements throws and would crash at launch, so check the setter first.
        PrivateWebKit.set(config.preferences, key: "developerExtrasEnabled", setter: "_setDeveloperExtrasEnabled:", value: true)
        // File-URL privileges (allowFileAccessFromFileURLs / allowUniversalAccessFromFileURLs) are
        // deliberately left OFF: with them on, any local HTML file could read other local files.
        // Bundled pages get subresource access via loadFileURL(_:allowingReadAccessTo:) instead.
        
        if let ruleList = adBlockRuleList, isAdBlockEnabled {
            config.userContentController.add(ruleList)
        }
        installUserScripts(for: config)
        
        for name in BrowserController.scriptMessageNames {
            config.userContentController.add(self, name: name)
        }
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "onyxFetchFeed")
        config.userContentController.add(self, contentWorld: .defaultClient, name: "onyxContextMenu")
        
        profileConfigurations[profile.id] = config
        return config
    }
    
    static let scriptMessageNames = [
        "openProfileManager", "onyxSavePasswordPrompt", "onyxSettings", "onyxNavigate",
        "onyxSwitchWorkspace", "onyxOpenSettings", "onyxFetchSuggestions", "onyxSetSearchEngine",
        "bypassBotChallenge"
    ]
    
    func switchToProfileIndex(_ index: Int) {
        guard index >= 0 && index < profiles.count else { return }
        switchToProfile(profiles[index])
    }
    
    func switchToProfile(_ profile: BrowserProfile) {
        guard profile.id != activeProfile.id else { return }
        
        // 1. Preserve current tabs & index for current profile
        profileTabs[activeProfile.id] = tabs
        profileActiveIndices[activeProfile.id] = activeTabIndex
        
        // 2. Remove web views safely without touching edgeGlowView
        webContainerView.subviews.forEach { view in
            if view !== edgeGlowView {
                view.removeFromSuperview()
            }
        }
        
        // 3. Switch active profile & update button
        activeProfile = profile
        profileButton.configure(profile: profile)
        
        // 4. Restore tabs for this profile or create a fresh start page tab
        if let savedTabs = profileTabs[profile.id], !savedTabs.isEmpty {
            tabs = savedTabs
            // `tabs` is now the source of truth for this workspace; a stale copy here would keep
            // tabs closed later in this visit alive (and possibly playing audio).
            profileTabs[profile.id] = nil
            let savedIndex = profileActiveIndices[profile.id] ?? 0
            activeTabIndex = min(savedIndex, tabs.count - 1)
        } else {
            tabs = []
            activeTabIndex = 0
            if !restoreSessionTabs(for: profile) {
                createNewTab(url: startPageURL)
            }
        }
        
        selectTab(at: activeTabIndex)
        
        // 5. Directional edge glow flash in new profile's color
        edgeGlowView?.flash(edge: .back, color: profile.color)
        
        // 6. Notify startpage of active profile
        notifyStartPageOfProfile()
    }
    
    @objc func showProfileManagerPopover() {
        if let pop = profilePopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let rowCount = profiles.count
        let totalHeight = CGFloat(50 + (rowCount * 48) + 10 + 98)
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 316, height: totalHeight))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.25).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerRow)
        
        let headerLabel = NSTextField(labelWithString: "WORKSPACES & PROFILES")
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        headerLabel.textColor = NSColor(white: 0.45, alpha: 1.0)
        headerRow.addSubview(headerLabel)
        
        let headerGearBtn = NavIconButton(iconName: "gearshape.fill", tooltip: "Workspaces & Browser Settings (⌘,)", target: nil, action: nil, size: 24)
        headerGearBtn.onClick = { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.openSettingsTab()
        }
        headerRow.addSubview(headerGearBtn)
        
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        container.addSubview(stack)
        
        for (i, prof) in profiles.enumerated() {
            let shortcutStr = i < 4 ? "⌘⌥\(i + 1)" : ""
            let tabCount = (prof.id == activeProfile.id) ? tabs.count : (profileTabs[prof.id]?.count ?? 0)
            let row = ProfileRowView(profile: prof, isActive: (prof.id == activeProfile.id), tabCount: tabCount, shortcut: shortcutStr)
            row.onClick = { [weak self, weak popover] in
                popover?.performClose(nil)
                self?.switchToProfile(prof)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        
        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .custom
        sep.borderWidth = 0
        sep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        container.addSubview(sep)
        
        let newProfileRow = ProfileActionRowView(title: "New Workspace / Profile...", iconName: "plus.circle")
        newProfileRow.onClick = { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.createNewProfilePrompt()
        }
        container.addSubview(newProfileRow)
        
        let settingsRow = ProfileActionRowView(title: "Settings & Preferences...", iconName: "gearshape")
        settingsRow.onClick = { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.openSettingsTab()
        }
        container.addSubview(settingsRow)
        
        let clearCacheRow = ProfileActionRowView(title: "Clear Active Workspace Cache...", iconName: "trash")
        clearCacheRow.onClick = { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.clearActiveProfileCache()
        }
        container.addSubview(clearCacheRow)
        
        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            headerRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            headerRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            headerRow.heightAnchor.constraint(equalToConstant: 24),
            
            headerLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            headerLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            
            headerGearBtn.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            headerGearBtn.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            headerGearBtn.widthAnchor.constraint(equalToConstant: 24),
            headerGearBtn.heightAnchor.constraint(equalToConstant: 24),
            
            stack.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            
            sep.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 6),
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            sep.heightAnchor.constraint(equalToConstant: 1),
            
            newProfileRow.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 6),
            newProfileRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            newProfileRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            
            settingsRow.topAnchor.constraint(equalTo: newProfileRow.bottomAnchor, constant: 2),
            settingsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            settingsRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            
            clearCacheRow.topAnchor.constraint(equalTo: settingsRow.bottomAnchor, constant: 2),
            clearCacheRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            clearCacheRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            clearCacheRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        
        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc
        profilePopover = popover
        
        popover.show(relativeTo: profileButton.bounds, of: profileButton, preferredEdge: .maxY)
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
    }
    
    func createNewProfilePrompt() {
        let alert = NSAlert()
        alert.messageText = "Create New Workspace"
        alert.informativeText = "Enter a name for the new isolated browsing workspace:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        inputField.placeholderString = "e.g. Work, Crypto, Research, Personal"
        alert.accessoryView = inputField
        
        if let window = self.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self = self, response == .alertFirstButtonReturn else { return }
                let name = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                self.addCustomProfile(name: name)
            }
        }
    }
    
    func addCustomProfile(name: String, hex: String? = nil) {
        let colors = ["#A855F7", "#EC4899", "#06B6D4", "#F97316", "#10B981", "#E4E4E7"]
        let colorHex = (hex != nil && !hex!.isEmpty) ? hex! : colors[profiles.count % colors.count]
        let newId = UUID().uuidString
        let newProfile = BrowserProfile(id: newId, name: name, iconName: "folder.badge.person.crop", colorHex: colorHex, isDefault: false)
        profiles.append(newProfile)
        saveProfiles()
        switchToProfile(newProfile)
    }
    
    func deleteCustomProfile(id: String) {
        guard profiles.count > 1 else { return }
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profToDelete = profiles[idx]
        guard !profToDelete.isDefault && profToDelete.id != "personal" else { return }
        
        if activeProfile.id == id {
            let nextProf = profiles.first(where: { $0.id != id }) ?? profiles[0]
            switchToProfile(nextProf)
        }
        
        profiles.removeAll(where: { $0.id == id })
        removeSavedSession(forWorkspace: id)
        // Its background tabs still have KVO observers and delegates pointing here; releasing
        // the web views with those attached is a KVO crash waiting for the deallocation.
        for tab in profileTabs[id] ?? [] {
            if tab.isObserved {
                tab.webView.removeObserver(self, forKeyPath: "estimatedProgress")
                tab.webView.removeObserver(self, forKeyPath: "title")
                tab.webView.removeObserver(self, forKeyPath: "URL")
                tab.isObserved = false
            }
            tab.webView.navigationDelegate = nil
            tab.webView.uiDelegate = nil
            tab.webView.pauseAllMediaPlayback(completionHandler: nil)
            tab.webView.stopLoading()
        }
        profileTabs.removeValue(forKey: id)
        profileActiveIndices.removeValue(forKey: id)
        profileConfigurations.removeValue(forKey: id)
        saveProfiles()
    }
    
    func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "OnyxProfiles")
        }
    }
    
    func loadSavedProfiles() {
        let result = Persistence.loadList(BrowserProfile.self, key: "OnyxProfiles")
        if let problem = result.problem {
            // Built-in workspaces stay available; the unreadable list is in Onyx/recovery and is only
            // replaced when a workspace is added or deleted.
            startupNotices.append(problem.userMessage)
        }
        let saved = result.items
        guard !saved.isEmpty else { return }
        profiles = saved
        if let def = saved.first(where: { $0.id == "personal" }) ?? saved.first {
            activeProfile = def
        }
    }
    
    func clearActiveProfileCache() {
        let store = websiteDataStore(for: activeProfile)
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        store.removeData(ofTypes: dataTypes, modifiedSince: dateFrom) { [weak self] in
            guard let self = self else { return }
            let alert = NSAlert()
            alert.messageText = "Workspace Cache Cleared"
            alert.informativeText = "Cookies, local storage, and website cache for workspace '\(self.activeProfile.name)' have been cleared."
            alert.addButton(withTitle: "OK")
            if let win = self.window {
                alert.beginSheetModal(for: win, completionHandler: nil)
            }
        }
    }
    
    func notifyStartPageOfProfile() {
        let js = startPageProfileScript()
        for tab in tabs {
            if isStartPageURL(tab.url) {
                tab.webView.evaluateJavaScript(js, completionHandler: nil)
            } else if isSettingsURL(tab.url) {
                sendSettingsPayload(to: tab.webView)
            }
        }
    }
    
    func startPageProfileScript() -> String {
        return "if (window.updateActiveProfile) window.updateActiveProfile(\(JS.string(activeProfile.name)), \(JS.string(activeProfile.colorHex)));"
    }
}
