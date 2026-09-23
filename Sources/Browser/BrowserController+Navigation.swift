import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Navigation & URL Handling
    func loadTabURL(tab: BrowserTab, url: URL) {
        let req = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        tab.url = url
        if isSettingsURL(url) {
            tab.title = "Settings"
            if let img = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                let icon = img.withSymbolConfiguration(cfg)
                tab.favicon = icon
                for subview in tabStack.arrangedSubviews {
                    if let tabItem = subview as? TabItemView, tabItem.tab.id == tab.id {
                        tabItem.updateFavicon(icon)
                    }
                }
            }
        } else if let host = url.host, !url.isFileURL {
            if let cached = FaviconManager.shared.cachedFavicon(for: host) {
                tab.favicon = cached
                for subview in tabStack.arrangedSubviews {
                    if let tabItem = subview as? TabItemView, tabItem.tab.id == tab.id {
                        tabItem.updateFavicon(cached)
                    }
                }
            } else {
                tab.favicon = nil
                for subview in tabStack.arrangedSubviews {
                    if let tabItem = subview as? TabItemView, tabItem.tab.id == tab.id {
                        tabItem.updateFavicon(nil)
                    }
                }
            }
        } else {
            tab.favicon = nil
            for subview in tabStack.arrangedSubviews {
                if let tabItem = subview as? TabItemView, tabItem.tab.id == tab.id {
                    tabItem.updateFavicon(nil)
                }
            }
        }
        if url.isFileURL {
            // Grant read access to the file's own folder only (bundled pages need their
            // sibling anime.min.js / logo.svg). Global file-URL privileges stay off.
            tab.webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            tab.webView.load(req)
        }
        
        if tab.id == activeTab.id {
            updateSearchField(url: url)
            if isSettingsURL(url) || (url.isFileURL && url.path.contains("startpage.html")) {
                searchThinkingOrb.stopAnimation()
                searchFaviconView.isHidden = false
                updateSearchFavicon(for: url)
            } else if isSearchURL(url) {
                searchThinkingOrb.stopAnimation()
                searchThinkingOrb.isHidden = true
                searchFaviconView.image = nil
                searchFaviconView.isHidden = true
            } else {
                let isResearch = isResearchURL(url)
                searchFaviconView.isHidden = true
                searchThinkingOrb.startAnimation(mode: isResearch ? .orbits : .orbits)
            }
            updateActiveBookmarkHighlight()
        }
    }
    
    func loadURL(_ url: URL) {
        loadTabURL(tab: activeTab, url: url)
    }
    
    func updateSearchField(url: URL) {
        if isSettingsURL(url) {
            searchField.stringValue = "onyx://settings"
            searchShortcutBadge.stringValue = "⌘,"
            searchShortcutBadge.isHidden = false
        } else if url.isFileURL && url.path.contains("startpage.html") {
            searchField.stringValue = ""
            searchShortcutBadge.stringValue = "⌘K"
            searchShortcutBadge.isHidden = false
            updateSearchPlaceholder()
        } else if isResearchURL(url) {
            let query = extractResearchQuery(from: url)
            if !query.isEmpty {
                searchField.stringValue = "✦ Onyx Research: " + query
            } else {
                searchField.stringValue = "✦ Onyx Research"
            }
            searchShortcutBadge.isHidden = true
        } else if isSearchURL(url) {
            let query = extractSearchQuery(from: url)
            searchField.stringValue = !query.isEmpty ? query : url.absoluteString
            searchShortcutBadge.isHidden = true
        } else {
            searchField.stringValue = url.absoluteString
            searchShortcutBadge.isHidden = true
        }
        updateSearchContainerGlow(for: searchField.stringValue)
    }
    
    func updateSearchContainerGlow(for text: String, focused: Bool? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isFocused = focused ?? ((window?.firstResponder as? NSTextView)?.delegate as? NSTextField === searchField)
        
        let borderColor: CGColor
        let shadowColor: CGColor
        let shadowOpacity: Float
        let shadowRadius: CGFloat
        
        if trimmed.hasPrefix("!r") || trimmed.hasPrefix("!ai") || trimmed.hasPrefix("✦ onyx research") {
            borderColor = NSColor(red: 56/255.0, green: 189/255.0, blue: 248/255.0, alpha: 0.85).cgColor
            shadowColor = NSColor(red: 56/255.0, green: 189/255.0, blue: 248/255.0, alpha: 0.50).cgColor
            shadowOpacity = 0.85
            shadowRadius = 12
        } else if trimmed.hasPrefix("!p") {
            borderColor = NSColor(red: 34/255.0, green: 211/255.0, blue: 238/255.0, alpha: 0.85).cgColor
            shadowColor = NSColor(red: 34/255.0, green: 211/255.0, blue: 238/255.0, alpha: 0.50).cgColor
            shadowOpacity = 0.85
            shadowRadius = 12
        } else if trimmed.hasPrefix("!g") {
            borderColor = NSColor(red: 66/255.0, green: 133/255.0, blue: 244/255.0, alpha: 0.85).cgColor
            shadowColor = NSColor(red: 66/255.0, green: 133/255.0, blue: 244/255.0, alpha: 0.50).cgColor
            shadowOpacity = 0.85
            shadowRadius = 12
        } else if trimmed.hasPrefix("!yt") {
            borderColor = NSColor(red: 255/255.0, green: 0/255.0, blue: 51/255.0, alpha: 0.85).cgColor
            shadowColor = NSColor(red: 255/255.0, green: 0/255.0, blue: 51/255.0, alpha: 0.50).cgColor
            shadowOpacity = 0.85
            shadowRadius = 12
        } else if trimmed.hasPrefix("!gh") {
            borderColor = NSColor(red: 168/255.0, green: 85/255.0, blue: 247/255.0, alpha: 0.85).cgColor
            shadowColor = NSColor(red: 168/255.0, green: 85/255.0, blue: 247/255.0, alpha: 0.50).cgColor
            shadowOpacity = 0.85
            shadowRadius = 12
        } else if trimmed.hasPrefix("!k") {
            borderColor = NSColor(red: 245/255.0, green: 158/255.0, blue: 11/255.0, alpha: 0.85).cgColor
            shadowColor = NSColor(red: 245/255.0, green: 158/255.0, blue: 11/255.0, alpha: 0.50).cgColor
            shadowOpacity = 0.85
            shadowRadius = 12
        } else if trimmed.hasPrefix("!w") {
            borderColor = NSColor(red: 148/255.0, green: 163/255.0, blue: 184/255.0, alpha: 0.85).cgColor
            shadowColor = NSColor(red: 148/255.0, green: 163/255.0, blue: 184/255.0, alpha: 0.50).cgColor
            shadowOpacity = 0.85
            shadowRadius = 12
        } else if isFocused {
            borderColor = NSColor(white: 1.0, alpha: 0.28).cgColor
            shadowColor = NSColor(white: 1.0, alpha: 0.15).cgColor
            shadowOpacity = 0.50
            shadowRadius = 8
        } else {
            borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            shadowColor = NSColor.clear.cgColor
            shadowOpacity = 0.0
            shadowRadius = 0
        }
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.searchContainer.layer?.borderColor = borderColor
            self.searchContainer.layer?.shadowColor = shadowColor
            self.searchContainer.layer?.shadowRadius = shadowRadius
            self.searchContainer.layer?.shadowOpacity = shadowOpacity
            if isFocused {
                self.searchContainer.layer?.backgroundColor = NSColor(red: 26/255.0, green: 26/255.0, blue: 30/255.0, alpha: 1.0).cgColor
            } else {
                self.searchContainer.layer?.backgroundColor = NSColor(red: 32/255.0, green: 32/255.0, blue: 36/255.0, alpha: 1.0).cgColor
            }
        }
    }
    
    // Update active site Favicon in search bar
    func updateSearchFavicon(for url: URL) {
        if isSettingsURL(url) {
            setSearchFaviconSymbol("gearshape.fill")
            return
        }
        if url.isFileURL || url.path.contains("startpage.html") {
            setSearchFaviconSymbol("sparkles")
            return
        }
        
        let urlString = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""
        
        // General search: Leave blank up there! No globe logo, no duck mascot!
        if isSearchURL(url) || host.contains("duckduckgo") || host.contains("duck.com") {
            searchFaviconView.image = nil
            searchFaviconView.isHidden = true
            return
        }
        
        if host.contains("duck.ai") || urlString.contains("ia=chat") {
            setSearchFaviconSymbol("brain")
            return
        }
        
        // Use real favicon if loaded or available in cache
        if let fav = activeTab.favicon {
            searchFaviconView.image = fav
            searchFaviconView.contentTintColor = nil
            searchFaviconView.isHidden = false
            return
        } else if !host.isEmpty, let cached = FaviconManager.shared.cachedFavicon(for: host) {
            searchFaviconView.image = cached
            searchFaviconView.contentTintColor = nil
            searchFaviconView.isHidden = false
            return
        }
        
        if host.contains("ninjatrader") {
            setSearchFaviconSymbol("chart.xyaxis.line")
        } else if host.contains("unapec") {
            setSearchFaviconSymbol("graduationcap")
        } else if host.contains("conflictly") {
            setSearchFaviconSymbol("bubble.left.and.bubble.right")
        } else if host.contains("tradesea") {
            setSearchFaviconSymbol("chart.line.uptrend.xyaxis")
        } else if host.contains("finviz") {
            setSearchFaviconSymbol("waveform.path.ecg")
        } else if host.contains("perplexity") {
            setSearchFaviconSymbol("sparkles")
        } else if host.contains("google") {
            setSearchFaviconSymbol("magnifyingglass")
        } else if host.contains("github") {
            setSearchFaviconSymbol("chevron.left.forwardslash.chevron.right")
        } else if host.contains("youtube") {
            setSearchFaviconSymbol("play.rectangle")
        } else if host.contains("wikipedia") {
            setSearchFaviconSymbol("book")
        } else {
            setSearchFaviconSymbol("globe")
        }
    }
    
    func setSearchFaviconSymbol(_ systemName: String) {
        if let img = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            searchFaviconView.image = img.withSymbolConfiguration(config)
            searchFaviconView.contentTintColor = NSColor(white: 0.70, alpha: 1.0)
            searchFaviconView.isHidden = false
        }
    }
    
    @objc func searchFieldSubmitted() {
        suggestedPopover?.performClose(nil)
        closeSuggestionsPopover()
        var query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        if query.hasPrefix("javascript:") {
            let script = String(query.dropFirst("javascript:".count))
            activeWebView.evaluateJavaScript(script, completionHandler: nil)
            return
        }
        
        if query.hasPrefix("✦ Onyx Research: ") {
            let actualQ = String(query.dropFirst("✦ Onyx Research: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !actualQ.isEmpty {
                query = "!r " + actualQ
            } else {
                return
            }
        } else if query == "✦ Onyx Research" {
            return
        } else if query.hasPrefix("✦ Search: ") {
            let actualQ = String(query.dropFirst("✦ Search: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !actualQ.isEmpty {
                query = actualQ
            } else {
                return
            }
        } else if query == "✦ Onyx Search" {
            return
        } else if query.hasPrefix("✦ ") {
            let actualQ = String(query.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !actualQ.isEmpty {
                query = actualQ
            }
        }
        
        let targetURL = resolveQuery(query)
        loadURL(targetURL)
        window?.makeFirstResponder(activeWebView)
    }
    
    func resolveQuery(_ rawInput: String) -> URL {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { return startPageURL }
        let trimmed = input
        let lower = trimmed.lowercased()
        if lower == "onyx://settings" || lower == "about:settings" || lower == "chrome://settings" || lower == "settings" {
            return settingsPageURL
        }
        if lower == "onyx://home" || lower == "onyx://newtab" || lower == "about:home" {
            return startPageURL
        }
        
        func encodeQuery(_ text: String) -> String {
            var cs = CharacterSet.urlQueryAllowed
            cs.remove(charactersIn: "&+=#?")
            return text.addingPercentEncoding(withAllowedCharacters: cs) ?? text
        }
        
        // Dedicated Deep Research Bangs (!r, !ai, !d)
        if input.hasPrefix("!r ") || input.hasPrefix("!ai ") {
            let q = encodeQuery(String(input.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            return URL(string: "https://duckduckgo.com/?q=\(q)&ia=chat")!
        } else if input == "!r" || input == "!ai" || input == "!d" {
            return URL(string: "https://duckduckgo.com/?q=&ia=chat")!
        } else if input.hasPrefix("!d ") {
            // DuckDuckGo dedicated AI Research Mode (Perplexity style)
            let q = encodeQuery(String(input.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            return URL(string: "https://duckduckgo.com/?q=\(q)&ia=chat")!
        } else if input.hasPrefix("!p ") {
            let q = encodeQuery(String(input.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            return URL(string: "https://www.perplexity.ai/search?q=\(q)")!
        } else if input.hasPrefix("!g ") {
            let q = encodeQuery(String(input.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            return URL(string: "https://www.google.com/search?q=\(q)")!
        } else if input.hasPrefix("!gh ") {
            let q = encodeQuery(String(input.dropFirst(4)).trimmingCharacters(in: .whitespaces))
            return URL(string: "https://github.com/search?q=\(q)")!
        } else if input.hasPrefix("!yt ") {
            let q = encodeQuery(String(input.dropFirst(4)).trimmingCharacters(in: .whitespaces))
            return URL(string: "https://www.youtube.com/results?search_query=\(q)")!
        } else if input.hasPrefix("!w ") {
            let q = encodeQuery(String(input.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            return URL(string: "https://en.wikipedia.org/wiki/Special:Search?search=\(q)")!
        } else if input.hasPrefix("!k ") {
            let q = encodeQuery(String(input.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            return URL(string: "https://kagi.com/search?q=\(q)")!
        } else if input.hasPrefix("!b ") {
            let q = encodeQuery(String(input.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            return URL(string: "https://search.brave.com/search?q=\(q)")!
        } else if input.hasPrefix("!lite ") || input.hasPrefix("!html ") {
            let q = encodeQuery(String(input.dropFirst(6)).trimmingCharacters(in: .whitespaces))
            return URL(string: "https://html.duckduckgo.com/html/?q=\(q)")!
        }
        
        // Direct local file URLs
        if input.hasPrefix("file://") {
            if let u = URL(string: input) { return u }
        } else if input.hasPrefix("/") {
            return URL(fileURLWithPath: input)
        }
        
        // Direct URLs
        if input.hasPrefix("http://") || input.hasPrefix("https://") {
            if let u = URL(string: input) { return u }
        }
        
        if input.contains(".") && !input.contains(" ") {
            if let u = URL(string: "https://" + input) { return u }
        }
        
        if input.hasPrefix("localhost:") || input == "localhost" {
            if let u = URL(string: "http://" + input) { return u }
        }
        
        // Automatic Research Intent Detection (Perplexity-style research behavior)
        let isResearchIntent = lower.hasSuffix("?") ||
                               lower.hasPrefix("how ") ||
                               lower.hasPrefix("what ") ||
                               lower.hasPrefix("why ") ||
                               lower.hasPrefix("explain ") ||
                               lower.hasPrefix("research ") ||
                               lower.hasPrefix("compare ") ||
                               lower.hasPrefix("analyze ") ||
                               lower.hasPrefix("who is ") ||
                               lower.hasPrefix("tell me about ")
        
        let q = encodeQuery(input)
        if isResearchIntent {
            return URL(string: "https://duckduckgo.com/?q=\(q)&ia=chat")!
        }
        
        let defaultEngine = UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo"
        switch defaultEngine.lowercased() {
        case "google":
            return URL(string: "https://www.google.com/search?q=\(q)")!
        case "brave":
            return URL(string: "https://search.brave.com/search?q=\(q)")!
        case "perplexity":
            return URL(string: "https://www.perplexity.ai/search?q=\(q)")!
        case "kagi":
            return URL(string: "https://kagi.com/search?q=\(q)")!
        case "bing":
            return URL(string: "https://www.bing.com/search?q=\(q)")!
        default:
            return URL(string: "https://duckduckgo.com/?q=\(q)")!
        }
    }
    
    // MARK: - Navigation Transitions & Creative Animations
    func animateButtonBounce(_ button: NSButton, direction: CGFloat) {
        let spring = CAKeyframeAnimation(keyPath: "transform")
        let t0 = CATransform3DIdentity
        let t1 = CATransform3DTranslate(CATransform3DMakeScale(0.88, 0.88, 1.0), direction * 3.0, 0, 0)
        let t2 = CATransform3DTranslate(CATransform3DMakeScale(1.06, 1.06, 1.0), direction * -1.0, 0, 0)
        let t3 = CATransform3DIdentity
        spring.values = [NSValue(caTransform3D: t0), NSValue(caTransform3D: t1), NSValue(caTransform3D: t2), NSValue(caTransform3D: t3)]
        spring.keyTimes = [0.0, 0.35, 0.70, 1.0]
        spring.duration = 0.26
        spring.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        button.layer?.add(spring, forKey: "buttonBounce")
    }
    
    func animateNavigationTransition(direction: NavigationDirection) {
        // 1. Tactile button bounce
        if direction == .back {
            animateButtonBounce(backButton, direction: -1.0)
        } else {
            animateButtonBounce(forwardButton, direction: 1.0)
        }
        
        // 2. Directional edge glow flash with active profile accent color
        edgeGlowView?.flash(edge: direction, color: activeProfile.color)
        
        // 3. Web View slide & cross-fade transition
        let deltaX: CGFloat = (direction == .back) ? -28.0 : 28.0
        
        let slideAnim = CABasicAnimation(keyPath: "transform.translation.x")
        slideAnim.fromValue = deltaX
        slideAnim.toValue = 0
        
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 0.35
        fadeAnim.toValue = 1.0
        
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.99
        scaleAnim.toValue = 1.0
        
        let group = CAAnimationGroup()
        group.animations = [slideAnim, fadeAnim, scaleAnim]
        group.duration = 0.24
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        
        activeWebView.layer?.add(group, forKey: "navTransition")
        
        // 4. Trigger thinking orb wave
        if !searchThinkingOrb.isHidden {
            searchThinkingOrb.startAnimation(mode: .orbits)
        }
    }
    
    @objc func goBack() {
        guard activeWebView.canGoBack else { return }
        animateNavigationTransition(direction: .back)
        activeWebView.goBack()
    }
    
    @objc func goForward() {
        guard activeWebView.canGoForward else { return }
        animateNavigationTransition(direction: .forward)
        activeWebView.goForward()
    }
    
    @objc func reloadPage() {
        if activeWebView.isLoading {
            activeWebView.stopLoading()
        } else {
            activeWebView.reload()
        }
    }
    
    @objc func openStartPage() {
        loadURL(startPageURL)
    }
}
