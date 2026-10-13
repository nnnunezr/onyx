import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Private Search & Bot Challenge Bypass Engine
    /// Clears DuckDuckGo's anomaly/bot-check state from the given store only.
    func purgeSearchBotAnomalyCookies(in store: WKWebsiteDataStore, completion: (() -> Void)? = nil) {
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let ddg = records.filter { $0.displayName.contains("duckduckgo") || $0.displayName.contains("duck.com") }
            guard !ddg.isEmpty else {
                completion?()
                return
            }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: ddg) {
                completion?()
            }
        }
    }
    
    func handleBotChallenge(in webView: WKWebView) {
        let query = extractSearchQuery(from: webView.url)
        guard !query.isEmpty else { return }
        purgeSearchBotAnomalyCookies(in: webView.configuration.websiteDataStore) { [weak webView] in
            DispatchQueue.main.async {
                var comps = URLComponents(string: "https://search.brave.com/search")!
                comps.queryItems = [URLQueryItem(name: "q", value: query)]
                // Bot verification wall hit: fall back to Brave Search for this query.
                if let bypassURL = comps.url {
                    webView?.load(URLRequest(url: bypassURL))
                }
            }
        }
    }
    
    // MARK: - Global Ad & Tracker Blocker + YouTube Ad Engine
    
    var isAdBlockEnabled: Bool {
        return UserDefaults.standard.object(forKey: "OnyxAdBlockEnabled") as? Bool ?? true
    }
    
    func setupYouTubeAdBlocker(for config: WKWebViewConfiguration) {
        guard isAdBlockEnabled else { return }
        let userScript = WKUserScript(source: youTubeAdBlockerSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
    }

    // High-speed native ad/tracker rule compilation with YouTube ad shield
    func setupAdBlocker() {
        let blockedDomains = [
            // Third-party Ad & Tracker Networks (Never block first-party youtube.com to prevent video player streaming breakage)
            "googleads\\.g\\.doubleclick\\.net",
            "pagead2\\.googlesyndication\\.com",
            "adservice\\.google\\.com",
            "static\\.doubleclick\\.net",
            "doubleclick\\.net",
            "google-analytics\\.com",
            "googlesyndication\\.com",
            "googleadservices\\.com",
            "adnxs\\.com",
            "scorecardresearch\\.com",
            "facebook\\.net",
            "connect\\.facebook\\.net",
            "hotjar\\.com",
            "clarity\\.ms",
            "criteo\\.com",
            "criteo\\.net",
            "outbrain\\.com",
            "taboola\\.com",
            "amazon-adsystem\\.com",
            "ads-twitter\\.com",
            "analytics\\.twitter\\.com",
            "pubmatic\\.com",
            "openx\\.net",
            "rubiconproject\\.com",
            "rubiconproject\\.net",
            "casalemedia\\.com",
            "indexww\\.com",
            "adsrvr\\.org",
            "popads\\.net",
            "popcash\\.net",
            "adsterra\\.com",
            "quantserve\\.com",
            "moatads\\.com",
            "serving-sys\\.com",
            "adroll\\.com",
            "adform\\.net",
            "smartadserver\\.com",
            "bidswitch\\.net",
            "media\\.net"
        ]
        
        // Anchored to the request's host (the domain or a subdomain of it), third-party loads only.
        // The old ".*domain.*" filters blocked any URL that merely contained a tracker name, such
        // as a search for "doubleclick.net", with no feedback.
        var rules: [[String: Any]] = blockedDomains.map { pattern in
            ["trigger": ["url-filter": "^[^:]+://+([^:/]+\\.)?" + pattern + "[:/]", "load-type": ["third-party"]],
             "action": ["type": "block"]]
        }
        
        // Native CSS display:none for YouTube promo / ad nodes
        let ytAdSelectors = "#masthead-ad, #player-ads, ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer, ytd-promoted-sparkles-web-renderer, ytd-promoted-video-renderer, ytd-compact-promoted-video-renderer, ytd-banner-promo-renderer, ytd-statement-banner-renderer, ytd-action-companion-ad-renderer, ytd-merch-shelf-renderer, .ytd-merch-shelf-renderer, .ytp-ad-overlay-container, .ytp-ad-message-container, .ytp-ad-preview-container, .ytp-ad-image-overlay, .ytp-ad-text-overlay, ytd-engagement-panel-section-list-renderer[target-id='engagement-panel-ads'], ytd-companion-slot-renderer, yt-mealbar-promo-renderer, ytd-mealbar-promo-renderer, ytd-enforcement-message-view-model"
        
        rules.append([
            "trigger": ["url-filter": ".*youtube\\.com.*"],
            "action": ["type": "css-display-none", "selector": ytAdSelectors]
        ])
        
        // Native CSS display:none for general web ad slots
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": [
                "type": "css-display-none",
                "selector": "[id^='google_ads_'], [id^='div-gpt-ad'], .adsbygoogle, .ad-banner, [data-ad-unit], [data-ad-slot]"
            ]
        ])
        
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "OnyxFastRules",
            encodedContentRuleList: jsonStr
        ) { [weak self] ruleList, error in
            if let ruleList = ruleList, let self = self {
                self.adBlockRuleList = ruleList
                self.applyAdBlockSetting()
            }
        }
    }
    
    /// Brings every workspace configuration in line with the stored ad-block preference:
    /// native rule list plus the YouTube script (user scripts are rebuilt so it can be dropped).
    func applyAdBlockSetting() {
        let enabled = isAdBlockEnabled
        for (_, config) in profileConfigurations {
            let ucc = config.userContentController
            if let ruleList = adBlockRuleList {
                ucc.remove(ruleList)
                if enabled { ucc.add(ruleList) }
            }
            ucc.removeAllUserScripts()
            installUserScripts(for: config)
        }
    }
    
    /// All per-configuration user scripts. Safe to call again after removeAllUserScripts().
    func installUserScripts(for config: WKWebViewConfiguration) {
        setupYouTubeAdBlocker(for: config)
        installSearchThemeScripts(for: config)
        // Onyx's own content world: pages cannot see or spoof the context-menu probe.
        config.userContentController.addUserScript(WKUserScript(source: onyxContextMenuScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
    }
}
