import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    func setupUI() {
        guard let window = self.window, let contentView = window.contentView else { return }
        
        // 1. Titlebar Tab Bar (Height: 38px, native window drag on background, traffic lights at x: 12..70)
        tabBar = TabBarView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.wantsLayer = true
        tabBar.layer?.backgroundColor = NSColor(red: 14/255.0, green: 14/255.0, blue: 17/255.0, alpha: 1.0).cgColor
        contentView.addSubview(tabBar)
        
        tabSeparator = NSBox()
        tabSeparator.translatesAutoresizingMaskIntoConstraints = false
        tabSeparator.boxType = .custom
        tabSeparator.borderWidth = 0
        tabSeparator.fillColor = NSColor(white: 1.0, alpha: 0.05)
        tabBar.addSubview(tabSeparator)
        
        tabStack = NSStackView()
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabStack.orientation = .horizontal
        tabStack.spacing = 6
        tabStack.alignment = .centerY
        
        // The tab row scrolls horizontally once tabs reach their minimum width, so the number of
        // tabs never changes the window's minimum size.
        tabScrollView = TabStripScrollView()
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.drawsBackground = false
        tabScrollView.hasHorizontalScroller = false
        tabScrollView.hasVerticalScroller = false
        tabScrollView.horizontalScrollElasticity = .allowed
        tabScrollView.verticalScrollElasticity = .none
        tabScrollView.contentView.drawsBackground = false
        tabScrollView.documentView = tabStack
        tabBar.addSubview(tabScrollView)
        
        newTabBtn = NavIconButton(iconName: "plus", tooltip: "New Tab (⌘T)", target: self, action: #selector(newTabClicked), size: 24)
        newTabBtn.layer?.cornerRadius = 12
        newTabBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.04).cgColor
        newTabBtn.layer?.borderWidth = 1
        newTabBtn.layer?.borderColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        tabBar.addSubview(newTabBtn)
        
        // 2. Toolbar Container (Height: 40px, full-width below titlebar)
        topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = NSColor(red: 14/255.0, green: 14/255.0, blue: 17/255.0, alpha: 1.0).cgColor
        contentView.addSubview(topBar)
        
        topBarSeparator = NSBox()
        topBarSeparator.translatesAutoresizingMaskIntoConstraints = false
        topBarSeparator.boxType = .custom
        topBarSeparator.borderWidth = 0
        topBarSeparator.fillColor = NSColor(white: 1.0, alpha: 0.05)
        topBar.addSubview(topBarSeparator)
        
        // Nav Buttons (Back, Forward, Reload)
        backButton = NavIconButton(iconName: "chevron.left", tooltip: "Back (⌘[)", target: self, action: #selector(goBack))
        forwardButton = NavIconButton(iconName: "chevron.right", tooltip: "Forward (⌘])", target: self, action: #selector(goForward))
        reloadButton = NavIconButton(iconName: "arrow.clockwise", tooltip: "Reload (⌘R)", target: self, action: #selector(reloadPage))
        
        backButton.isEnabled = false
        forwardButton.isEnabled = false
        
        let navStack = NSStackView(views: [backButton, forwardButton, reloadButton])
        navStack.translatesAutoresizingMaskIntoConstraints = false
        navStack.orientation = .horizontal
        navStack.spacing = 4
        navStack.alignment = .centerY
        topBar.addSubview(navStack)
        
        // Address Bar / Search Container (Precision 32px dark obsidian capsule with 10px radius)
        searchContainer = NSView()
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.wantsLayer = true
        searchContainer.layer?.cornerRadius = 10
        searchContainer.layer?.borderWidth = 1
        searchContainer.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        searchContainer.layer?.backgroundColor = NSColor(red: 24/255.0, green: 24/255.0, blue: 28/255.0, alpha: 1.0).cgColor
        topBar.addSubview(searchContainer)
        
        searchFaviconView = NSImageView()
        searchFaviconView.translatesAutoresizingMaskIntoConstraints = false
        searchFaviconView.wantsLayer = true
        searchFaviconView.layer?.cornerRadius = 3
        searchFaviconView.layer?.masksToBounds = true
        searchFaviconView.imageScaling = .scaleProportionallyUpOrDown
        if let img = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Favicon") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            searchFaviconView.image = img.withSymbolConfiguration(config)
            searchFaviconView.contentTintColor = NSColor(white: 0.60, alpha: 1.0)
        }
        searchFaviconView.toolTip = "Search Engine: Click to change default"
        let engineClickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(showSearchEngineMenu(_:)))
        searchFaviconView.addGestureRecognizer(engineClickRecognizer)
        searchContainer.addSubview(searchFaviconView)
        
        searchThinkingOrb = ThinkingOrbView()
        searchThinkingOrb.translatesAutoresizingMaskIntoConstraints = false
        searchThinkingOrb.isHidden = true
        searchContainer.addSubview(searchThinkingOrb)
        
        searchField = CustomSearchBar()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.focusRingType = .none
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.textColor = NSColor(white: 0.98, alpha: 1.0)
        searchField.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        updateSearchPlaceholder()
        updateSearchEngineIcon()
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldSubmitted)
        searchContainer.addSubview(searchField)
        
        searchShortcutBadge = NSTextField(labelWithString: "⌘L")
        searchShortcutBadge.translatesAutoresizingMaskIntoConstraints = false
        searchShortcutBadge.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)
        searchShortcutBadge.textColor = NSColor(white: 0.45, alpha: 1.0)
        searchShortcutBadge.wantsLayer = true
        searchShortcutBadge.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        searchShortcutBadge.layer?.cornerRadius = 4
        searchContainer.addSubview(searchShortcutBadge)
        
        searchField.onFocusChanged = { [weak self] focused in
            guard let self = self else { return }
            if focused {
                self.suggestedPopover?.performClose(nil)
                self.searchShortcutBadge.isHidden = true
            } else {
                self.searchShortcutBadge.isHidden = !self.searchField.stringValue.isEmpty
            }
            self.updateSearchContainerGlow(for: self.searchField.stringValue, focused: focused)
        }
        
        // Trailing Toolbar Controls (Pinnable Extensions Stack, Extensions Menu, Profile)
        suggestedTabsBtn = NavIconButton(iconName: "sparkles", tooltip: "AI Research Canvas (⌘⇧S)", target: self, action: #selector(showSuggestedTabsPopover))
        downloadsButton = DownloadsNavButton(target: self, action: #selector(toggleDownloadsPopover))
        passwordsButton = PasswordsNavButton(target: self, action: #selector(togglePasswordsPopover))
        shieldButton = NavIconButton(iconName: "shield.checkerboard", tooltip: "Onyx Shield: Private & Fast (30 MB RAM)", target: self, action: #selector(showPrivacyReport))
        
        extensionsStack = NSStackView(views: [suggestedTabsBtn, downloadsButton, passwordsButton, shieldButton])
        extensionsStack.translatesAutoresizingMaskIntoConstraints = false
        extensionsStack.orientation = .horizontal
        extensionsStack.spacing = 6
        extensionsStack.alignment = .centerY
        
        extensionsButton = NavIconButton(iconName: "puzzlepiece.extension", tooltip: "Extensions", target: self, action: #selector(toggleExtensionsPopover))
        
        profileButton = ProfilePillButton(target: self, action: #selector(showProfileManagerPopover))
        profileButton.configure(profile: activeProfile)
        profileButton.onSettingsClick = { [weak self] in
            self?.openSettingsTab()
        }
        
        trailingControlsStack = NSStackView(views: [extensionsStack, extensionsButton, profileButton])
        trailingControlsStack.translatesAutoresizingMaskIntoConstraints = false
        trailingControlsStack.orientation = .horizontal
        trailingControlsStack.spacing = 8
        trailingControlsStack.alignment = .centerY
        topBar.addSubview(trailingControlsStack)
        
        setupExtensionContextMenus()
        applyToolbarPins()
        
        // 3. Bookmarks Shelf (Height: 28px, resting 100% transparent items matching Comet)
        bookmarksBar = BookmarksBarView()
        bookmarksBar.controller = self
        bookmarksBar.translatesAutoresizingMaskIntoConstraints = false
        bookmarksBar.wantsLayer = true
        bookmarksBar.layer?.backgroundColor = NSColor(red: 22/255.0, green: 22/255.0, blue: 25/255.0, alpha: 1.0).cgColor
        bookmarksBar.toolTip = "Bookmarks (Left-click for options)"
        contentView.addSubview(bookmarksBar)
        
        bookmarksSeparator = NSBox()
        bookmarksSeparator.translatesAutoresizingMaskIntoConstraints = false
        bookmarksSeparator.boxType = .custom
        bookmarksSeparator.borderWidth = 0
        bookmarksSeparator.fillColor = NSColor(white: 1.0, alpha: 0.06)
        bookmarksBar.addSubview(bookmarksSeparator)
        
        bookmarksStack = BookmarksStackView()
        bookmarksStack.translatesAutoresizingMaskIntoConstraints = false
        bookmarksStack.orientation = .horizontal
        bookmarksStack.spacing = 4
        bookmarksStack.alignment = .centerY
        bookmarksBar.addSubview(bookmarksStack)
        
        manageBookmarksBtn = NavIconButton(iconName: "ellipsis", tooltip: "Manage Bookmarks...", target: self, action: #selector(manageBookmarksButtonClicked(_:)), size: 20)
        manageBookmarksBtn.layer?.cornerRadius = 4
        manageBookmarksBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        bookmarksBar.addSubview(manageBookmarksBtn)
        
        renderBookmarks()
        
        // Hairline Progress Bar (Onyx Pure White Liquid Stream, 1.5px)
        progressBar = NSBox()
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.boxType = .custom
        progressBar.borderWidth = 0
        progressBar.fillColor = NSColor(white: 1.0, alpha: 0.90)
        progressBar.wantsLayer = true
        progressBar.layer?.shadowColor = NSColor.white.cgColor
        progressBar.layer?.shadowOpacity = 0.4
        progressBar.layer?.shadowRadius = 3
        progressBar.layer?.shadowOffset = .zero
        progressBar.isHidden = true
        bookmarksBar.addSubview(progressBar)
        
        // 4. Web Content Container View
        webContainerView = NSView()
        webContainerView.translatesAutoresizingMaskIntoConstraints = false
        webContainerView.wantsLayer = true
        webContainerView.layer?.backgroundColor = NSColor(red: 7/255.0, green: 7/255.0, blue: 9/255.0, alpha: 1.0).cgColor
        contentView.addSubview(webContainerView)
        
        // Directional Edge Glow Shimmer View
        edgeGlowView = DirectionalEdgeGlowView()
        webContainerView.addSubview(edgeGlowView)
        NSLayoutConstraint.activate([
            edgeGlowView.topAnchor.constraint(equalTo: webContainerView.topAnchor),
            edgeGlowView.bottomAnchor.constraint(equalTo: webContainerView.bottomAnchor),
            edgeGlowView.leadingAnchor.constraint(equalTo: webContainerView.leadingAnchor),
            edgeGlowView.trailingAnchor.constraint(equalTo: webContainerView.trailingAnchor)
        ])
        
        let initialBookmarksVisible = UserDefaults.standard.object(forKey: "OnyxShowBookmarksBar") as? Bool ?? true
        progressConstraint = progressBar.widthAnchor.constraint(equalToConstant: 0)
        bookmarksBarHeightConstraint = bookmarksBar.heightAnchor.constraint(equalToConstant: initialBookmarksVisible ? 28 : 0)
        bookmarksBar.alphaValue = initialBookmarksVisible ? 1.0 : 0.0
        
        tabStripWidthConstraint = tabScrollView.widthAnchor.constraint(equalToConstant: 0)
        tabStripWidthConstraint.isActive = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: tabBar, queue: .main) { [weak self] _ in
            self?.layoutTabStrip()
        }
        tabBar.postsFrameChangedNotifications = true
        
        NSLayoutConstraint.activate([
            // Row 1: Titlebar Tab Bar (38px, starts at x: 78 to clear macOS traffic lights at 12..70)
            tabBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 38),
            
            tabSeparator.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
            tabSeparator.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            tabSeparator.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            tabSeparator.heightAnchor.constraint(equalToConstant: 1),
            
            tabScrollView.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 78),
            tabScrollView.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabScrollView.heightAnchor.constraint(equalToConstant: 32),
            tabStack.leadingAnchor.constraint(equalTo: tabScrollView.contentView.leadingAnchor),
            tabStack.topAnchor.constraint(equalTo: tabScrollView.contentView.topAnchor),
            tabStack.heightAnchor.constraint(equalTo: tabScrollView.contentView.heightAnchor),
            
            newTabBtn.leadingAnchor.constraint(equalTo: tabScrollView.trailingAnchor, constant: 4),
            newTabBtn.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            
            // Row 2: Toolbar (40px)
            topBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            topBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 40),
            
            topBarSeparator.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            topBarSeparator.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            topBarSeparator.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            topBarSeparator.heightAnchor.constraint(equalToConstant: 1),
            
            navStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            navStack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            
            trailingControlsStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            trailingControlsStack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            
            searchContainer.leadingAnchor.constraint(equalTo: navStack.trailingAnchor, constant: 12),
            searchContainer.trailingAnchor.constraint(equalTo: trailingControlsStack.leadingAnchor, constant: -12),
            searchContainer.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            searchContainer.heightAnchor.constraint(equalToConstant: 32),
            
            searchFaviconView.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10),
            searchFaviconView.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchFaviconView.widthAnchor.constraint(equalToConstant: 14),
            searchFaviconView.heightAnchor.constraint(equalToConstant: 14),
            
            searchThinkingOrb.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 9),
            searchThinkingOrb.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchThinkingOrb.widthAnchor.constraint(equalToConstant: 16),
            searchThinkingOrb.heightAnchor.constraint(equalToConstant: 16),
            
            searchField.leadingAnchor.constraint(equalTo: searchFaviconView.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchShortcutBadge.leadingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            
            searchShortcutBadge.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -8),
            searchShortcutBadge.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            
            // Row 3: Bookmarks Shelf (28px)
            bookmarksBar.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            bookmarksBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bookmarksBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bookmarksBarHeightConstraint,
            
            bookmarksSeparator.bottomAnchor.constraint(equalTo: bookmarksBar.bottomAnchor),
            bookmarksSeparator.leadingAnchor.constraint(equalTo: bookmarksBar.leadingAnchor),
            bookmarksSeparator.trailingAnchor.constraint(equalTo: bookmarksBar.trailingAnchor),
            bookmarksSeparator.heightAnchor.constraint(equalToConstant: 1),
            
            bookmarksStack.leadingAnchor.constraint(equalTo: bookmarksBar.leadingAnchor, constant: 14),
            bookmarksStack.trailingAnchor.constraint(lessThanOrEqualTo: manageBookmarksBtn.leadingAnchor, constant: -8),
            bookmarksStack.centerYAnchor.constraint(equalTo: bookmarksBar.centerYAnchor),
            
            manageBookmarksBtn.trailingAnchor.constraint(equalTo: bookmarksBar.trailingAnchor, constant: -12),
            manageBookmarksBtn.centerYAnchor.constraint(equalTo: bookmarksBar.centerYAnchor),
            
            progressBar.bottomAnchor.constraint(equalTo: bookmarksBar.bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: bookmarksBar.leadingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 1.5),
            progressConstraint,
            
            // Web Content Container
            webContainerView.topAnchor.constraint(equalTo: bookmarksBar.bottomAnchor),
            webContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        updateActiveBookmarkHighlight()
    }
    
    func updateSearchPlaceholder() {
        let defaultEngine = UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo"
        let engineName: String
        switch defaultEngine.lowercased() {
        case "google": engineName = "Google"
        case "brave": engineName = "Brave"
        case "perplexity": engineName = "Perplexity"
        case "kagi": engineName = "Kagi"
        case "bing": engineName = "Bing"
        default: engineName = "DuckDuckGo"
        }
        let msg = "Search with \(engineName) or enter address"
        searchField.placeholderAttributedString = NSAttributedString(
            string: msg,
            attributes: [
                .foregroundColor: NSColor(white: 0.45, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12, weight: .regular)
            ]
        )
    }
    
    func updateSearchEngineIcon() {
        let defaultEngine = UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo"
        let iconName: String
        switch defaultEngine.lowercased() {
        case "google": iconName = "g.circle.fill"
        case "brave": iconName = "shield.checkerboard"
        case "perplexity": iconName = "sparkles"
        case "kagi": iconName = "magnifyingglass.circle.fill"
        case "bing": iconName = "b.circle.fill"
        default: iconName = "sparkles"
        }
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: "Search Engine") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            searchFaviconView.image = img.withSymbolConfiguration(config)
            searchFaviconView.contentTintColor = NSColor(white: 0.70, alpha: 1.0)
        }
    }
    
    @objc func showSearchEngineMenu(_ sender: Any?) {
        let menu = NSMenu(title: "Default Search Engine")
        let currentEngine = (UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo").lowercased()
        
        let engines: [(key: String, title: String, icon: String)] = [
            ("duckduckgo", "DuckDuckGo (AI Chat Ready)", "sparkles"),
            ("google", "Google", "g.circle.fill"),
            ("brave", "Brave Search (Private)", "shield.checkerboard"),
            ("perplexity", "Perplexity AI", "sparkles"),
            ("kagi", "Kagi Search", "magnifyingglass.circle.fill"),
            ("bing", "Microsoft Bing", "b.circle.fill")
        ]
        
        for (key, title, icon) in engines {
            let item = NSMenuItem(title: title, action: #selector(searchEngineMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                item.image = img.withSymbolConfiguration(cfg)
            }
            item.state = (key == currentEngine) ? .on : .off
            menu.addItem(item)
        }
        
        let location = NSPoint(x: 0, y: searchFaviconView.bounds.maxY + 4)
        menu.popUp(positioning: nil, at: location, in: searchFaviconView)
    }

    @objc func searchEngineMenuItemClicked(_ sender: NSMenuItem) {
        if let engine = sender.representedObject as? String {
            setLiveSearchEngine(engine)
        }
    }
    
    func setLiveSearchEngine(_ engine: String) {
        guard let normalized = SearchEngines.normalize(engine) else { return }
        
        // 1. Persist engine preference immediately
        UserDefaults.standard.set(normalized, forKey: "OnyxSearchEngine")
        
        // 2. Update omnibar placeholder & icon
        updateSearchPlaceholder()
        updateSearchEngineIcon()
        
        // 3. Inform Onyx's own open pages live (never third-party sites) without reloading them
        let engineJS = JS.string(normalized)
        let broadcastScript = """
        window.postMessage({ type: 'onyx-search-engine-changed', engine: \(engineJS) }, '*');
        if (typeof window.onOnyxSearchEngineChanged === 'function') {
            window.onOnyxSearchEngineChanged(\(engineJS));
        }
        if (typeof window.setSearchEngine === 'function') {
            window.setSearchEngine(\(engineJS));
        }
        """
        for tab in tabs where isInternalPageURL(tab.webView.url ?? tab.url) {
            tab.webView.evaluateJavaScript(broadcastScript, completionHandler: nil)
        }
        
        // 4. If current active tab is currently on a search results page, seamlessly reroute to the new engine
        if let currentURL = activeWebView.url {
            let urlStr = currentURL.absoluteString
            let isSearchURL = urlStr.contains("duckduckgo.com/?q=") ||
                              urlStr.contains("google.com/search?") ||
                              urlStr.contains("search.brave.com/search?") ||
                              urlStr.contains("perplexity.ai/search?") ||
                              urlStr.contains("bing.com/search?") ||
                              urlStr.contains("kagi.com/search?")
            
            if isSearchURL, let components = URLComponents(url: currentURL, resolvingAgainstBaseURL: false) {
                if let queryItem = components.queryItems?.first(where: { $0.name == "q" || $0.name == "query" }),
                   let currentQuery = queryItem.value, !currentQuery.isEmpty {
                    let newURL = resolveQuery(currentQuery)
                    loadURL(newURL)
                }
            }
        }
        
        // 5. Update engine chips in suggestionsView if open
        suggestionsView?.updateActiveEngine(normalized)
        
        // 6. Display a sleek toast HUD confirming live switch
        let engineDisplayName: String
        switch normalized {
        case "google": engineDisplayName = "Google"
        case "brave": engineDisplayName = "Brave Search"
        case "perplexity": engineDisplayName = "Perplexity AI"
        case "kagi": engineDisplayName = "Kagi"
        case "bing": engineDisplayName = "Microsoft Bing"
        default: engineDisplayName = "DuckDuckGo"
        }
        showVaultToastHUD(icon: "sparkles", title: "SEARCH ENGINE CHANGED", message: "Live default set to \(engineDisplayName)")
    }
}
