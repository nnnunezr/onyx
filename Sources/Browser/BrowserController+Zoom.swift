import Cocoa
import WebKit

extension BrowserController {
    private static let siteZoomKey = "OnyxSiteZoom"

    /// Sets the page zoom and remembers it for the site (the host), not the tab.
    func setZoom(_ zoom: Double, for webView: WKWebView) {
        webView.pageZoom = SiteZoom.clamped(zoom)
        let saved = UserDefaults.standard.dictionary(forKey: Self.siteZoomKey) as? [String: Double] ?? [:]
        let updated = SiteZoom.updated(saved, host: webView.url?.host?.lowercased() ?? "", zoom: zoom)
        UserDefaults.standard.set(updated, forKey: Self.siteZoomKey)
    }

    /// Called when a page commits: the zoom follows the site, so moving between sites in one tab
    /// no longer carries the old site's zoom along.
    func applySiteZoom(to webView: WKWebView) {
        let saved = UserDefaults.standard.dictionary(forKey: Self.siteZoomKey) as? [String: Double]
        let zoom = saved?[webView.url?.host?.lowercased() ?? ""] ?? 1.0
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
    }
}
