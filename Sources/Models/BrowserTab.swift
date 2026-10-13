import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Browser Tab Model
class BrowserTab: NSObject {
    let id = UUID()
    var webView: WKWebView
    var title: String = "Onyx"
    var url: URL
    var favicon: NSImage?
    var estimatedProgress: Double = 0.0
    var isLoading: Bool = false
    var isObserved: Bool = false
    /// Set when this tab's WebContent process died while the tab was in the background.
    var needsReload: Bool = false
    /// Recent WebContent crashes, used to stop auto-reloading a page that keeps crashing.
    var recentCrashes: [Date] = []
    /// Address-bar input Onyx guessed was a site (`node.js` -> https://node.js). If that host does
    /// not exist, the input is searched instead.
    var typedGuess: (input: String, url: URL)?
    
    init(url: URL, configuration: WKWebViewConfiguration) {
        self.url = url
        self.title = url.isFileURL ? "Onyx" : (url.host ?? "New Tab")
        
        self.webView = OnyxWebView(frame: .zero, configuration: configuration)
        // Sized by autoresizing mask, not Auto Layout: element fullscreen (YouTube etc.) moves the
        // web view into WebKit's own window and sizes it by frame. Without a mask it collapses to
        // zero there and the fullscreen window stays black.
        self.webView.translatesAutoresizingMaskIntoConstraints = true
        self.webView.autoresizingMask = [.width, .height]
        self.webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) {
            self.webView.isInspectable = true
        }
        self.webView.wantsLayer = true
        self.webView.layer?.backgroundColor = NSColor(red: 7/255.0, green: 7/255.0, blue: 9/255.0, alpha: 1.0).cgColor
        if #available(macOS 12.0, *) {
            self.webView.underPageBackgroundColor = NSColor(red: 7/255.0, green: 7/255.0, blue: 9/255.0, alpha: 1.0)
        }
        PrivateWebKit.set(self.webView, key: "drawsBackground", setter: "_setDrawsBackground:", value: false)
        
        super.init()
    }
}
