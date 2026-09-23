import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Private Search & Bot Challenge Bypass Engine
    func purgeSearchBotAnomalyCookies(completion: (() -> Void)? = nil) {
        var stores: [WKWebsiteDataStore] = [WKWebsiteDataStore.default(), sharedConfiguration.websiteDataStore]
        stores.append(websiteDataStore(for: activeProfile))
        
        let group = DispatchGroup()
        for store in stores {
            group.enter()
            store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                let ddg = records.filter { $0.displayName.contains("duckduckgo") || $0.displayName.contains("duck.com") }
                if !ddg.isEmpty {
                    store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: ddg) {
                        group.leave()
                    }
                } else {
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            completion?()
        }
    }
    
    func handleBotChallenge(in webView: WKWebView) {
        let query = extractSearchQuery(from: webView.url)
        purgeSearchBotAnomalyCookies { [weak self] in
            DispatchQueue.main.async {
                guard self != nil else { return }
                if !query.isEmpty {
                    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    // In Onyx, bot verification is disabled for private browsing.
                    // Auto-bypass to private bot-free Brave Search
                    let bypassURL = URL(string: "https://search.brave.com/search?q=\(encoded)")!
                    webView.load(URLRequest(url: bypassURL))
                }
            }
        }
    }
    
    // MARK: - Global Ad & Tracker Blocker + YouTube Ad Engine
    
    func setupYouTubeAdBlocker(for config: WKWebViewConfiguration) {
        let userScript = WKUserScript(source: youTubeAdBlockerSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
    }

    func injectYouTubeAdBlocker(into webView: WKWebView) {
        guard let url = webView.url, let host = url.host?.lowercased(),
              host.contains("youtube.com") || host.contains("youtu.be") else { return }
        webView.evaluateJavaScript(youTubeAdBlockerSource, completionHandler: nil)
    }

    // High-speed native ad/tracker rule compilation with YouTube ad shield
    func setupAdBlocker() {
        setupYouTubeAdBlocker(for: sharedConfiguration)
        
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
        
        var rules: [[String: Any]] = blockedDomains.map { pattern in
            ["trigger": ["url-filter": ".*" + pattern + ".*"], "action": ["type": "block"]]
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
                self.sharedConfiguration.userContentController.add(ruleList)
                for (_, config) in self.profileConfigurations {
                    config.userContentController.add(ruleList)
                }
            }
        }
    }
}
