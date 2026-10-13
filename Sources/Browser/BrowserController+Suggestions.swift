import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Browsing Suggestions Methods
    func setupSuggestionsPopover() {
        guard suggestionsPopover == nil else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        let controller = NSViewController()
        let view = BrowsingSuggestionsView(frame: NSRect(x: 0, y: 0, width: 560, height: 260))
        view.onSelect = { [weak self] item in
            self?.executeSelectedSuggestion(item)
        }
        view.onSwitchEngine = { [weak self] engine in
            self?.setLiveSearchEngine(engine)
        }
        controller.view = view
        popover.contentViewController = controller
        self.suggestionsView = view
        self.suggestionsPopover = popover
    }

    func presentSuggestionsPopover(items: [BrowsingSuggestionItem]) {
        guard !items.isEmpty, let window = self.window, window.isKeyWindow else {
            closeSuggestionsPopover()
            return
        }
        
        if suggestionsPopover == nil {
            setupSuggestionsPopover()
        }
        
        suggestionsView?.updateItems(items)
        
        let popoverWidth = max(520, searchContainer.bounds.width)
        let popoverHeight = min(360, CGFloat(items.count) * 36 + 48)
        suggestionsPopover?.contentSize = NSSize(width: popoverWidth, height: popoverHeight)
        
        if suggestionsPopover?.isShown != true {
            suggestionsPopover?.show(relativeTo: searchContainer.bounds, of: searchContainer, preferredEdge: .maxY)
        }
    }

    func closeSuggestionsPopover() {
        activeSuggestionTask?.cancel()
        suggestionsPopover?.performClose(nil)
    }

    func executeSelectedSuggestion(_ item: BrowsingSuggestionItem) {
        closeSuggestionsPopover()
        if let urlStr = item.urlString, let url = URL(string: urlStr) {
            loadURL(url)
        } else if let q = item.searchQuery {
            let url = resolveQuery(q)
            loadURL(url)
        } else {
            let url = resolveQuery(item.title)
            loadURL(url)
        }
        window?.makeFirstResponder(activeWebView)
    }

    func handleSearchFieldInputChanged(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            closeSuggestionsPopover()
            return
        }
        
        if trimmed.hasPrefix("javascript:") {
            closeSuggestionsPopover()
            return
        }
        
        let defaultEngine = UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo"
        let engineDisplayName: String
        switch defaultEngine.lowercased() {
        case "google": engineDisplayName = "Google"
        case "brave": engineDisplayName = "Brave"
        case "perplexity": engineDisplayName = "Perplexity"
        case "kagi": engineDisplayName = "Kagi"
        case "bing": engineDisplayName = "Bing"
        default: engineDisplayName = "DuckDuckGo"
        }
        
        // 1. Instant Local Suggestions
        var instantItems: [BrowsingSuggestionItem] = []
        
        // Default search item
        instantItems.append(BrowsingSuggestionItem(
            type: .search,
            title: "✦ Search \(engineDisplayName): \"\(trimmed)\"",
            subtitle: "Search Engine",
            iconName: "magnifyingglass",
            urlString: nil,
            searchQuery: trimmed,
            isDirectNav: false
        ))
        
        // Direct domain navigation
        let lower = trimmed.lowercased()
        let popularDomains = [
            "apple": ("apple.com", "Apple"),
            "github": ("github.com", "GitHub"),
            "google": ("google.com", "Google"),
            "youtube": ("youtube.com", "YouTube"),
            "reddit": ("reddit.com", "Reddit"),
            "twitter": ("twitter.com", "Twitter / X"),
            "x": ("x.com", "X"),
            "wikipedia": ("wikipedia.org", "Wikipedia"),
            "amazon": ("amazon.com", "Amazon"),
            "figma": ("figma.com", "Figma"),
            "notion": ("notion.so", "Notion"),
            "ninjatrader": ("web.ninjatrader.com", "NinjaTrader Web"),
            "canvas": ("canvas.unapec.edu.do", "Canvas Tablero"),
            "conflictly": ("conflictly.app", "Conflictly Dashboard"),
            "tradesea": ("app.tradesea.ai", "Tradesea")
        ]
        
        if let (dom, name) = popularDomains[lower] {
            instantItems.append(BrowsingSuggestionItem(
                type: .domain,
                title: "\(name) — \(dom)",
                subtitle: "Direct Navigation",
                iconName: "globe",
                urlString: "https://\(dom)",
                searchQuery: nil,
                isDirectNav: true
            ))
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            let directUrl = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
            instantItems.append(BrowsingSuggestionItem(
                type: .domain,
                title: "Go to \(trimmed)",
                subtitle: "Open URL",
                iconName: "globe",
                urlString: directUrl,
                searchQuery: nil,
                isDirectNav: true
            ))
        }
        
        // Bang shortcuts
        if trimmed.hasPrefix("!") {
            let bangs = [
                ("!r", "AI Deep Research Mode", "sparkles"),
                ("!ai", "AI Conversational Research", "sparkles"),
                ("!d", "Duck.ai Dedicated Research", "sparkles"),
                ("!p", "Perplexity AI Search", "sparkles"),
                ("!g", "Google Search", "magnifyingglass"),
                ("!yt", "YouTube Ad-Free Video Search", "play.rectangle.fill"),
                ("!gh", "GitHub Code & Repositories", "chevron.left.forwardslash.chevron.right"),
                ("!w", "Wikipedia Encyclopedia", "book.closed.fill"),
                ("!k", "Kagi Ad-Free Search", "shield.fill"),
                ("!b", "Brave Private Search", "shield.checkerboard")
            ]
            for (bang, desc, icon) in bangs {
                if bang.hasPrefix(lower) || lower == "!" {
                    let actualQ = String(trimmed.dropFirst(bang.count)).trimmingCharacters(in: .whitespaces)
                    let titleText = actualQ.isEmpty ? "\(bang) · \(desc)" : "\(bang) \(actualQ) · \(desc)"
                    instantItems.append(BrowsingSuggestionItem(
                        type: .bang,
                        title: titleText,
                        subtitle: "Bang Shortcut",
                        iconName: icon,
                        urlString: nil,
                        searchQuery: trimmed,
                        isDirectNav: false
                    ))
                }
            }
        }
        
        // Bookmarks matches
        for bm in bookmarks {
            if bm.title.localizedCaseInsensitiveContains(trimmed) || bm.domain.localizedCaseInsensitiveContains(trimmed) {
                instantItems.append(BrowsingSuggestionItem(
                    type: .bookmark,
                    title: bm.title,
                    subtitle: bm.domain,
                    iconName: bm.iconName,
                    urlString: bm.urlString,
                    searchQuery: nil,
                    isDirectNav: true
                ))
                if instantItems.count >= 4 { break }
            }
        }
        
        // History matches
        for h in browsingHistory {
            if h.title.localizedCaseInsensitiveContains(trimmed) || h.urlString.localizedCaseInsensitiveContains(trimmed) {
                if !instantItems.contains(where: { $0.urlString == h.urlString }) {
                    instantItems.append(BrowsingSuggestionItem(
                        type: .history,
                        title: h.title,
                        subtitle: URL(string: h.urlString)?.host ?? h.urlString,
                        iconName: "clock.arrow.circlepath",
                        urlString: h.urlString,
                        searchQuery: nil,
                        isDirectNav: true
                    ))
                }
                if instantItems.count >= 6 { break }
            }
        }
        
        // Present instant suggestions immediately
        presentSuggestionsPopover(items: instantItems)
        
        // 2. Fetch live suggestions asynchronously
        activeSuggestionTask?.cancel()
        // .urlQueryAllowed leaves & + # = unescaped, which would cut "c++" or "a&b" short on the server.
        var queryChars = CharacterSet.urlQueryAllowed
        queryChars.remove(charactersIn: "&+=#?")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: queryChars),
              let fetchURL = URL(string: "https://duckduckgo.com/ac/?q=\(encoded)&type=list") else { return }
        
        let task = URLSession.shared.dataTask(with: fetchURL) { [weak self] data, response, error in
            guard let self = self, error == nil, let data = data else { return }
            
            guard let jsonArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any],
                  jsonArray.count >= 2,
                  let suggestions = jsonArray[1] as? [String] else { return }
            
            DispatchQueue.main.async {
                guard self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                
                var combined = instantItems
                if combined.count > 3 {
                    combined = Array(combined.prefix(3))
                }
                
                for phrase in suggestions.prefix(5) {
                    if !combined.contains(where: { $0.title == phrase || $0.searchQuery == phrase }) {
                        combined.append(BrowsingSuggestionItem(
                            type: .search,
                            title: phrase,
                            subtitle: "\(engineDisplayName) Suggestion",
                            iconName: "magnifyingglass",
                            urlString: nil,
                            searchQuery: phrase,
                            isDirectNav: false
                        ))
                    }
                }
                
                self.presentSuggestionsPopover(items: combined)
            }
        }
        activeSuggestionTask = task
        task.resume()
    }

    func fetchSuggestionsForWeb(query: String, reqId: String, from webView: WKWebView?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var comps = URLComponents(string: "https://duckduckgo.com/ac/") else {
            webView?.evaluateJavaScript("window.onOnyxSuggestionsReceived && window.onOnyxSuggestionsReceived(\(JS.string(reqId)), []);", completionHandler: nil)
            return
        }
        comps.queryItems = [URLQueryItem(name: "q", value: trimmed), URLQueryItem(name: "type", value: "list")]
        // URLQueryItem leaves "+" and "&"-adjacent characters ambiguous for some servers; encode "+" explicitly.
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let fetchURL = comps.url else { return }
        
        URLSession.shared.dataTask(with: fetchURL) { [weak webView] data, _, error in
            var jsonString = "[]"
            if error == nil, let data = data,
               let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any],
               array.count >= 2,
               let suggestions = array[1] as? [String],
               let outData = try? JSONSerialization.data(withJSONObject: suggestions, options: []),
               let str = String(data: outData, encoding: .utf8) {
                jsonString = str
            }
            DispatchQueue.main.async {
                webView?.evaluateJavaScript("window.onOnyxSuggestionsReceived && window.onOnyxSuggestionsReceived(\(JS.string(reqId)), \(jsonString));", completionHandler: nil)
            }
        }.resume()
    }
}
