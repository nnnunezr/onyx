import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Tab Manager Methods
    func createNewTab(url: URL, switchTo: Bool = true) {
        let config = configuration(for: activeProfile)
        let tab = BrowserTab(url: url, configuration: config)
        if isSettingsURL(url) {
            tab.title = "Settings"
            if let img = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                tab.favicon = img.withSymbolConfiguration(cfg)
            }
        } else if let host = url.host, !url.isFileURL {
            tab.favicon = FaviconManager.shared.cachedFavicon(for: host)
        }
        attachTab(tab)
        
        if switchTo {
            selectTab(at: tabs.count - 1)
        } else {
            renderTabs()
        }
        
        loadTabURL(tab: tab, url: url)
    }
    
    /// Opens a URL handed to Onyx at launch. Loading it into the brand-new start page tab does
    /// not work: WebKit drops a web load issued right after that tab's pending file load. So open
    /// it in its own tab and discard the untouched start page.
    func openLaunchURL(_ url: URL) {
        let untouchedStartPage = tabs.count == 1 && isStartPageURL(tabs[0].url)
        createNewTab(url: url, switchTo: true)
        if untouchedStartPage {
            closeTab(at: 0)
        }
    }
    
    /// Wires delegates + KVO and appends the tab. Does not load anything or change selection.
    func attachTab(_ tab: BrowserTab) {
        tab.webView.navigationDelegate = self
        tab.webView.uiDelegate = self
        tab.webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
        tab.webView.addObserver(self, forKeyPath: "title", options: .new, context: nil)
        tab.webView.addObserver(self, forKeyPath: "URL", options: .new, context: nil)
        tab.isObserved = true
        tabs.append(tab)
    }
    
    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        hideFindBar(restoreFocus: false)
        
        // If the outgoing page (or nothing) had focus, hand focus to the incoming page so the
        // keyboard keeps working after a switch. Leave it alone while the omnibox is being edited.
        let responder = window?.firstResponder
        let pageHadFocus = responder === window || (responder as? NSView).map { view in
            webContainerView.subviews.contains { $0 !== edgeGlowView && (view === $0 || view.isDescendant(of: $0)) }
        } ?? true
        
        // Remove previous web view safely without triggering computed properties
        webContainerView.subviews.forEach { view in
            if view !== edgeGlowView {
                view.removeFromSuperview()
            }
        }
        activeTabIndex = index
        
        // Add new active web view positioned below edge glow overlay
        let currentTab = tabs[index]
        if let edgeGlow = edgeGlowView {
            webContainerView.addSubview(currentTab.webView, positioned: .below, relativeTo: edgeGlow)
        } else {
            webContainerView.addSubview(currentTab.webView)
        }
        
        currentTab.webView.frame = webContainerView.bounds
        
        if pageHadFocus {
            window?.makeFirstResponder(currentTab.webView)
        }
        
        renderTabs()
        updateSearchField(url: currentTab.url)
        window?.title = currentTab.title
        
        if currentTab.needsReload {
            reloadAfterCrash(currentTab)
        }
        
        if currentTab.webView.isLoading {
            let isSearch = isSearchURL(currentTab.url)
            if isSearch {
                searchThinkingOrb.stopAnimation()
                searchThinkingOrb.isHidden = true
                searchFaviconView.image = nil
                searchFaviconView.isHidden = true
            } else {
                searchFaviconView.isHidden = true
                searchThinkingOrb.startAnimation(mode: .orbits)
            }
        } else if isSearchURL(currentTab.url) {
            searchThinkingOrb.stopAnimation()
            searchThinkingOrb.isHidden = true
            searchFaviconView.image = nil
            searchFaviconView.isHidden = true
        } else {
            searchThinkingOrb.stopAnimation()
            searchFaviconView.isHidden = false
            updateSearchFavicon(for: currentTab.url)
        }
        
        backButton.isEnabled = currentTab.webView.canGoBack
        forwardButton.isEnabled = currentTab.webView.canGoForward
        
        updateActiveBookmarkHighlight()
        updatePasswordsBadge(for: currentTab.url)
    }
    
    func closeTab(tab: BrowserTab) {
        guard let idx = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        closeTab(at: idx)
    }
    
    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        let closingTab = tabs[index]
        let wasActive = (index == activeTabIndex)
        
        if closingTab.isObserved {
            closingTab.webView.removeObserver(self, forKeyPath: "estimatedProgress")
            closingTab.webView.removeObserver(self, forKeyPath: "title")
            closingTab.webView.removeObserver(self, forKeyPath: "URL")
            closingTab.isObserved = false
        }
        closingTab.webView.navigationDelegate = nil
        closingTab.webView.uiDelegate = nil
        closingTab.webView.pauseAllMediaPlayback(completionHandler: nil)
        closingTab.webView.stopLoading()
        closingTab.webView.removeFromSuperview()
        
        tabs.remove(at: index)
        defer { scheduleSessionSave() }
        
        if tabs.isEmpty {
            activeTabIndex = 0
            createNewTab(url: startPageURL)
            return
        }
        
        if wasActive {
            let nextIndex = min(index, tabs.count - 1)
            selectTab(at: nextIndex)
        } else {
            if index < activeTabIndex {
                activeTabIndex -= 1
            }
            renderTabs()
        }
    }
    
    func renderTabs() {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, tab) in tabs.enumerated() {
            let tabView = TabItemView(tab: tab, index: i, isSelected: (i == activeTabIndex))
            tabView.onSelect = { [weak self] t in
                if let idx = self?.tabs.firstIndex(where: { $0.id == t.id }) {
                    self?.selectTab(at: idx)
                }
            }
            tabView.onClose = { [weak self] t in
                self?.closeTab(tab: t)
            }
            tabView.onDuplicate = { [weak self] t in
                self?.duplicateTab(t)
            }
            tabView.onReload = { t in
                t.webView.reload()
            }
            tabView.onCloseOthers = { [weak self] t in
                self?.closeOtherTabs(t)
            }
            tabView.onCopyURL = { t in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(t.url.absoluteString, forType: .string)
            }
            tabStack.addArrangedSubview(tabView)
        }
        layoutTabStrip()
    }
    
    /// Tabs share the space between the traffic lights and the right-hand controls: 220 pt each
    /// when they fit, shrinking evenly to 72 pt; past that the row scrolls and keeps the active
    /// tab in view.
    func layoutTabStrip() {
        guard let tabBar = tabBar, let stack = tabStack, let strip = tabScrollView else { return }
        let maxWidth: CGFloat = 220, minWidth: CGFloat = 72
        let leading: CGFloat = 78, reservedTrailing: CGFloat = 120, newTabSpace: CGFloat = 4 + 24
        let available = max(minWidth, tabBar.bounds.width - leading - reservedTrailing - newTabSpace)
        let count = CGFloat(max(stack.arrangedSubviews.count, 1))
        let spacing = stack.spacing * (count - 1)
        let tabWidth = min(maxWidth, max(minWidth, ((available - spacing) / count).rounded(.down)))
        for view in stack.arrangedSubviews {
            if let c = view.constraints.first(where: { $0.identifier == "onyxTabWidth" }) {
                c.constant = tabWidth
            } else {
                let c = view.widthAnchor.constraint(equalToConstant: tabWidth)
                c.identifier = "onyxTabWidth"
                c.isActive = true
            }
        }
        let contentWidth = tabWidth * count + spacing
        tabStripWidthConstraint.constant = min(contentWidth, available)
        stack.layoutSubtreeIfNeeded()
        strip.layoutSubtreeIfNeeded()
        if activeTabIndex < stack.arrangedSubviews.count {
            let active = stack.arrangedSubviews[activeTabIndex]
            active.scrollToVisible(active.bounds.insetBy(dx: -8, dy: 0))
        }
    }

    func duplicateTab(_ tab: BrowserTab) {
        createNewTab(url: tab.url, switchTo: true)
    }

    func closeOtherTabs(_ tab: BrowserTab) {
        let tabsToClose = tabs.filter { $0.id != tab.id }
        for t in tabsToClose {
            closeTab(tab: t)
        }
    }

    func updateTabFavicon(for tab: BrowserTab, favicon: NSImage) {
        tab.favicon = favicon
        for subview in tabStack.arrangedSubviews {
            if let tabItem = subview as? TabItemView, tabItem.tab.id == tab.id {
                tabItem.updateFavicon(favicon)
            }
        }
        if tab.id == activeTab.id {
            searchFaviconView.image = favicon
            searchFaviconView.contentTintColor = nil
        }
    }
    
    func fetchFavicon(for tab: BrowserTab) {
        let currentURL = tab.webView.url ?? tab.url
        guard !currentURL.isFileURL, let host = currentURL.host, !host.isEmpty else { return }
        
        // 1. Instant cache hit check
        if let cached = FaviconManager.shared.cachedFavicon(for: host) {
            updateTabFavicon(for: tab, favicon: cached)
            return
        }
        
        // 2. Query page DOM for favicon link tags
        let js = """
        (function() {
            var links = document.querySelectorAll("link[rel*='icon']");
            var urls = [];
            for (var i = 0; i < links.length; i++) {
                if (links[i].href) {
                    urls.push(links[i].href);
                }
            }
            return urls;
        })();
        """
        
        tab.webView.evaluateJavaScript(js) { [weak self, weak tab] (result, _) in
            guard let self = self, let tab = tab else { return }
            var candidates: [URL] = []
            
            if let hrefs = result as? [String] {
                for href in hrefs {
                    if let u = URL(string: href, relativeTo: currentURL)?.absoluteURL {
                        candidates.append(u)
                    }
                }
            }
            
            // Standard root /favicon.ico
            if let rootFavicon = URL(string: "\(currentURL.scheme ?? "https")://\(host)/favicon.ico") {
                candidates.append(rootFavicon)
            }
            
            // Only the site's own icons. The Google S2 and DuckDuckGo icon-service fallbacks told
            // those companies every host Onyx visited (including LAN and localhost hosts).
            
            FaviconManager.shared.fetchFirstValidFavicon(from: candidates, forHost: host) { [weak self, weak tab] image in
                guard let image = image, let self = self, let tab = tab else { return }
                DispatchQueue.main.async {
                    self.updateTabFavicon(for: tab, favicon: image)
                }
            }
        }
    }

    func updateActiveBookmarkHighlight() {
        let currentURL = activeTab.url
        let currentHost = currentURL.host?.lowercased() ?? ""
        let currentStr = currentURL.absoluteString.lowercased()
        
        for btn in bookmarkButtons {
            let domain = btn.bookmark.domain.lowercased()
            let matches = (!currentHost.isEmpty && (currentHost.contains(domain) || domain.contains(currentHost))) || currentStr.contains(domain)
            btn.isActive = matches
        }
    }
    
    @objc func newTabClicked() {
        createNewTab(url: startPageURL)
    }
    
    @objc func showSuggestedTabsPopover() {
        if let pop = suggestedPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let suggestedList: [SuggestedWorkspaceItem] = [
            SuggestedWorkspaceItem(title: "AI Research Canvas", subtitle: "Instant synthetic research & deep canvas", iconName: "sparkles", urlString: "https://duckduckgo.com/?q=&ia=chat", shortcut: "⌘1"),
            SuggestedWorkspaceItem(title: "NinjaTrader Web", subtitle: "Futures & live algorithmic charting", iconName: "chart.xyaxis.line", urlString: "https://web.ninjatrader.com/trading-mode", shortcut: "⌘2"),
            SuggestedWorkspaceItem(title: "UNAPEC Virtual", subtitle: "Campus portal & student coursework", iconName: "graduationcap", urlString: "https://canvas.unapec.edu.do/", shortcut: "⌘3"),
            SuggestedWorkspaceItem(title: "Conflictly AI", subtitle: "Resolution intelligence workspace", iconName: "bubble.left.and.bubble.right", urlString: "https://www.conflictly.app/dashboard", shortcut: "⌘4"),
            SuggestedWorkspaceItem(title: "Tradesea Terminal", subtitle: "Algorithmic execution platform", iconName: "chart.line.uptrend.xyaxis", urlString: "https://app.tradesea.ai/trade", shortcut: "⌘5"),
            SuggestedWorkspaceItem(title: "Finviz Elite", subtitle: "Market screener & sector heatmaps", iconName: "waveform.path.ecg", urlString: "https://finviz.com/", shortcut: "⌘6")
        ]
        
        let newsList: [SuggestedNewsItem] = [
            SuggestedNewsItem(headline: "Claude 3.7 & Hybrid Extended Reasoning Released", source: "anthropic.com", category: "AI", time: "5m", urlString: "https://www.anthropic.com/news"),
            SuggestedNewsItem(headline: "Semiconductor Index Rallies to Record High on Hyperscale CapEx", source: "bloomberg.com", category: "MARKETS", time: "18m", urlString: "https://www.bloomberg.com/markets"),
            SuggestedNewsItem(headline: "DeepSeek-R1 Architecture: Verification Loops & Open Weights", source: "deepseek.com", category: "AI", time: "44m", urlString: "https://api-docs.deepseek.com/news"),
            SuggestedNewsItem(headline: "High-Performance Native Mac WebKit Runtimes in Swift", source: "news.ycombinator.com", category: "TECH", time: "32m", urlString: "https://news.ycombinator.com/"),
            SuggestedNewsItem(headline: "Mega-Cap Tech Heatmaps: Sector Rotations & Market Breadth", source: "finviz.com", category: "MARKETS", time: "25m", urlString: "https://finviz.com/")
        ]
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340, height: 368))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.25).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        let segControl = NSSegmentedControl(labels: ["Workspaces", "Live News"], trackingMode: .selectOne, target: nil, action: nil)
        segControl.translatesAutoresizingMaskIntoConstraints = false
        segControl.segmentStyle = .texturedRounded
        segControl.selectedSegment = 0
        container.addSubview(segControl)
        
        let settingsBtn = NavIconButton(iconName: "gearshape.fill", tooltip: "Workspaces & Settings (⌘,)", target: nil, action: nil, size: 24)
        settingsBtn.onClick = { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.openSettingsTab()
        }
        container.addSubview(settingsBtn)
        
        let workspaceStack = NSStackView()
        workspaceStack.translatesAutoresizingMaskIntoConstraints = false
        workspaceStack.orientation = .vertical
        workspaceStack.spacing = 4
        workspaceStack.alignment = .leading
        container.addSubview(workspaceStack)
        
        for item in suggestedList {
            let row = SuggestedWorkspaceRowView(item: item)
            row.onClick = { [weak self, weak popover] in
                popover?.performClose(nil)
                guard let self = self, let url = URL(string: item.urlString) else { return }
                if self.activeTab.url.isFileURL && self.activeTab.url.path.contains("startpage.html") {
                    self.loadURL(url)
                } else {
                    self.createNewTab(url: url)
                }
            }
            workspaceStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: workspaceStack.widthAnchor).isActive = true
        }
        
        let newsStack = NSStackView()
        newsStack.translatesAutoresizingMaskIntoConstraints = false
        newsStack.orientation = .vertical
        newsStack.spacing = 4
        newsStack.alignment = .leading
        newsStack.isHidden = true
        container.addSubview(newsStack)
        
        for item in newsList {
            let row = SuggestedNewsRowView(item: item)
            row.onClick = { [weak self, weak popover] in
                popover?.performClose(nil)
                guard let self = self, let url = URL(string: item.urlString) else { return }
                if self.activeTab.url.isFileURL && self.activeTab.url.path.contains("startpage.html") {
                    self.loadURL(url)
                } else {
                    self.createNewTab(url: url)
                }
            }
            newsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: newsStack.widthAnchor).isActive = true
        }
        
        class PopoverSegmentHandler: NSObject {
            let onSwitch: (Int) -> Void
            init(onSwitch: @escaping (Int) -> Void) { self.onSwitch = onSwitch }
            @objc func segChanged(_ sender: NSSegmentedControl) { onSwitch(sender.selectedSegment) }
        }
        
        let handler = PopoverSegmentHandler { segIdx in
            workspaceStack.isHidden = (segIdx != 0)
            newsStack.isHidden = (segIdx != 1)
        }
        objc_setAssociatedObject(container, "popoverSegHandler", handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        segControl.target = handler
        segControl.action = #selector(PopoverSegmentHandler.segChanged(_:))
        
        NSLayoutConstraint.activate([
            segControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            segControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            segControl.trailingAnchor.constraint(equalTo: settingsBtn.leadingAnchor, constant: -8),
            segControl.heightAnchor.constraint(equalToConstant: 24),
            
            settingsBtn.centerYAnchor.constraint(equalTo: segControl.centerYAnchor),
            settingsBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            settingsBtn.widthAnchor.constraint(equalToConstant: 24),
            settingsBtn.heightAnchor.constraint(equalToConstant: 24),
            
            workspaceStack.topAnchor.constraint(equalTo: segControl.bottomAnchor, constant: 10),
            workspaceStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            workspaceStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            workspaceStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10),
            
            newsStack.topAnchor.constraint(equalTo: segControl.bottomAnchor, constant: 10),
            newsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            newsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            newsStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10)
        ])
        
        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc
        suggestedPopover = popover
        
        let anchor = (suggestedTabsBtn.isHidden || suggestedTabsBtn.window == nil) ? extensionsButton! : suggestedTabsBtn!
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
    }
}
