import Cocoa
import WebKit

// MARK: - Onyx Web View
/// WKWebView with a browser-style context menu. WebKit's stock menu is built for a single-window
/// app: "Open Link in New Window", "Search with Google" that leaves Onyx, downloads with no
/// "Save As…", and no bookmark or workspace actions. The page-side contextmenu script
/// (`onyxContextMenuScript`) tells us what was under the pointer just before the menu opens.
final class OnyxWebView: WKWebView {
    struct ContextInfo {
        var link: URL?
        var linkText: String
        var image: URL?
        var media: URL?
        var selection: String
        let time: Date
    }

    /// Set by the `onyxContextMenu` message, which WebKit delivers before it shows the menu.
    var contextInfo: ContextInfo?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        // Ignore info from an earlier right-click whose menu the page suppressed.
        let info = contextInfo.flatMap { Date().timeIntervalSince($0.time) < 2 ? $0 : nil }
        (uiDelegate as? BrowserController)?.customizeContextMenu(menu, in: self, info: info)
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        contextInfo = nil
    }
}

/// Runs in Onyx's own content world in every frame, so pages can neither see the listener nor
/// post fake context info. Capture phase on window: it runs before page handlers.
let onyxContextMenuScript = #"""
(function() {
    if (window.__onyxContextMenu) return;
    window.__onyxContextMenu = true;
    function abs(v) {
        if (!v) return '';
        if (typeof v !== 'string') v = v.baseVal || '';   // SVG <a>
        try { return new URL(v, document.baseURI).href; } catch (e) { return ''; }
    }
    window.addEventListener('contextmenu', function(e) {
        try {
            const path = e.composedPath ? e.composedPath() : [];
            let el = path.length ? path[0] : e.target;
            if (el && el.nodeType !== 1) el = el.parentElement;
            const find = (sel) => (el && el.closest) ? el.closest(sel) : null;
            const a = find('a[href], area[href]');
            const img = find('img');
            const media = find('video, audio');
            const sel = window.getSelection ? String(window.getSelection()) : '';
            window.webkit.messageHandlers.onyxContextMenu.postMessage({
                link: a ? abs(a.href) : '',
                linkText: a ? (a.innerText || a.getAttribute('aria-label') || '').trim().slice(0, 200) : '',
                image: img ? abs(img.currentSrc || img.src) : '',
                media: media ? abs(media.currentSrc || media.src) : '',
                selection: sel.trim().slice(0, 500)
            });
        } catch (err) {}
    }, true);
})();
"""#
