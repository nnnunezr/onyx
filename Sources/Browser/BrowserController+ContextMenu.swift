import Cocoa
import WebKit

// MARK: - Web Page Context Menu
/// Rebuilds WebKit's right-click menu into the one Safari and Chrome users expect: open in a new
/// tab (or another workspace), download with or without "Save As…", copy addresses, bookmark a
/// link, and search the selection with the Onyx search engine. WebKit items Onyx has no better
/// version of (Copy, Copy Image, Share, Look Up, Translate, Speech, Back/Forward/Reload, Inspect
/// Element, spelling) are kept as they are.
extension BrowserController {
    private enum WKItem {
        static let openLink = "WKMenuItemIdentifierOpenLinkInNewWindow"
        static let downloadLink = "WKMenuItemIdentifierDownloadLinkedFile"
        static let copyLink = "WKMenuItemIdentifierCopyLink"
        static let openImage = "WKMenuItemIdentifierOpenImageInNewWindow"
        static let downloadImage = "WKMenuItemIdentifierDownloadImage"
        static let copyImage = "WKMenuItemIdentifierCopyImage"
        static let openMedia = "WKMenuItemIdentifierOpenMediaInNewWindow"
        static let downloadMedia = "WKMenuItemIdentifierDownloadMedia"
        static let copyMedia = "WKMenuItemIdentifierCopyMediaLink"
        static let openFrame = "WKMenuItemIdentifierOpenFrameInNewWindow"
        static let searchWeb = "WKMenuItemIdentifierSearchWeb"
    }

    /// What a menu item acts on. The web view is weak: the tab may close while the menu is open.
    final class ContextTarget: NSObject {
        let url: URL
        let text: String
        weak var webView: WKWebView?
        init(url: URL, text: String = "", webView: WKWebView?) {
            self.url = url
            self.text = text
            self.webView = webView
        }
    }

    func handleContextMenuMessage(_ body: [String: Any], from webView: OnyxWebView) {
        func url(_ key: String) -> URL? {
            guard let s = body[key] as? String, !s.isEmpty else { return nil }
            return URL(string: s)
        }
        webView.contextInfo = OnyxWebView.ContextInfo(
            link: url("link"),
            linkText: body["linkText"] as? String ?? "",
            image: url("image"),
            media: url("media"),
            selection: body["selection"] as? String ?? "",
            time: Date()
        )
    }

    /// Only these are opened or downloaded by Onyx's own items. blob:, data: and javascript: links
    /// keep WebKit's native items, which resolve them inside the page's own process.
    private func isWebURL(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func customizeContextMenu(_ menu: NSMenu, in webView: OnyxWebView, info: OnyxWebView.ContextInfo?) {
        let original = menu.items
        let has = { (id: String) in original.contains { $0.identifier?.rawValue == id } }
        var replaced: Set<String> = []
        var result: [NSMenuItem] = []

        func item(_ title: String, _ action: Selector, _ target: ContextTarget?) -> NSMenuItem {
            let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
            mi.target = self
            mi.representedObject = target
            return mi
        }
        func separatorIfNeeded() {
            if let last = result.last, !last.isSeparatorItem { result.append(.separator()) }
        }

        // Link section, replacing WebKit's Open Link in New Window / Download Linked File / Copy Link.
        if let link = info?.link, isWebURL(link), has(WKItem.openLink) || has(WKItem.copyLink) {
            let t = ContextTarget(url: link, text: info?.linkText ?? "", webView: webView)
            result.append(item("Open Link in New Tab", #selector(ctxOpenInNewTab(_:)), t))
            result.append(item("Open Link in New Tab and Switch", #selector(ctxOpenInNewTabAndSwitch(_:)), t))
            let others = profiles.filter { $0.id != activeProfile.id }
            if !others.isEmpty {
                let sub = NSMenu()
                for p in others {
                    let mi = item(p.name, #selector(ctxOpenInWorkspace(_:)), t)
                    mi.tag = profiles.firstIndex(of: p) ?? -1
                    sub.addItem(mi)
                }
                let parent = NSMenuItem(title: "Open Link in Workspace", action: nil, keyEquivalent: "")
                parent.submenu = sub
                result.append(parent)
            }
            result.append(.separator())
            result.append(item("Download Linked File", #selector(ctxDownload(_:)), t))
            result.append(item("Download Linked File As…", #selector(ctxDownloadAs(_:)), t))
            result.append(.separator())
            result.append(item("Add Link to Bookmarks", #selector(ctxBookmarkLink(_:)), t))
            result.append(item("Copy Link", #selector(ctxCopyAddress(_:)), t))
            replaced.formUnion([WKItem.openLink, WKItem.downloadLink, WKItem.copyLink])
        }

        // Image section.
        if let image = info?.image, isWebURL(image), has(WKItem.openImage) || has(WKItem.downloadImage) {
            separatorIfNeeded()
            let t = ContextTarget(url: image, webView: webView)
            result.append(item("Open Image in New Tab", #selector(ctxOpenInNewTab(_:)), t))
            result.append(item("Save Image to Downloads", #selector(ctxDownload(_:)), t))
            result.append(item("Save Image As…", #selector(ctxDownloadAs(_:)), t))
            if let copy = original.first(where: { $0.identifier?.rawValue == WKItem.copyImage }) {
                result.append(copy)
            }
            result.append(item("Copy Image Address", #selector(ctxCopyAddress(_:)), t))
            replaced.formUnion([WKItem.openImage, WKItem.downloadImage, WKItem.copyImage])
        }

        // Video / audio section. Streaming players (YouTube) use blob: sources and keep WebKit's items.
        if let media = info?.media, isWebURL(media), has(WKItem.openMedia) || has(WKItem.downloadMedia) {
            separatorIfNeeded()
            let t = ContextTarget(url: media, webView: webView)
            result.append(item("Open Video in New Tab", #selector(ctxOpenInNewTab(_:)), t))
            result.append(item("Download Video", #selector(ctxDownload(_:)), t))
            result.append(item("Download Video As…", #selector(ctxDownloadAs(_:)), t))
            result.append(item("Copy Video Address", #selector(ctxCopyAddress(_:)), t))
            replaced.formUnion([WKItem.openMedia, WKItem.downloadMedia, WKItem.copyMedia])
        }

        if !result.isEmpty { separatorIfNeeded() }

        // Everything else in WebKit's order, with Onyx versions of the window-oriented items.
        for mi in original {
            let id = mi.identifier?.rawValue ?? ""
            if replaced.contains(id) { continue }
            switch id {
            case WKItem.searchWeb:
                let text = (info?.selection ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { result.append(mi); continue }
                let shown = text.count > 30 ? String(text.prefix(30)) + "…" : text
                let t = ContextTarget(url: webSearchURL(for: text), text: text, webView: webView)
                result.append(item("Search \(SearchEngines.displayName(SearchEngines.current)) for “\(shown)”", #selector(ctxOpenInNewTabAndSwitch(_:)), t))
            case WKItem.openLink, WKItem.openImage, WKItem.openMedia, WKItem.openFrame:
                // Non-web URL or no page info: WebKit's own action still works (it opens a tab
                // through createWebViewWith), it just needs the right name.
                mi.title = mi.title.replacingOccurrences(of: "New Window", with: "New Tab")
                result.append(mi)
            default:
                result.append(mi)
            }
        }

        // Drop doubled or edge separators left by the regrouping.
        var cleaned: [NSMenuItem] = []
        for mi in result {
            if mi.isSeparatorItem && (cleaned.isEmpty || cleaned.last?.isSeparatorItem == true) { continue }
            cleaned.append(mi)
        }
        while cleaned.last?.isSeparatorItem == true { cleaned.removeLast() }

        menu.removeAllItems()
        for mi in cleaned {
            mi.menu?.removeItem(mi)
            menu.addItem(mi)
        }
    }

    // MARK: - Context menu actions
    private func target(_ sender: Any?) -> ContextTarget? {
        return (sender as? NSMenuItem)?.representedObject as? ContextTarget
    }

    @objc func ctxOpenInNewTab(_ sender: NSMenuItem) {
        guard let t = target(sender) else { return }
        createNewTab(url: t.url, switchTo: false)
    }

    @objc func ctxOpenInNewTabAndSwitch(_ sender: NSMenuItem) {
        guard let t = target(sender) else { return }
        createNewTab(url: t.url, switchTo: true)
    }

    @objc func ctxOpenInWorkspace(_ sender: NSMenuItem) {
        guard let t = target(sender), profiles.indices.contains(sender.tag) else { return }
        switchToProfile(profiles[sender.tag])
        createNewTab(url: t.url, switchTo: true)
    }

    @objc func ctxDownload(_ sender: NSMenuItem) {
        guard let t = target(sender) else { return }
        startContextDownload(t, askForLocation: false)
    }

    @objc func ctxDownloadAs(_ sender: NSMenuItem) {
        guard let t = target(sender) else { return }
        startContextDownload(t, askForLocation: true)
    }

    /// Downloads through the page's web view so its cookies and workspace data store apply
    /// (signed-in Drive, Gmail and Canvas files need them).
    private func startContextDownload(_ t: ContextTarget, askForLocation: Bool) {
        let webView = t.webView ?? activeWebView
        var request = URLRequest(url: t.url)
        if let referrer = webView.url, isWebURL(referrer) {
            request.setValue(referrer.absoluteString, forHTTPHeaderField: "Referer")
        }
        webView.startDownload(using: request) { [weak self] download in
            guard let self = self else { return }
            download.delegate = self
            self.registerDownload(download: download, sourceURL: t.url)
            self.activeDownloads[download]?.asksForLocation = askForLocation
        }
    }

    @objc func ctxCopyAddress(_ sender: NSMenuItem) {
        guard let t = target(sender) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([t.url as NSURL])
        pb.setString(t.url.absoluteString, forType: .string)
    }

    @objc func ctxBookmarkLink(_ sender: NSMenuItem) {
        guard let t = target(sender) else { return }
        let urlStr = t.url.absoluteString
        guard !bookmarks.contains(where: { $0.urlString == urlStr }) else {
            showVaultToastHUD(icon: "bookmark.fill", title: "ALREADY BOOKMARKED", message: t.url.host ?? urlStr)
            return
        }
        let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = text.isEmpty ? (t.url.host ?? "Bookmark") : String(text.prefix(60))
        bookmarks.append(BookmarkItem(title: title, urlString: urlStr, iconName: iconNameForURL(urlStr)))
        saveBookmarks()
        renderBookmarks()
        showVaultToastHUD(icon: "bookmark.fill", title: "BOOKMARK ADDED", message: title)
    }
}
