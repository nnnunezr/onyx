import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Main Browser Window Controller
class BrowserController: NSWindowController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, NSTextFieldDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    // Downloads Management
    var downloads: [OnyxDownloadItem] = []
    var activeDownloads: [WKDownload: OnyxDownloadItem] = [:]
    var downloadsButton: DownloadsNavButton!
    var downloadsPopover: NSPopover?
    var downloadProgressTimer: Timer?
    var activeDownloadHUD: DownloadNotificationHUD?
    
    // Password Vault & Security Management
    var passwordStore = OnyxPasswordStore.shared
    var passwordsButton: PasswordsNavButton!
    var passwordsPopover: NSPopover?
    var passwordSearchField: NSTextField?
    var passwordRowsStack: NSStackView?
    var passwordCountLabel: NSTextField?
    var activeToastHUD: OnyxToastHUD?
    var findBar: OnyxFindBar?
    var findMatchIndex = 0
    var findMatchCount = 0
    var lastFindQuery = ""
    var activeSavePromptHUD: OnyxSavePasswordHUD?
    
    // Toolbar Extensions & Pinning System
    var extensionsButton: NavIconButton!
    var extensionsPopover: NSPopover?
    var extensionsStack: NSStackView!
    var trailingControlsStack: NSStackView!
    
    
    // Profile Management (Multi-Profile System with Isolated DataStores)
    var profiles: [BrowserProfile] = [
        BrowserProfile(id: "personal", name: "Personal", iconName: "person.crop.circle", colorHex: "#FFFFFF", isDefault: true),
        BrowserProfile(id: "research", name: "Research & AI", iconName: "sparkles", colorHex: "#E2E8F0", isDefault: false),
        BrowserProfile(id: "trading", name: "Markets & Trading", iconName: "chart.xyaxis.line", colorHex: "#34D399", isDefault: false),
        BrowserProfile(id: "campus", name: "Campus / Academic", iconName: "graduationcap", colorHex: "#FBBF24", isDefault: false)
    ]
    var activeProfile: BrowserProfile = BrowserProfile(id: "personal", name: "Personal", iconName: "person.crop.circle", colorHex: "#FFFFFF", isDefault: true)
    var profileTabs: [String: [BrowserTab]] = [:]
    /// Most recent last. Reopened with ⇧⌘T into the workspace the tab was closed in.
    var recentlyClosedTabs: [(url: URL, title: String, profileID: String)] = []
    var profileActiveIndices: [String: Int] = [:]
    var profileConfigurations: [String: WKWebViewConfiguration] = [:]
    var profileButton: ProfilePillButton!
    var profilePopover: NSPopover?
    var edgeGlowView: DirectionalEdgeGlowView!
    var adBlockRuleList: WKContentRuleList?
    var sessionSaveWorkItem: DispatchWorkItem?
    /// Set by File > Reopen Last Session: workspaces opened later this run restore from the
    /// previous run's snapshot even when the startup mode is not Restore.
    var reopenLastSessionRequested = false
    /// Problems found while loading stored data, shown as toasts once the window exists.
    var startupNotices: [String] = []
    /// True only when stored history was unreadable AND its backup failed: never overwrite it then.
    var historySavingBlocked = false
    /// The sheet currently shown for a page's alert()/confirm()/prompt(), and the page that opened it,
    /// so Cmd+W can still close a tab stuck in a dialog loop.
    weak var activeJSDialogSheet: NSWindow?
    weak var activeJSDialogWebView: WKWebView?
    /// When recent alert()/confirm()/prompt() dialogs were shown, to cap a page that spams them.
    var recentJSDialogTimes: [Date] = []
    
    // Tab Management (Resilient Index Guarding)
    var tabs: [BrowserTab] = []
    var activeTabIndex: Int = 0
    var activeTab: BrowserTab {
        if activeTabIndex >= 0 && activeTabIndex < tabs.count {
            return tabs[activeTabIndex]
        }
        if let first = tabs.first {
            return first
        }
        return BrowserTab(url: startPageURL, configuration: configuration(for: activeProfile))
    }
    var activeWebView: WKWebView { return activeTab.webView }
    
    var webContainerView: NSView!
    var searchContainer: NSView!
    var searchField: CustomSearchBar!
    var searchFaviconView: NSImageView!
    var searchThinkingOrb: ThinkingOrbView!
    var searchShortcutBadge: NSTextField!
    var backButton: NavIconButton!
    var forwardButton: NavIconButton!
    var reloadButton: NavIconButton!
    var topBar: NSView!
    var topBarSeparator: NSBox!
    
    // Tab Bar
    var tabBar: TabBarView!
    var tabStack: NSStackView!
    var tabScrollView: TabStripScrollView!
    var tabStripWidthConstraint: NSLayoutConstraint!
    var newTabBtn: NavIconButton!
    var suggestedTabsBtn: NavIconButton!
    var suggestedPopover: NSPopover?
    var tabSeparator: NSBox!
    
    // Browsing Suggestions & History
    var browsingHistory: [BrowsingHistoryItem] = []
    var suggestionsPopover: NSPopover?
    var suggestionsView: BrowsingSuggestionsView?
    var activeSuggestionTask: URLSessionDataTask?
    
    // Bookmarks Bar
    var bookmarksBar: BookmarksBarView!
    var bookmarksStack: NSStackView!
    var manageBookmarksBtn: NavIconButton!
    var bookmarksBarHeightConstraint: NSLayoutConstraint!
    var bookmarksSeparator: NSBox!
    var bookmarkButtons: [BookmarkButton] = []
    weak var hoveredBookmarkButton: BookmarkButton?
    var bookmarkManagerPopover: NSPopover?
    var bookmarkManagerStack: NSStackView?
    var bookmarkManagerCountLabel: NSTextField?
    
    var progressBar: NSBox!
    var progressConstraint: NSLayoutConstraint!
    var shieldButton: NavIconButton!
    
    static let defaultBookmarks: [BookmarkItem] = [
        BookmarkItem(title: "NinjaTrader", shortcut: "⌘1", urlString: "https://web.ninjatrader.com/trading-mode", domain: "ninjatrader.com", iconName: "chart.line.uptrend.xyaxis"),
        BookmarkItem(title: "Tablero", shortcut: "⌘2", urlString: "https://canvas.unapec.edu.do/", domain: "unapec.edu.do", iconName: "graduationcap"),
        BookmarkItem(title: "Conflictly", shortcut: "⌘3", urlString: "https://www.conflictly.app/dashboard", domain: "conflictly.app", iconName: "bubble.left.and.bubble.right"),
        BookmarkItem(title: "Tradesea", shortcut: "⌘4", urlString: "https://app.tradesea.ai/trade", domain: "tradesea.ai", iconName: "chart.xyaxis.line"),
        BookmarkItem(title: "Finviz", shortcut: "⌘5", urlString: "https://finviz.com/", domain: "finviz.com", iconName: "waveform.path.ecg"),
        BookmarkItem(title: "GitHub", shortcut: "⌘6", urlString: "https://github.com", domain: "github.com", iconName: "chevron.left.forwardslash.chevron.right")
    ]
    var bookmarks: [BookmarkItem] = []
    
    let startPageURL: URL = {
        if let bundleURL = Bundle.main.url(forResource: "startpage", withExtension: "html") {
            return bundleURL
        }
        return BrowserController.devResourceURL("startpage.html")
    }()
    
    let settingsPageURL: URL = {
        if let bundleURL = Bundle.main.url(forResource: "settings", withExtension: "html") {
            return bundleURL
        }
        return BrowserController.devResourceURL("settings.html")
    }()
    
    /// Fallback for running the raw `onyx` binary outside the .app bundle: resources sit next to the executable.
    static func devResourceURL(_ name: String) -> URL {
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        return exeDir.appendingPathComponent(name)
    }
    
    /// True only for Onyx's own bundled pages (start page & settings). These are the
    /// only documents allowed to drive privileged native bridges.
    func isInternalPageURL(_ url: URL?) -> Bool {
        guard let url = url, url.isFileURL else { return false }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path == startPageURL.standardizedFileURL.resolvingSymlinksInPath().path ||
               path == settingsPageURL.standardizedFileURL.resolvingSymlinksInPath().path
    }
    
    func isStartPageURL(_ url: URL?) -> Bool {
        guard let url = url, url.isFileURL else { return false }
        return url.standardizedFileURL.resolvingSymlinksInPath().path == startPageURL.standardizedFileURL.resolvingSymlinksInPath().path
    }
    
    func isSettingsURL(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        let str = url.absoluteString.lowercased()
        if str.hasPrefix("onyx://settings") ||
           str.hasPrefix("about:settings") ||
           str.hasPrefix("chrome://settings") {
            return true
        }
        if url.isFileURL && url.lastPathComponent.lowercased() == "settings.html" {
            return true
        }
        return false
    }
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1280, height: 850),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 900, height: 650)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 22/255.0, green: 22/255.0, blue: 25/255.0, alpha: 1.0)
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        
        loadSavedProfiles()
        loadSavedBookmarks()
        loadBrowsingHistory()
        setupAdBlocker()
        setupUI()
        setupShortcuts()
        NotificationCenter.default.addObserver(forName: OnyxPasswordStore.didLoadNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if !self.passwordStore.isLoaded {
                // A failed Keychain read used to be invisible (and every save silently refused).
                self.showVaultToastHUD(icon: "lock.trianglebadge.exclamationmark", title: "VAULT LOCKED",
                                       message: self.vaultLockedMessage())
            }
            self.updatePasswordsBadge(for: self.activeWebView.url)
            if self.passwordsPopover?.isShown == true {
                self.refreshPasswordManagerList(query: self.passwordSearchField?.stringValue ?? "")
            }
        }
        
        snapshotLastSessionAtLaunch()
        showStartupNotices()
        
        // Open initial tab(s) based on user preference
        let startupMode = UserDefaults.standard.string(forKey: "OnyxStartupBehavior") ?? "startpage"
        if startupMode == "restore", restoreSessionTabs(for: activeProfile) {
            return
        }
        if startupMode == "blank" {
            createNewTab(url: URL(string: "about:blank")!)
        } else {
            createNewTab(url: startPageURL)
        }
    }
    
    // KVO for progress, title, url
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let webView = object as? WKWebView else { return }
        guard let matchingTab = tabs.first(where: { $0.webView == webView }) else { return }
        
        if keyPath == "estimatedProgress" {
            matchingTab.estimatedProgress = webView.estimatedProgress
            if matchingTab.id == activeTab.id {
                let progress = webView.estimatedProgress
                if let parentBar = progressBar.superview {
                    var targetWidth = CGFloat(progress) * parentBar.bounds.width
                    // Never move backward mid-load (the start trickle may be ahead of WebKit).
                    if progress < 1.0 { targetWidth = max(targetWidth, self.progressConstraint.constant) }
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.18
                        Motion.prepare(ctx)
                        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                        self.progressConstraint.animator().constant = targetWidth
                    }
                    if progress >= 1.0 {
                        NSAnimationContext.runAnimationGroup({ ctx in
                            ctx.duration = 0.25
                            Motion.prepare(ctx)
                            self.progressBar.animator().alphaValue = 0.0
                        }, completionHandler: {
                            self.progressBar.isHidden = true
                            self.progressBar.alphaValue = 1.0
                            self.progressConstraint.constant = 0
                        })
                    } else {
                        self.progressBar.isHidden = false
                        self.progressBar.alphaValue = 1.0
                    }
                }
            }
        } else if keyPath == "title" {
            if isSettingsURL(matchingTab.url) {
                matchingTab.title = "Settings"
                if matchingTab.id == activeTab.id {
                    self.window?.title = "Settings — Onyx"
                }
                if matchingTab.favicon == nil {
                    if let img = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings") {
                        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                        matchingTab.favicon = img.withSymbolConfiguration(cfg)
                    }
                }
                renderTabs()
            } else if isResearchURL(matchingTab.url) {
                let q = extractResearchQuery(from: matchingTab.url)
                let cleanTitle = q.isEmpty ? "✦ Onyx Research" : "✦ \(q)"
                matchingTab.title = cleanTitle
                if matchingTab.id == activeTab.id {
                    self.window?.title = cleanTitle
                }
                refreshTabTitle(matchingTab)
            } else if isSearchURL(matchingTab.url) {
                let q = extractSearchQuery(from: matchingTab.url)
                var rawTitle = webView.title ?? ""
                rawTitle = rawTitle.replacingOccurrences(of: " at DuckDuckGo", with: "")
                                   .replacingOccurrences(of: " - DuckDuckGo", with: "")
                                   .replacingOccurrences(of: "DuckDuckGo — ", with: "")
                                   .replacingOccurrences(of: "DuckDuckGo", with: "")
                                   .trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle: String
                if !q.isEmpty {
                    displayTitle = "✦ \(q) — Search"
                } else if !rawTitle.isEmpty {
                    displayTitle = "✦ \(rawTitle) — Search"
                } else {
                    displayTitle = "✦ Onyx Search"
                }
                matchingTab.title = displayTitle
                if matchingTab.id == activeTab.id {
                    self.window?.title = displayTitle
                }
                refreshTabTitle(matchingTab)
            } else if let title = webView.title, !title.isEmpty {
                var cleanTitle = title
                if cleanTitle.contains("DuckDuckGo") {
                    cleanTitle = cleanTitle.replacingOccurrences(of: " at DuckDuckGo", with: "")
                                           .replacingOccurrences(of: " - DuckDuckGo", with: "")
                                           .replacingOccurrences(of: "DuckDuckGo — ", with: "")
                                           .replacingOccurrences(of: "DuckDuckGo", with: "")
                                           .trimmingCharacters(in: .whitespacesAndNewlines)
                    cleanTitle = "✦ \(cleanTitle) — Search"
                }
                matchingTab.title = cleanTitle
                if matchingTab.id == activeTab.id {
                    self.window?.title = cleanTitle
                }
                refreshTabTitle(matchingTab)
            }
        } else if keyPath == "URL" {
            if let url = webView.url {
                let oldHost = matchingTab.url.host
                matchingTab.url = url
                if isSettingsURL(url) {
                    matchingTab.title = "Settings"
                    if let img = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings") {
                        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                        matchingTab.favicon = img.withSymbolConfiguration(cfg)
                    }
                }
                if matchingTab.id == activeTab.id {
                    // A page changing its own URL (autoplay, SPA routing) must not wipe what is being typed.
                    let isEditingAddress = (window?.firstResponder as? NSTextView)?.delegate === searchField
                    if !isEditingAddress { updateSearchField(url: url) }
                    updateSearchFavicon(for: url)
                    backButton.isEnabled = webView.canGoBack
                    forwardButton.isEnabled = webView.canGoForward
                    updateActiveBookmarkHighlight()
                }
                if let newHost = url.host, !url.isFileURL {
                    if let cached = FaviconManager.shared.cachedFavicon(for: newHost) {
                        updateTabFavicon(for: matchingTab, favicon: cached)
                    } else if oldHost != newHost {
                        matchingTab.favicon = nil
                        for subview in tabStack.arrangedSubviews {
                            if let tabItem = subview as? TabItemView, tabItem.tab.id == matchingTab.id {
                                tabItem.updateFavicon(nil)
                            }
                        }
                    }
                }
            }
        }
    }
}
