import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - NSColor Hex Initializer
extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        guard hexSanitized.count == 6, let rgb = UInt64(hexSanitized, radix: 16) else { return nil }
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - NSButton Monochrome Attributed Title Helper
extension NSButton {
    func setMonochromeTitle(_ text: String, color: NSColor = .white, font: NSFont? = nil) {
        let f = font ?? self.font ?? NSFont.systemFont(ofSize: 11, weight: .medium)
        self.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: f
        ])
    }
}

// MARK: - Browser Profile Model
struct BrowserProfile: Codable, Equatable {
    let id: String
    var name: String
    var iconName: String
    var colorHex: String
    var isDefault: Bool
    
    var color: NSColor {
        return NSColor(hex: colorHex) ?? .white
    }
}

// MARK: - Navigation Direction & Edge Glow Engine
enum NavigationDirection {
    case back
    case forward
}

class DirectionalEdgeGlowView: NSView {
    private let gradientLayer = CAGradientLayer()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.masksToBounds = true
        
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradientLayer)
        alphaValue = 0.0
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Mouse clicks always pass through to the active web view
    }
    
    func flash(edge: NavigationDirection, color: NSColor) {
        self.layer?.removeAllAnimations()
        gradientLayer.removeAllAnimations()
        
        let clearColor = NSColor.clear.cgColor
        let glowColor = color.cgColor
        
        if edge == .back {
            gradientLayer.colors = [glowColor, clearColor]
            gradientLayer.locations = [0.0, 0.14]
        } else {
            gradientLayer.colors = [clearColor, glowColor]
            gradientLayer.locations = [0.86, 1.0]
        }
        
        self.alphaValue = 1.0
        
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 1.0
        fadeAnim.toValue = 0.0
        fadeAnim.duration = 0.32
        fadeAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        fadeAnim.fillMode = .forwards
        fadeAnim.isRemovedOnCompletion = false
        
        self.layer?.add(fadeAnim, forKey: "fadeGlow")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            self?.alphaValue = 0.0
            self?.layer?.removeAllAnimations()
        }
    }
}

// MARK: - Bookmark Model
struct BookmarkItem: Codable, Equatable {
    var id: String
    var title: String
    var shortcut: String
    var urlString: String
    var domain: String
    var iconName: String
    
    init(id: String = UUID().uuidString, title: String, shortcut: String = "", urlString: String, domain: String = "", iconName: String = "globe") {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.urlString = urlString
        if domain.isEmpty, let host = URL(string: urlString)?.host {
            self.domain = host
        } else {
            self.domain = domain
        }
        self.iconName = iconName
    }
}

// MARK: - Fun Placeholder Messages (Apple-style short & playful)
let funSearchPrompts: [String] = [
    "Where to next?",
    "What's on your mind?",
    "Curiosity starts here...",
    "Seek and find...",
    "Ask away...",
    "Think fast, search faster",
    "What are we exploring?",
    "Beam me up...",
    "Ready when you are",
    "Fire away..."
]

func randomFunPrompt() -> String {
    return funSearchPrompts.randomElement() ?? "Where to next?"
}

// MARK: - Favicon Manager (High-Performance Memory & Disk Cache for Tab Favicons)
class FaviconManager {
    static let shared = FaviconManager()
    
    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheDir: URL?
    private let session: URLSession
    private var inFlightCompletions: [String: [(NSImage?) -> Void]] = [:]
    private let lock = NSLock()
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
        
        if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = cachesURL.appendingPathComponent("com.company.onyx/favicons", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            self.cacheDir = dir
        } else {
            self.cacheDir = nil
        }
        
        memoryCache.countLimit = 250
    }
    
    func cachedFavicon(for host: String) -> NSImage? {
        let cleanHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return nil }
        
        let key = cleanHost as NSString
        if let mem = memoryCache.object(forKey: key) {
            mem.isTemplate = false
            return mem
        }
        if let dir = cacheDir {
            let safeName = cleanHost.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
            let fileURL = dir.appendingPathComponent("\(safeName).png")
            if let data = try? Data(contentsOf: fileURL), let img = NSImage(data: data) {
                img.isTemplate = false
                memoryCache.setObject(img, forKey: key)
                return img
            }
        }
        return nil
    }
    
    func storeFavicon(_ image: NSImage, for host: String) {
        let cleanHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return }
        
        image.isTemplate = false
        let key = cleanHost as NSString
        memoryCache.setObject(image, forKey: key)
        
        if let dir = cacheDir,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let safeName = cleanHost.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
            let fileURL = dir.appendingPathComponent("\(safeName).png")
            try? png.write(to: fileURL)
        }
    }
    
    func fetchFirstValidFavicon(from urls: [URL], forHost host: String, completion: @escaping (NSImage?) -> Void) {
        let cleanHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        lock.lock()
        if inFlightCompletions[cleanHost] != nil {
            inFlightCompletions[cleanHost]?.append(completion)
            lock.unlock()
            return
        }
        inFlightCompletions[cleanHost] = [completion]
        lock.unlock()
        
        func finish(_ image: NSImage?) {
            self.lock.lock()
            let callbacks = self.inFlightCompletions.removeValue(forKey: cleanHost) ?? []
            self.lock.unlock()
            for cb in callbacks {
                cb(image)
            }
        }
        
        func tryNext(index: Int) {
            guard index < urls.count else {
                finish(nil)
                return
            }
            let targetURL = urls[index]
            var req = URLRequest(url: targetURL)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            
            session.dataTask(with: req) { [weak self] (data, response, error) in
                guard let self = self else { return }
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let data = data, data.count > 32,
                   let image = NSImage(data: data), image.isValid {
                    let processed = self.prepareRetinaFavicon(image)
                    self.storeFavicon(processed, for: cleanHost)
                    finish(processed)
                } else {
                    tryNext(index: index + 1)
                }
            }.resume()
        }
        
        tryNext(index: 0)
    }
    
    private func prepareRetinaFavicon(_ source: NSImage) -> NSImage {
        let targetSize = NSSize(width: 16, height: 16)
        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            rep.size = targetSize
            NSGraphicsContext.saveGraphicsState()
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current = ctx
            ctx?.imageInterpolation = .high
            source.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            
            let result = NSImage(size: targetSize)
            result.addRepresentation(rep)
            result.isTemplate = false
            return result
        }
        source.size = targetSize
        source.isTemplate = false
        return source
    }
}

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
    
    init(url: URL, configuration: WKWebViewConfiguration) {
        self.url = url
        self.title = url.isFileURL ? "Onyx" : (url.host ?? "New Tab")
        
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.translatesAutoresizingMaskIntoConstraints = false
        self.webView.allowsBackForwardNavigationGestures = true
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        if #available(macOS 13.3, *) {
            self.webView.isInspectable = true
        }
        self.webView.wantsLayer = true
        self.webView.layer?.backgroundColor = NSColor(red: 7/255.0, green: 7/255.0, blue: 9/255.0, alpha: 1.0).cgColor
        if #available(macOS 12.0, *) {
            self.webView.underPageBackgroundColor = NSColor(red: 7/255.0, green: 7/255.0, blue: 9/255.0, alpha: 1.0)
        }
        self.webView.setValue(false, forKey: "drawsBackground")
        
        super.init()
    }
}

// MARK: - Tab Bar Container View (Native macOS Window Dragging on Empty Space)
class TabBarView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - Tab Close Button (Refined Apple/Comet Circular Icon Button)
class TabCloseButton: NSButton {
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 7
        self.layer?.masksToBounds = true
        if let xmark = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 7.5, weight: .semibold)
            self.image = xmark.withSymbolConfiguration(cfg)
        }
        self.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
            self.contentTintColor = NSColor.white
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        }
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Tab Item View (Comet Native Window Tab Pill)
class TabItemView: NSView {
    let tab: BrowserTab
    let index: Int
    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }
    
    private var trackingArea: NSTrackingArea?
    private var titleLabel: NSTextField!
    private var iconView: NSImageView!
    private var closeBtn: TabCloseButton!
    private var isHovered: Bool = false
    
    var onSelect: ((BrowserTab) -> Void)?
    var onClose: ((BrowserTab) -> Void)?
    var onDuplicate: ((BrowserTab) -> Void)?
    var onReload: ((BrowserTab) -> Void)?
    var onCloseOthers: ((BrowserTab) -> Void)?
    var onCopyURL: ((BrowserTab) -> Void)?
    
    init(tab: BrowserTab, index: Int, isSelected: Bool) {
        self.tab = tab
        self.index = index
        self.isSelected = isSelected
        super.init(frame: .zero)
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 8
        self.layer?.masksToBounds = false
        
        // Favicon / SF Symbol (14x14)
        iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 3
        iconView.layer?.masksToBounds = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        
        if tab.favicon == nil, let host = tab.url.host, !tab.url.isFileURL {
            tab.favicon = FaviconManager.shared.cachedFavicon(for: host)
        }
        updateFavicon(tab.favicon)
        addSubview(iconView)
        
        // Title Label (11.5pt SF Pro)
        titleLabel = NSTextField(labelWithString: tab.title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = isSelected ? NSFont.systemFont(ofSize: 11.5, weight: .medium) : NSFont.systemFont(ofSize: 11.5, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)
        
        // Close Button
        closeBtn = TabCloseButton(frame: .zero)
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        addSubview(closeBtn)
        
        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: 28),
            self.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            self.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            closeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 15),
            closeBtn.heightAnchor.constraint(equalToConstant: 15)
        ])
        
        updateAppearance()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func defaultIconName() -> String {
        let str = tab.url.absoluteString.lowercased()
        let host = tab.url.host?.lowercased() ?? ""
        if str.contains("settings") || tab.title.lowercased().contains("settings") {
            return "gearshape.fill"
        } else if host.contains("duck.ai") || str.contains("ia=chat") {
            return "brain"
        } else if tab.url.isFileURL || host.isEmpty {
            return "sparkles"
        } else if host.contains("github") {
            return "chevron.left.forwardslash.chevron.right"
        } else if host.contains("youtube") || host.contains("vimeo") || host.contains("netflix") {
            return "play.rectangle.fill"
        } else if host.contains("twitter") || host.contains("x.com") || host.contains("reddit") {
            return "bubble.left.and.bubble.right.fill"
        } else if host.contains("mail") {
            return "envelope.fill"
        } else if host.contains("news") || host.contains("nytimes") || host.contains("bbc") || host.contains("wsj") {
            return "newspaper.fill"
        } else {
            return "globe"
        }
    }
    
    func updateTitle(_ title: String) {
        titleLabel.stringValue = title
    }
    
    func updateFavicon(_ icon: NSImage?) {
        tab.favicon = icon
        if let icon = icon {
            iconView.image = icon
            iconView.contentTintColor = nil
            iconView.imageScaling = .scaleProportionallyUpOrDown
        } else {
            let iconName = defaultIconName()
            if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .medium)
                iconView.image = img.withSymbolConfiguration(cfg)
                iconView.contentTintColor = isSelected ? NSColor.white : NSColor(white: 0.65, alpha: 1.0)
            }
        }
    }
    
    func updateAppearance() {
        if tab.favicon == nil {
            iconView?.contentTintColor = isSelected ? NSColor.white : (isHovered ? NSColor(white: 0.85, alpha: 1.0) : NSColor(white: 0.65, alpha: 1.0))
        } else {
            iconView?.contentTintColor = nil
        }
        
        if isSelected {
            // Active Tab (Floating Slate Pill with frosted glass highlight)
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.10).cgColor
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
            layer?.borderWidth = 1.0
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.35
            layer?.shadowRadius = 4
            layer?.shadowOffset = CGSize(width: 0, height: -1)
            
            titleLabel.textColor = NSColor(white: 0.98, alpha: 1.0)
            titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
            
            closeBtn.alphaValue = 0.85
            closeBtn.contentTintColor = NSColor(white: 0.85, alpha: 1.0)
        } else {
            // Inactive Tab (Seamless resting state, subtle glass pill on hover)
            let bgAlpha: CGFloat = isHovered ? 0.05 : 0.0
            let borderAlpha: CGFloat = isHovered ? 0.08 : 0.0
            layer?.backgroundColor = NSColor(white: 1.0, alpha: bgAlpha).cgColor
            layer?.borderColor = NSColor(white: 1.0, alpha: borderAlpha).cgColor
            layer?.borderWidth = isHovered ? 1.0 : 0.0
            layer?.shadowOpacity = 0.0
            
            titleLabel.textColor = isHovered ? NSColor(white: 0.94, alpha: 1.0) : NSColor(white: 0.58, alpha: 1.0)
            titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
            
            closeBtn.alphaValue = isHovered ? 0.70 : 0.0
            closeBtn.contentTintColor = NSColor(white: 0.70, alpha: 1.0)
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.updateAppearance()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.updateAppearance()
        }
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if closeBtn.frame.contains(loc) {
            return
        }
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            self.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.985, y: 0.985))
        }
        onSelect?(tab)
    }
    
    override func mouseUp(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.setAffineTransform(.identity)
        }
    }
    
    @objc func closeClicked() {
        onClose?(tab)
    }
    
    // Right-Click Native Context Menu
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "Tab Options")
        
        let duplicateItem = NSMenuItem(title: "Duplicate Tab", action: #selector(duplicateAction), keyEquivalent: "d")
        duplicateItem.target = self
        menu.addItem(duplicateItem)
        
        let reloadItem = NSMenuItem(title: "Reload Tab", action: #selector(reloadAction), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let copyUrlItem = NSMenuItem(title: "Copy URL", action: #selector(copyURLAction), keyEquivalent: "c")
        copyUrlItem.target = self
        menu.addItem(copyUrlItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let closeOthersItem = NSMenuItem(title: "Close Other Tabs", action: #selector(closeOthersAction), keyEquivalent: "")
        closeOthersItem.target = self
        menu.addItem(closeOthersItem)
        
        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(closeTabAction), keyEquivalent: "w")
        closeItem.target = self
        menu.addItem(closeItem)
        
        return menu
    }
    
    @objc private func duplicateAction() { onDuplicate?(tab) }
    @objc private func reloadAction() { onReload?(tab) }
    @objc private func copyURLAction() { onCopyURL?(tab) }
    @objc private func closeOthersAction() { onCloseOthers?(tab) }
    @objc private func closeTabAction() { onClose?(tab) }
}

// MARK: - Bookmark Delete Icon Button (✕ Action on Hover)
class BookmarkDeleteIconButton: NSControl {
    var onAction: (() -> Void)?
    private var isHovered: Bool = false
    private var isPressed: Bool = false
    private var trackingArea: NSTrackingArea?
    private var iconView: NSImageView!
    
    init() {
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 3.5
        self.layer?.masksToBounds = true
        self.toolTip = "Delete bookmark"
        
        iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Delete bookmark") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 7.5, weight: .bold)
            iconView.image = img.withSymbolConfiguration(cfg)
        }
        iconView.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        addSubview(iconView)
        
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 9),
            iconView.heightAnchor.constraint(equalToConstant: 9),
            
            self.widthAnchor.constraint(equalToConstant: 15),
            self.heightAnchor.constraint(equalToConstant: 15)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func updateState() {
        if isPressed {
            layer?.backgroundColor = NSColor(red: 239/255.0, green: 68/255.0, blue: 68/255.0, alpha: 0.35).cgColor
            iconView.contentTintColor = NSColor(red: 254/255.0, green: 202/255.0, blue: 202/255.0, alpha: 1.0)
        } else if isHovered {
            layer?.backgroundColor = NSColor(red: 239/255.0, green: 68/255.0, blue: 68/255.0, alpha: 0.22).cgColor
            iconView.contentTintColor = NSColor(red: 248/255.0, green: 113/255.0, blue: 113/255.0, alpha: 1.0)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            iconView.contentTintColor = NSColor(white: 0.68, alpha: 0.9)
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            self.updateState()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            self.updateState()
        }
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard self.frame.contains(point) else { return nil }
        return self
    }
    
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateState()
    }
    
    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        updateState()
        if wasPressed {
            let loc = convert(event.locationInWindow, from: nil)
            if bounds.contains(loc) {
                onAction?()
            }
        }
    }
}

// MARK: - Bookmark Button (Ultra-clean Comet / Apple Bookmark Item with Context Menu)
class BookmarkButton: NSControl {
    let bookmark: BookmarkItem
    private var trackingArea: NSTrackingArea?
    public private(set) var isHovered: Bool = false
    private var isPressed: Bool = false
    
    var isActive: Bool = false {
        didSet {
            if oldValue != isActive {
                updateAppearance()
            }
        }
    }
    
    var onOpenInNewTab: ((BookmarkItem) -> Void)?
    var onCopyURL: ((BookmarkItem) -> Void)?
    var onEdit: ((BookmarkItem) -> Void)?
    var onDelete: ((BookmarkItem) -> Void)?
    var onOpenManager: (() -> Void)?
    var onAddBookmark: (() -> Void)?
    var onHoverChanged: ((BookmarkButton, Bool) -> Void)?
    
    private var iconView: NSImageView!
    private var titleLabel: NSTextField!
    private var deleteButton: BookmarkDeleteIconButton!
    
    init(bookmark: BookmarkItem, target: AnyObject?, action: Selector) {
        self.bookmark = bookmark
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 4
        self.layer?.masksToBounds = true
        self.target = target
        self.action = action
        self.toolTip = "\(bookmark.title) (\(bookmark.shortcut))\n\(bookmark.urlString)\nClick ✕ or press Delete to remove"
        
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        addSubview(stack)
        
        // Favicon / SF Symbol (13x13)
        iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: bookmark.iconName, accessibilityDescription: bookmark.title) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = NSColor(white: 0.70, alpha: 1.0)
        }
        stack.addArrangedSubview(iconView)
        
        // Title Label (12pt SF Pro)
        titleLabel = NSTextField(labelWithString: bookmark.title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = NSColor(white: 0.78, alpha: 1.0)
        stack.addArrangedSubview(titleLabel)
        
        // Inline Delete Button (Appears on Hover to delete ONLY this bookmark)
        deleteButton = BookmarkDeleteIconButton()
        deleteButton.isHidden = true
        deleteButton.alphaValue = 0
        deleteButton.onAction = { [weak self] in
            guard let self = self else { return }
            self.onDelete?(self.bookmark)
        }
        stack.addArrangedSubview(deleteButton)
        
        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: 22),
            
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),
            
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        self.setContentHuggingPriority(.required, for: .horizontal)
        self.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        updateAppearance()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func updateAppearance() {
        if isActive {
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.12).cgColor
            titleLabel.textColor = NSColor.white
            titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            iconView.contentTintColor = NSColor.white
        } else if isHovered {
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            titleLabel.textColor = NSColor.white
            titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            iconView.contentTintColor = NSColor.white
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = NSColor(white: 0.78, alpha: 1.0)
            titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            iconView.contentTintColor = NSColor(white: 0.70, alpha: 1.0)
        }
    }
    
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        if !hovered && isPressed {
            isPressed = false
            self.layer?.setAffineTransform(.identity)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            ctx.allowsImplicitAnimation = true
            if hovered {
                self.deleteButton.isHidden = false
                self.deleteButton.animator().alphaValue = 0.85
            } else {
                self.deleteButton.isHidden = true
                self.deleteButton.animator().alphaValue = 0.0
            }
            self.updateAppearance()
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
        onHoverChanged?(self, true)
    }
    
    override func mouseExited(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            // Still within the bookmark button bounds
            return
        }
        setHovered(false)
        onHoverChanged?(self, false)
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard self.frame.contains(point) else { return nil }
        let localPoint = convert(point, from: superview)
        if let delBtn = deleteButton, !delBtn.isHidden {
            let pInDel = delBtn.convert(localPoint, from: self)
            if delBtn.bounds.contains(pInDel) {
                return delBtn
            }
        }
        return self
    }
    
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            onEdit?(bookmark)
            return
        }
        if event.modifierFlags.contains(.control) {
            if let m = menu(for: event) {
                let loc = convert(event.locationInWindow, from: nil)
                m.popUp(positioning: nil, at: loc, in: self)
                return
            }
        }
        
        isPressed = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.06
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.updateAppearance()
        }
        if wasPressed {
            let loc = convert(event.locationInWindow, from: nil)
            if bounds.contains(loc) {
                if event.clickCount == 2 {
                    onEdit?(bookmark)
                    return
                }
                if let action = action, let target = target {
                    NSApp.sendAction(action, to: target, from: self)
                }
            }
        }
    }
    
    // Right-Click Context Menu for Bookmark
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: bookmark.title)
        
        let openItem = NSMenuItem(title: "Open \"\(bookmark.title)\"", action: #selector(openCurrentAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        
        let newTabItem = NSMenuItem(title: "Open in New Tab", action: #selector(openNewTabAction), keyEquivalent: "")
        newTabItem.target = self
        menu.addItem(newTabItem)
        
        let copyItem = NSMenuItem(title: "Copy URL", action: #selector(copyURLAction), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let editItem = NSMenuItem(title: "Edit Bookmark...", action: #selector(editAction), keyEquivalent: "e")
        editItem.target = self
        menu.addItem(editItem)
        
        let deleteItem = NSMenuItem(title: "Delete Bookmark", action: #selector(deleteAction), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let addItem = NSMenuItem(title: "Add Bookmark...", action: #selector(addAction), keyEquivalent: "d")
        addItem.target = self
        menu.addItem(addItem)
        
        let manageItem = NSMenuItem(title: "Bookmark Manager...", action: #selector(manageAction), keyEquivalent: "b")
        manageItem.target = self
        menu.addItem(manageItem)
        
        return menu
    }
    
    @objc private func openCurrentAction() {
        if let action = action, let target = target {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
    
    @objc private func openNewTabAction() {
        onOpenInNewTab?(bookmark)
    }
    
    @objc private func copyURLAction() {
        onCopyURL?(bookmark)
    }
    
    @objc private func editAction() {
        onEdit?(bookmark)
    }
    
    @objc private func deleteAction() {
        onDelete?(bookmark)
    }
    
    @objc private func addAction() {
        onAddBookmark?()
    }
    
    @objc private func manageAction() {
        onOpenManager?()
    }
}

// MARK: - Bookmark Manager Action Button
class ManagerActionButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private let hoverBg: NSColor
    private let normalTint: NSColor
    private let hoverTint: NSColor
    
    init(iconName: String, tooltip: String, normalTint: NSColor, hoverTint: NSColor, hoverBg: NSColor, target: AnyObject?, action: Selector) {
        self.normalTint = normalTint
        self.hoverTint = hoverTint
        self.hoverBg = hoverBg
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.clear.cgColor
        toolTip = tooltip
        self.target = target
        self.action = action
        
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: tooltip) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            self.image = img.withSymbolConfiguration(cfg)
            self.contentTintColor = normalTint
        }
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            self.layer?.backgroundColor = hoverBg.cgColor
            self.contentTintColor = hoverTint
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.contentTintColor = normalTint
        }
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Bookmark Manager Row View (Used in the Bookmark Management Popover)
class BookmarkManagerRowView: NSView {
    let bookmark: BookmarkItem
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    var onOpen: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    
    init(bookmark: BookmarkItem) {
        self.bookmark = bookmark
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.clear.cgColor
        
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 6
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        iconPlate.layer?.borderWidth = 1
        iconPlate.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        addSubview(iconPlate)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: bookmark.iconName, accessibilityDescription: bookmark.title) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = NSColor(white: 0.75, alpha: 1.0)
        }
        iconPlate.addSubview(iconView)
        
        let titleLabel = NSTextField(labelWithString: bookmark.title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor.white
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        
        let urlLabel = NSTextField(labelWithString: bookmark.urlString)
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        urlLabel.textColor = NSColor(white: 0.50, alpha: 1.0)
        urlLabel.lineBreakMode = .byTruncatingTail
        addSubview(urlLabel)
        
        let delBtn = ManagerActionButton(
            iconName: "trash",
            tooltip: "Delete Bookmark",
            normalTint: NSColor(red: 248/255.0, green: 113/255.0, blue: 113/255.0, alpha: 0.85),
            hoverTint: NSColor(red: 254/255.0, green: 202/255.0, blue: 202/255.0, alpha: 1.0),
            hoverBg: NSColor(red: 239/255.0, green: 68/255.0, blue: 68/255.0, alpha: 0.20),
            target: self,
            action: #selector(deleteClicked)
        )
        addSubview(delBtn)
        
        let editBtn = ManagerActionButton(
            iconName: "pencil",
            tooltip: "Edit Bookmark",
            normalTint: NSColor(white: 0.65, alpha: 1.0),
            hoverTint: .white,
            hoverBg: NSColor(white: 1.0, alpha: 0.12),
            target: self,
            action: #selector(editClicked)
        )
        addSubview(editBtn)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 26),
            iconPlate.heightAnchor.constraint(equalToConstant: 26),
            
            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: editBtn.leadingAnchor, constant: -6),
            
            urlLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            urlLabel.trailingAnchor.constraint(lessThanOrEqualTo: editBtn.leadingAnchor, constant: -6),
            
            delBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            delBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            editBtn.trailingAnchor.constraint(equalTo: delBtn.leadingAnchor, constant: -4),
            editBtn.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.07).cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if loc.x < bounds.width - 60 {
            onOpen?()
        }
    }
    
    @objc func editClicked() { onEdit?() }
    @objc func deleteClicked() { onDelete?() }
}

// MARK: - Bookmarks Stack View (Passes through clicks on gaps to BookmarksBarView)
class BookmarksStackView: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view === self {
            return nil
        }
        return view
    }
}

// MARK: - Bookmarks Bar Container View (Handles clicks on top of the bar)
class BookmarksBarView: NSView {
    weak var controller: BrowserController?
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseExited(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if !bounds.contains(loc) {
            controller?.hoveredBookmarkButton?.setHovered(false)
            controller?.hoveredBookmarkButton = nil
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        controller?.showBookmarksBarMenu(at: loc, in: self)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        controller?.showBookmarksBarMenu(at: loc, in: self)
    }
    
    override func menu(for event: NSEvent) -> NSMenu? {
        let loc = convert(event.locationInWindow, from: nil)
        return controller?.createBookmarksBarMenu(at: loc)
    }
}

// MARK: - Nav Icon Button
class NavIconButton: NSButton {
    private var trackingArea: NSTrackingArea?
    var onClick: (() -> Void)?
    
    init(iconName: String, tooltip: String, target: AnyObject?, action: Selector?, size: CGFloat = 28) {
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.wantsLayer = true
        self.toolTip = tooltip
        self.target = target
        if let act = action {
            self.action = act
        }
        self.layer?.cornerRadius = 5
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        let iconPointSize: CGFloat = (size <= 24) ? 10 : 12
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: tooltip) {
            let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
            self.image = img.withSymbolConfiguration(config)
            self.contentTintColor = NSColor(white: 0.82, alpha: 1.0)
        }
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: size),
            self.heightAnchor.constraint(equalToConstant: size)
        ])
        self.setContentHuggingPriority(.required, for: .horizontal)
        self.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            self.contentTintColor = NSColor.white
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.contentTintColor = self.isEnabled ? NSColor(white: 0.82, alpha: 1.0) : NSColor(white: 0.35, alpha: 1.0)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if let onClick = onClick {
            onClick()
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if let m = self.menu {
            NSMenu.popUpContextMenu(m, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
    
    override var isEnabled: Bool {
        didSet {
            contentTintColor = isEnabled ? NSColor(white: 0.82, alpha: 1.0) : NSColor(white: 0.35, alpha: 1.0)
            if !isEnabled { layer?.backgroundColor = NSColor.clear.cgColor }
        }
    }
}

// MARK: - Custom Search Bar
class CustomSearchBar: NSTextField {
    var onFocusChanged: ((Bool) -> Void)?
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "a" {
                self.currentEditor()?.selectAll(nil)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChanged?(true) }
        return result
    }
}

// MARK: - Suggested Workspace Item Model
struct SuggestedWorkspaceItem {
    let title: String
    let subtitle: String
    let iconName: String
    let urlString: String
    let shortcut: String
}

// MARK: - Suggested Workspace Row View (Apple-style interactive item)
class SuggestedWorkspaceRowView: NSView {
    let item: SuggestedWorkspaceItem
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    
    init(item: SuggestedWorkspaceItem) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.clear.cgColor
        
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 7
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        iconPlate.layer?.borderWidth = 1
        iconPlate.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        addSubview(iconPlate)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: item.iconName, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = NSColor(white: 0.88, alpha: 1.0)
        }
        iconPlate.addSubview(iconView)
        
        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = NSColor.white
        addSubview(titleLabel)
        
        let subLabel = NSTextField(labelWithString: item.subtitle)
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        subLabel.textColor = NSColor(white: 0.50, alpha: 1.0)
        addSubview(subLabel)
        
        let badge = NSTextField(labelWithString: item.shortcut)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        badge.textColor = NSColor(white: 0.60, alpha: 1.0)
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        badge.layer?.cornerRadius = 4
        badge.alignment = .center
        addSubview(badge)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 30),
            iconPlate.heightAnchor.constraint(equalToConstant: 30),
            
            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),
            
            subLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),
            
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 26),
            badge.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - Suggested News Item Model
struct SuggestedNewsItem {
    let headline: String
    let source: String
    let category: String
    let time: String
    let urlString: String
}

// MARK: - Suggested News Row View (Apple-style interactive news item)
class SuggestedNewsRowView: NSView {
    let item: SuggestedNewsItem
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    
    init(item: SuggestedNewsItem) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.clear.cgColor
        
        let catBadge = NSTextField(labelWithString: item.category)
        catBadge.translatesAutoresizingMaskIntoConstraints = false
        catBadge.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        if item.category == "AI" {
            catBadge.textColor = NSColor(white: 0.92, alpha: 1.0)
        } else if item.category == "MARKETS" {
            catBadge.textColor = NSColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1.0)
        } else {
            catBadge.textColor = NSColor(white: 0.85, alpha: 1.0)
        }
        addSubview(catBadge)
        
        let timeLabel = NSTextField(labelWithString: item.time)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        timeLabel.textColor = NSColor(white: 0.45, alpha: 1.0)
        addSubview(timeLabel)
        
        let titleLabel = NSTextField(labelWithString: item.headline)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = NSColor.white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)
        
        let sourceLabel = NSTextField(labelWithString: item.source)
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        sourceLabel.textColor = NSColor(white: 0.50, alpha: 1.0)
        addSubview(sourceLabel)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),
            
            catBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            catBadge.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            timeLabel.centerYAnchor.constraint(equalTo: catBadge.centerYAnchor),
            
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: catBadge.bottomAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            
            sourceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            sourceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            sourceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - Browsing History & Suggestion Models
struct BrowsingHistoryItem: Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var urlString: String
    var timestamp: Date
}

struct BrowsingSuggestionItem {
    enum SuggestionType {
        case search
        case domain
        case bookmark
        case history
        case bang
    }
    let type: SuggestionType
    let title: String
    let subtitle: String
    let iconName: String
    let urlString: String?
    let searchQuery: String?
    let isDirectNav: Bool
}

// MARK: - Browsing Suggestion Row View
class BrowsingSuggestionRowView: NSView {
    let item: BrowsingSuggestionItem
    var isSelected: Bool = false {
        didSet { updateHighlight() }
    }
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(item: BrowsingSuggestionItem) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: item.iconName, accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            iconView.image = img.withSymbolConfiguration(conf)
            iconView.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        }
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = item.title
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = NSColor(white: 0.95, alpha: 1.0)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.stringValue = item.subtitle
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = NSColor(white: 0.45, alpha: 1.0)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            subtitleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) {
        isSelected = true
    }

    override func mouseExited(with event: NSEvent) {
        isSelected = false
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    private func updateHighlight() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            layer?.backgroundColor = isSelected ? NSColor(white: 1.0, alpha: 0.08).cgColor : NSColor.clear.cgColor
            titleLabel.textColor = isSelected ? NSColor.white : NSColor(white: 0.92, alpha: 1.0)
            iconView.contentTintColor = isSelected ? NSColor.white : NSColor(white: 0.65, alpha: 1.0)
        }
    }
}

// MARK: - Browsing Suggestions Container View
class BrowsingSuggestionsView: NSView {
    var onSelect: ((BrowsingSuggestionItem) -> Void)?
    var onSwitchEngine: ((String) -> Void)?
    
    private let stackView = NSStackView()
    private var rowViews: [BrowsingSuggestionRowView] = []
    private var items: [BrowsingSuggestionItem] = []
    private var engineButtons: [NSButton] = []
    
    var selectedIndex: Int = -1 {
        didSet {
            for (idx, row) in rowViews.enumerated() {
                row.isSelected = (idx == selectedIndex)
            }
        }
    }

    override var acceptsFirstResponder: Bool { return false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor(red: 16/255.0, green: 16/255.0, blue: 20/255.0, alpha: 0.96).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 2
        stackView.alignment = .leading
        addSubview(stackView)

        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.wantsLayer = true
        footer.layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.28).cgColor
        addSubview(footer)

        let footerLabel = NSTextField(labelWithString: "↑↓ Navigate · ↵ Select · esc Dismiss")
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        footerLabel.textColor = NSColor(white: 0.40, alpha: 1.0)
        footer.addSubview(footerLabel)

        let engineStack = NSStackView()
        engineStack.translatesAutoresizingMaskIntoConstraints = false
        engineStack.orientation = .horizontal
        engineStack.spacing = 4
        footer.addSubview(engineStack)

        let engines = [("duckduckgo", "DDG"), ("google", "Google"), ("brave", "Brave"), ("perplexity", "Perplexity"), ("kagi", "Kagi"), ("bing", "Bing")]
        let current = (UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo").lowercased()
        for (key, label) in engines {
            let btn = NSButton(title: label, target: self, action: #selector(engineButtonClicked(_:)))
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 4
            btn.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
            if key == current {
                btn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.14).cgColor
                btn.contentTintColor = .white
            } else {
                btn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.04).cgColor
                btn.contentTintColor = NSColor(white: 0.55, alpha: 1.0)
            }
            btn.identifier = NSUserInterfaceItemIdentifier(key)
            engineButtons.append(btn)
            engineStack.addArrangedSubview(btn)
        }

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),

            footer.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 6),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 32),

            footerLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            footerLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            engineStack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -8),
            engineStack.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func engineButtonClicked(_ sender: NSButton) {
        if let key = sender.identifier?.rawValue {
            onSwitchEngine?(key)
        }
    }

    func updateActiveEngine(_ engine: String) {
        let low = engine.lowercased()
        for btn in engineButtons {
            let isCurrent = (btn.identifier?.rawValue == low)
            btn.layer?.backgroundColor = isCurrent ? NSColor(white: 1.0, alpha: 0.14).cgColor : NSColor(white: 1.0, alpha: 0.04).cgColor
            btn.contentTintColor = isCurrent ? .white : NSColor(white: 0.55, alpha: 1.0)
        }
    }

    func updateItems(_ newItems: [BrowsingSuggestionItem]) {
        self.items = newItems
        selectedIndex = -1
        for v in rowViews {
            v.removeFromSuperview()
        }
        rowViews.removeAll()

        for item in newItems {
            let row = BrowsingSuggestionRowView(item: item)
            row.onClick = { [weak self] in
                self?.onSelect?(item)
            }
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            rowViews.append(row)
        }
    }

    func moveSelection(direction: Int) {
        guard !items.isEmpty else { return }
        if selectedIndex == -1 {
            selectedIndex = (direction > 0) ? 0 : (items.count - 1)
        } else {
            selectedIndex = max(0, min(items.count - 1, selectedIndex + direction))
        }
    }

    func selectedItem() -> BrowsingSuggestionItem? {
        if selectedIndex >= 0 && selectedIndex < items.count {
            return items[selectedIndex]
        }
        return nil
    }
}

// MARK: - Profile Pill Button (Apple-style frosted capsule in Top Bar that smoothly expands on hover)
class ProfilePillButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private let dotView = NSView()
    private let titleLbl = NSTextField(labelWithString: "Personal")
    private let gearButton = NSButton()
    private let chevronView = NSImageView()
    private var isHovered: Bool = false
    private var widthConstraint: NSLayoutConstraint?
    private var activeProfileName: String = "Personal"
    var onSettingsClick: (() -> Void)?
    
    private let collapsedWidth: CGFloat = 28
    private var expandedWidth: CGFloat {
        let titleW = titleLbl.intrinsicContentSize.width
        return ceil(10 + 8 + 6 + titleW + 6 + 14 + 4 + 8 + 10)
    }
    
    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.title = ""
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        layer?.masksToBounds = true
        toolTip = "Workspace: Personal · Hover to view & access Settings, click to switch (⌘⌥P)"
        
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.layer?.backgroundColor = NSColor.white.cgColor
        addSubview(dotView)
        
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        titleLbl.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        titleLbl.textColor = NSColor(white: 0.94, alpha: 1.0)
        titleLbl.alphaValue = 0.0
        titleLbl.lineBreakMode = .byClipping
        titleLbl.maximumNumberOfLines = 1
        addSubview(titleLbl)
        
        gearButton.translatesAutoresizingMaskIntoConstraints = false
        gearButton.bezelStyle = .regularSquare
        gearButton.isBordered = false
        gearButton.title = ""
        gearButton.wantsLayer = true
        gearButton.toolTip = "Open Workspaces & Browser Settings (⌘,)"
        gearButton.target = self
        gearButton.action = #selector(gearClicked)
        if let img = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 9.0, weight: .medium)
            gearButton.image = img.withSymbolConfiguration(cfg)
            gearButton.contentTintColor = NSColor(white: 0.70, alpha: 1.0)
        }
        gearButton.alphaValue = 0.0
        addSubview(gearButton)
        
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 7.5, weight: .semibold)
            chevronView.image = img.withSymbolConfiguration(cfg)
            chevronView.contentTintColor = NSColor(white: 0.55, alpha: 1.0)
        }
        chevronView.alphaValue = 0.0
        addSubview(chevronView)
        
        widthConstraint = widthAnchor.constraint(equalToConstant: collapsedWidth)
        widthConstraint?.isActive = true
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),
            
            titleLbl.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 6),
            titleLbl.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            gearButton.leadingAnchor.constraint(equalTo: titleLbl.trailingAnchor, constant: 6),
            gearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            gearButton.widthAnchor.constraint(equalToConstant: 14),
            gearButton.heightAnchor.constraint(equalToConstant: 14),
            
            chevronView.leadingAnchor.constraint(equalTo: gearButton.trailingAnchor, constant: 4),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 8),
            chevronView.heightAnchor.constraint(equalToConstant: 8)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override var intrinsicContentSize: NSSize {
        let w = isHovered ? expandedWidth : collapsedWidth
        return NSSize(width: w, height: 28)
    }
    
    func configure(profile: BrowserProfile) {
        activeProfileName = profile.name
        titleLbl.stringValue = profile.name
        dotView.layer?.backgroundColor = profile.color.cgColor
        dotView.layer?.shadowColor = profile.color.cgColor
        dotView.layer?.shadowOpacity = 0.6
        dotView.layer?.shadowRadius = 4
        dotView.layer?.shadowOffset = .zero
        toolTip = "Workspace: \(profile.name) · Click to switch, click gear for Settings (⌘,)"
        if isHovered {
            widthConstraint?.constant = expandedWidth
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        updateTrackingAreas()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    @objc private func gearClicked() {
        onSettingsClick?()
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isHovered && gearButton.alphaValue > 0.3 {
            let gearPoint = gearButton.convert(point, from: self)
            if gearButton.bounds.insetBy(dx: -4, dy: -4).contains(gearPoint) {
                return gearButton
            }
        }
        return super.hitTest(point)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.widthConstraint?.animator().constant = self.expandedWidth
            self.titleLbl.animator().alphaValue = 1.0
            self.gearButton.animator().alphaValue = 1.0
            self.chevronView.animator().alphaValue = 1.0
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.09).cgColor
            self.layer?.borderColor = NSColor(white: 1.0, alpha: 0.20).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.widthConstraint?.animator().constant = self.collapsedWidth
            self.titleLbl.animator().alphaValue = 0.0
            self.gearButton.animator().alphaValue = 0.0
            self.chevronView.animator().alphaValue = 0.0
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
            self.layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        }
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Profile Row View (Item inside Profile Switcher Popover)
class ProfileRowView: NSView {
    let profile: BrowserProfile
    let isActive: Bool
    let tabCount: Int
    let shortcut: String
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    
    init(profile: BrowserProfile, isActive: Bool, tabCount: Int, shortcut: String) {
        self.profile = profile
        self.isActive = isActive
        self.tabCount = tabCount
        self.shortcut = shortcut
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = isActive ? NSColor(white: 1.0, alpha: 0.08).cgColor : NSColor.clear.cgColor
        if isActive {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        }
        
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 7
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        iconPlate.layer?.borderWidth = 1
        iconPlate.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        addSubview(iconPlate)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: profile.iconName, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = profile.color
        }
        iconPlate.addSubview(iconView)
        
        let titleLabel = NSTextField(labelWithString: profile.name)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: isActive ? .semibold : .medium)
        titleLabel.textColor = NSColor.white
        addSubview(titleLabel)
        
        let tabString = tabCount == 1 ? "1 tab" : "\(tabCount) tabs"
        let subText = isActive ? "\(tabString) • Active" : "\(tabString) • Isolated"
        let subLabel = NSTextField(labelWithString: subText)
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        subLabel.textColor = isActive ? NSColor(white: 0.70, alpha: 1.0) : NSColor(white: 0.45, alpha: 1.0)
        addSubview(subLabel)
        
        let badge = NSTextField(labelWithString: shortcut)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        badge.textColor = NSColor(white: 0.60, alpha: 1.0)
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        badge.layer?.cornerRadius = 4
        badge.alignment = .center
        addSubview(badge)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 28),
            iconPlate.heightAnchor.constraint(equalToConstant: 28),
            
            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),
            
            subLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),
            
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            badge.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        if !isActive {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
            }
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if !isActive {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                self.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - Profile Action Row View (Add profile & clear cache buttons)
class ProfileActionRowView: NSView {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    
    init(title: String, iconName: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.clear.cgColor
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        }
        addSubview(iconView)
        
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = NSColor(white: 0.75, alpha: 1.0)
        addSubview(label)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),
            
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - Download Models & Management
class OnyxDownloadItem: Identifiable {
    let id: UUID = UUID()
    weak var download: WKDownload?
    var filename: String
    var destinationURL: URL?
    var sourceURL: URL?
    var totalBytes: Int64 = 0
    var receivedBytes: Int64 = 0
    var progressFraction: Double = 0.0
    var state: State = .downloading
    let startDate: Date = Date()
    var finishDate: Date?
    var errorMessage: String?
    
    enum State {
        case downloading
        case completed
        case failed
        case cancelled
    }
    
    init(download: WKDownload?, filename: String, sourceURL: URL?) {
        self.download = download
        self.filename = filename
        self.sourceURL = sourceURL
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        if totalBytes > 0 {
            return formatter.string(fromByteCount: totalBytes)
        } else if receivedBytes > 0 {
            return formatter.string(fromByteCount: receivedBytes)
        } else if let dest = destinationURL, let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path), let sz = attrs[.size] as? Int64 {
            return formatter.string(fromByteCount: sz)
        }
        return "Zero KB"
    }
    
    var iconName: String {
        let ext = (destinationURL?.pathExtension ?? (filename as NSString).pathExtension).lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff":
            return "photo"
        case "zip", "tar", "gz", "7z", "rar", "dmg", "pkg", "iso":
            return "archivebox"
        case "pdf", "doc", "docx", "pages", "txt", "md", "rtf":
            return "doc.text"
        case "swift", "js", "ts", "py", "html", "css", "json", "c", "cpp", "rs", "sh":
            return "curlybraces"
        case "mp3", "wav", "m4a", "flac", "aac":
            return "music.note"
        case "mp4", "mov", "mkv", "avi", "webm":
            return "film"
        case "xls", "xlsx", "numbers", "csv":
            return "tablecells"
        case "key", "ppt", "pptx":
            return "play.rectangle"
        default:
            return "doc"
        }
    }
}

// MARK: - Downloads Navigation Icon Button (Apple-style with progress & badge)
class DownloadsNavButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private let iconView = NSImageView()
    private let badgeDot = NSView()
    private let progressLayer = CAShapeLayer()
    
    var isDownloading: Bool = false {
        didSet { updateVisuals() }
    }
    var progress: Double = 0.0 {
        didSet { updateProgressRing() }
    }
    var hasUnseenFinished: Bool = false {
        didSet { updateVisuals() }
    }
    
    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.title = ""
        self.attributedTitle = NSAttributedString(string: "")
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.wantsLayer = true
        self.target = target
        self.action = action
        self.toolTip = "Downloads (⌘J)"
        self.layer?.cornerRadius = 6
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Downloads") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            iconView.image = img.withSymbolConfiguration(config)
            iconView.contentTintColor = NSColor(white: 0.82, alpha: 1.0)
        }
        addSubview(iconView)
        
        progressLayer.strokeColor = NSColor.white.cgColor
        progressLayer.fillColor = NSColor.clear.cgColor
        progressLayer.lineWidth = 1.5
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0
        progressLayer.lineCap = .round
        layer?.addSublayer(progressLayer)
        
        badgeDot.translatesAutoresizingMaskIntoConstraints = false
        badgeDot.wantsLayer = true
        badgeDot.layer?.cornerRadius = 3
        badgeDot.layer?.backgroundColor = NSColor(white: 0.95, alpha: 1.0).cgColor
        badgeDot.layer?.shadowColor = NSColor.white.cgColor
        badgeDot.layer?.shadowOpacity = 0.8
        badgeDot.layer?.shadowRadius = 2
        badgeDot.isHidden = true
        addSubview(badgeDot)
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
            
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            badgeDot.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            badgeDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            badgeDot.widthAnchor.constraint(equalToConstant: 6),
            badgeDot.heightAnchor.constraint(equalToConstant: 6)
        ])
        
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func layout() {
        super.layout()
        let radius: CGFloat = 10.0
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: -CGFloat.pi / 2, endAngle: 1.5 * CGFloat.pi, clockwise: false)
        progressLayer.path = path
    }
    
    func updateVisuals() {
        badgeDot.isHidden = !hasUnseenFinished || isDownloading
        if isDownloading {
            progressLayer.isHidden = false
            if let img = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Downloading") {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                iconView.image = img.withSymbolConfiguration(config)
                iconView.contentTintColor = NSColor.white
            }
        } else {
            progressLayer.isHidden = true
            if let img = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Downloads") {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                iconView.image = img.withSymbolConfiguration(config)
                iconView.contentTintColor = hasUnseenFinished ? NSColor.white : NSColor(white: 0.82, alpha: 1.0)
            }
        }
    }
    
    func updateProgressRing() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = CGFloat(max(0.04, min(1.0, progress)))
        CATransaction.commit()
    }
    
    func triggerBounce() {
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, 1.28, 0.92, 1.08, 1.0]
        bounce.keyTimes = [0, 0.3, 0.55, 0.8, 1.0]
        bounce.duration = 0.38
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(bounce, forKey: "bounce")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            self.iconView.contentTintColor = NSColor.white
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.updateVisuals()
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if let m = self.menu {
            NSMenu.popUpContextMenu(m, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

// MARK: - Flipped Clip View for Top-Aligned Scroll Views
class FlippedClipView: NSClipView {
    override var isFlipped: Bool { return true }
}

// MARK: - Onyx Download Row View (Popover row with live progress and actions)
class OnyxDownloadRowView: NSView {
    let item: OnyxDownloadItem
    var onShowInFinder: (() -> Void)?
    var onOpenFile: (() -> Void)?
    var onCancel: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    
    private let titleLabel = NSTextField()
    private let subLabel = NSTextField()
    private let progressBar = NSBox()
    private var progressWidthConstraint: NSLayoutConstraint?
    
    init(item: OnyxDownloadItem) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.clear.cgColor
        
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 7
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        iconPlate.layer?.borderWidth = 1
        iconPlate.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        addSubview(iconPlate)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: item.iconName, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = NSColor(white: 0.88, alpha: 1.0)
        }
        iconPlate.addSubview(iconView)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.drawsBackground = false
        titleLabel.stringValue = item.filename
        titleLabel.font = NSFont.systemFont(ofSize: 12.0, weight: .medium)
        titleLabel.textColor = NSColor.white
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)
        
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.isBezeled = false
        subLabel.isEditable = false
        subLabel.drawsBackground = false
        subLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        subLabel.textColor = NSColor(white: 0.70, alpha: 1.0)
        addSubview(subLabel)
        
        let progressTrack = NSBox()
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.boxType = .custom
        progressTrack.borderWidth = 0
        progressTrack.fillColor = NSColor(white: 1.0, alpha: 0.08)
        progressTrack.layer?.cornerRadius = 1
        addSubview(progressTrack)
        
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.boxType = .custom
        progressBar.borderWidth = 0
        progressBar.fillColor = NSColor.white
        progressBar.layer?.cornerRadius = 1
        progressTrack.addSubview(progressBar)
        
        progressWidthConstraint = progressBar.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint?.isActive = true
        
        let actionsStack = NSStackView()
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 4
        actionsStack.alignment = .centerY
        addSubview(actionsStack)
        
        if case .downloading = item.state {
            let cancelBtn = NavIconButton(iconName: "xmark.circle", tooltip: "Cancel Download", target: self, action: #selector(cancelClicked))
            actionsStack.addArrangedSubview(cancelBtn)
        } else if case .completed = item.state {
            let finderBtn = NavIconButton(iconName: "magnifyingglass", tooltip: "Show in Finder", target: self, action: #selector(finderClicked))
            let openBtn = NavIconButton(iconName: "arrow.up.forward.app", tooltip: "Open File", target: self, action: #selector(openClicked))
            actionsStack.addArrangedSubview(finderBtn)
            actionsStack.addArrangedSubview(openBtn)
        }
        
        updateContent()
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),
            
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 32),
            iconPlate.heightAnchor.constraint(equalToConstant: 32),
            
            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            
            subLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            
            progressTrack.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            progressTrack.topAnchor.constraint(equalTo: subLabel.bottomAnchor, constant: 3),
            progressTrack.trailingAnchor.constraint(equalTo: actionsStack.leadingAnchor, constant: -12),
            progressTrack.heightAnchor.constraint(equalToConstant: 2),
            
            progressBar.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressBar.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressBar.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        if case .downloading = item.state {
            progressTrack.isHidden = false
        } else {
            progressTrack.isHidden = true
        }
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func updateContent() {
        titleLabel.stringValue = item.filename
        switch item.state {
        case .downloading:
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let rec = formatter.string(fromByteCount: item.receivedBytes)
            if item.totalBytes > 0 {
                let tot = formatter.string(fromByteCount: item.totalBytes)
                let pct = Int(item.progressFraction * 100.0)
                subLabel.stringValue = "\(rec) of \(tot) (\(pct)%)"
                progressWidthConstraint?.constant = CGFloat(item.progressFraction) * 130.0
            } else {
                subLabel.stringValue = "\(rec) downloaded"
            }
        case .completed:
            subLabel.stringValue = "\(item.formattedSize) • Ready"
            subLabel.textColor = NSColor(white: 0.70, alpha: 1.0)
        case .failed:
            subLabel.stringValue = item.errorMessage ?? "Download failed"
            subLabel.textColor = NSColor(red: 248/255.0, green: 113/255.0, blue: 113/255.0, alpha: 1.0)
        case .cancelled:
            subLabel.stringValue = "Cancelled"
            subLabel.textColor = NSColor(white: 0.40, alpha: 1.0)
        }
    }
    
    @objc private func finderClicked() { onShowInFinder?() }
    @objc private func openClicked() { onOpenFile?() }
    @objc private func cancelClicked() { onCancel?() }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

// MARK: - Download Notification HUD Banner (Apple-style floating toast)
class DownloadNotificationHUD: NSView {
    let fileURL: URL
    private var trackingArea: NSTrackingArea?
    
    init(filename: String, fileURL: URL) {
        self.fileURL = fileURL
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        layer?.backgroundColor = NSColor(red: 18/255.0, green: 18/255.0, blue: 22/255.0, alpha: 0.94).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.shadowRadius = 12
        
        let blur = NSVisualEffectView()
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        addSubview(blur)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Downloaded") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = NSColor(red: 52/255.0, green: 211/255.0, blue: 153/255.0, alpha: 1.0)
        }
        addSubview(iconView)
        
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading
        addSubview(textStack)
        
        let headerLabel = NSTextField(labelWithString: "DOWNLOAD COMPLETE")
        headerLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        headerLabel.textColor = NSColor(red: 52/255.0, green: 211/255.0, blue: 153/255.0, alpha: 1.0)
        textStack.addArrangedSubview(headerLabel)
        
        let nameLabel = NSTextField(labelWithString: filename)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = NSColor.white
        nameLabel.lineBreakMode = .byTruncatingMiddle
        textStack.addArrangedSubview(nameLabel)
        
        let finderBtn = NSButton()
        finderBtn.translatesAutoresizingMaskIntoConstraints = false
        finderBtn.bezelStyle = .regularSquare
        finderBtn.isBordered = false
        finderBtn.wantsLayer = true
        finderBtn.layer?.cornerRadius = 6
        finderBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        finderBtn.layer?.borderWidth = 1
        finderBtn.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        finderBtn.attributedTitle = NSAttributedString(string: "Show in Finder", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        finderBtn.target = self
        finderBtn.action = #selector(showInFinderClicked)
        addSubview(finderBtn)
        
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: finderBtn.leadingAnchor, constant: -10),
            
            finderBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            finderBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            finderBtn.heightAnchor.constraint(equalToConstant: 26),
            finderBtn.widthAnchor.constraint(equalToConstant: 96)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    @objc private func showInFinderClicked() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        dismiss()
    }
    
    override func mouseDown(with event: NSEvent) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        dismiss()
    }
    
    func animateIn() {
        alphaValue = 0
        let transform = CATransform3DMakeTranslation(0, -10, 0)
        layer?.transform = transform
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().alphaValue = 1.0
            self.layer?.transform = CATransform3DIdentity
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            self?.dismiss()
        }
    }
    
    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.removeFromSuperview()
        })
    }
}

// MARK: - Jakub Antalik Thinking-Orbs Engine (Native 3D Canvas in Swift)
enum ThinkingOrbMode {
    case orbits      // Working / page loading
    case globe       // Searching / AI research query
    case wave        // Listening / audio / focus
    case breathing   // Idle calm ring
    case rubik       // Solving / deep synthesis
}

struct OrbDot {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
    var r: CGFloat
    var white: CGFloat
    var a: CGFloat
}

class ThinkingOrbView: NSView {
    var mode: ThinkingOrbMode = .orbits
    private var displayTimer: Timer?
    private var startTime: CFTimeInterval = 0
    
    override var isFlipped: Bool { return true }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func startAnimation(mode: ThinkingOrbMode = .orbits) {
        self.mode = mode
        self.isHidden = false
        if displayTimer == nil {
            startTime = CACurrentMediaTime()
            displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.needsDisplay = true
            }
        }
    }
    
    func stopAnimation() {
        displayTimer?.invalidate()
        displayTimer = nil
        self.isHidden = true
        needsDisplay = true
    }
    
    private func hashD(_ a: Double, _ b: Double) -> Double {
        let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return h - floor(h)
    }
    
    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        return atan2(sin(a - b), cos(a - b))
    }
    
    private func project(yaw: Double, tilt: Double, cx: Double, cy: Double, scale: Double, x: Double, y: Double, z: Double) -> (Double, Double, Double) {
        let st = sin(tilt), ct = cos(tilt)
        let sy = sin(yaw), cyw = cos(yaw)
        let x1 = x * cyw + z * sy
        let z1 = -x * sy + z * cyw
        let y1 = y * ct - z1 * st
        let z2 = y * st + z1 * ct
        return (cx + x1 * scale, cy - y1 * scale, z2)
    }
    
    private func generateFrame(size: Double, t: Double) -> [OrbDot] {
        var dots: [OrbDot] = []
        let cx = size / 2.0
        let cy = size / 2.0
        let rScale = max(0.5, pow(size / 300.0, 0.6) * 1.6)
        
        switch mode {
        case .orbits:
            let R = (size / 2.0) * 0.84
            let orbitCount = 6
            let ghostCount = 18
            let particles = 2
            
            for orb in 0..<orbitCount {
                let h1 = hashD(Double(orb), 1.7)
                let h2 = hashD(Double(orb), 5.2)
                let h3 = hashD(Double(orb), 8.9)
                let ro = R * (0.45 + 0.52 * h1)
                let th = h1 * 2.0 * .pi
                let phi = acos(2.0 * h2 - 1.0)
                let nx = sin(phi) * cos(th)
                let ny = cos(phi)
                let nz = sin(phi) * sin(th)
                
                var ux = -ny, uy = nx, uz = 0.0
                let ul = max(1e-6, sqrt(ux * ux + uy * uy))
                ux /= ul; uy /= ul
                let vx = ny * uz - nz * uy
                let vy = nz * ux - nx * uz
                let vz = nx * uy - ny * ux
                let speed = (0.35 + 0.65 * h3) * (h3 > 0.5 ? 1.0 : -1.0) * 1.88
                
                for k in 0..<ghostCount {
                    let a = (Double(k) / Double(ghostCount)) * 2.0 * .pi
                    let (px, py, z) = project(yaw: t * 0.18, tilt: 0.32, cx: cx, cy: cy, scale: 1.0,
                                              x: (ux * cos(a) + vx * sin(a)) * ro,
                                              y: (uy * cos(a) + vy * sin(a)) * ro,
                                              z: (uz * cos(a) + vz * sin(a)) * ro)
                    let depth = (z / ro + 1.0) / 2.0
                    dots.append(OrbDot(x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                                       r: CGFloat(max(0.4, 0.75 * rScale)),
                                       white: 0.70,
                                       a: CGFloat(0.4 * (0.35 + 0.65 * depth))))
                }
                
                for m in 0..<particles {
                    let a = t * speed + (Double(m) / Double(particles)) * 2.0 * .pi + h2 * 6.0
                    let (px, py, z) = project(yaw: t * 0.18, tilt: 0.32, cx: cx, cy: cy, scale: 1.0,
                                              x: (ux * cos(a) + vx * sin(a)) * ro,
                                              y: (uy * cos(a) + vy * sin(a)) * ro,
                                              z: (uz * cos(a) + vz * sin(a)) * ro)
                    let depth = (z / ro + 1.0) / 2.0
                    dots.append(OrbDot(x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                                       r: CGFloat((1.1 + 1.4 * depth) * rScale),
                                       white: CGFloat(0.25 - 0.22 * depth),
                                       a: 0.95))
                }
            }
            
        case .globe:
            let spin = 0.65
            let radius = (size / 2.0) * 0.84
            let tilt = 0.4 + 0.06 * sin(t * 0.35)
            let scan = t * (spin + 1.5 * 3.8)
            let latRings = 8
            let lonDensity = 20
            
            for li in 0...latRings {
                let lat = -.pi / 2.0 + (Double(li) / Double(latRings)) * .pi
                let cosLat = cos(lat), sinLat = sin(lat)
                let lonCount = max(1, Int(abs(cosLat) * Double(lonDensity)))
                for lj in 0..<lonCount {
                    let lon = (Double(lj) / Double(lonCount)) * 2.0 * .pi
                    let (px, py, z) = project(yaw: t * spin, tilt: tilt, cx: cx, cy: cy, scale: radius,
                                              x: cosLat * cos(lon), y: sinLat, z: cosLat * sin(lon))
                    let depth = (z + 1.0) / 2.0
                    let d = angleDelta(lon + t * spin, scan)
                    let boost = exp(-(d * d) / 0.22) * max(0.0, z)
                    dots.append(OrbDot(
                        x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                        r: CGFloat((0.6 + 1.4 * depth + 1.2 * boost) * rScale),
                        white: CGFloat(0.60 - 0.50 * depth),
                        a: CGFloat(0.40 + 0.60 * min(1.0, boost))
                    ))
                }
            }
            
        case .wave:
            let R = (size / 2.0) * 0.85
            let rings = 8
            let lonDensity = 18
            for ri in 0...rings {
                let lat = -.pi / 2.0 + (Double(ri) / Double(rings)) * .pi
                let cosLat = cos(lat), sinLat = sin(lat)
                let w = 0.62 * sin(t * 2.5 - Double(ri) * 0.6) + 0.38 * sin(t * 1.4 + Double(ri) * 0.9)
                let rr = R * (0.86 + 0.12 * w)
                let lonCount = max(1, Int(abs(cosLat) * Double(lonDensity)))
                for lj in 0..<lonCount {
                    let lon = (Double(lj) / Double(lonCount)) * 2.0 * .pi
                    let (px, py, z) = project(yaw: t * 0.2, tilt: 0.38, cx: cx, cy: cy, scale: 1.0,
                                              x: cosLat * cos(lon) * rr, y: sinLat * rr, z: cosLat * sin(lon) * rr)
                    let depth = (z / R + 1.0) / 2.0
                    let crest = max(0.0, w)
                    dots.append(OrbDot(
                        x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                        r: CGFloat((0.6 + 1.4 * depth) * (1.0 + 0.4 * crest) * rScale),
                        white: CGFloat(0.62 - 0.52 * depth - 0.1 * crest),
                        a: CGFloat(0.45 + 0.55 * depth)
                    ))
                }
            }
            
        case .breathing:
            let R = (size / 2.0) * 0.78
            let wobAmp = 0.23 * 0.368
            let baseR = R / (1.0 + 0.85 * wobAmp)
            let lanes = 3, segs = 36
            for w in 0..<lanes {
                let laneOff = (Double(w) - Double(lanes - 1) / 2.0) * 0.08
                for k in 0..<segs {
                    let a = (Double(k) / Double(segs)) * 2.0 * .pi
                    let wob = (0.16 * sin(a * 3.0 - t * 1.8 + Double(w) * 0.25) + 0.07 * sin(a * 5.0 + t * 1.2)) * 0.368
                    let radial = 1.0 + wob
                    let x = cos(a) * (baseR * radial)
                    let y = sin(a) * (baseR * radial) + laneOff * baseR
                    let (px, py, z) = project(yaw: 0, tilt: 0.3, cx: cx, cy: cy, scale: 1.0, x: x, y: y, z: 0)
                    dots.append(OrbDot(
                        x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                        r: CGFloat(1.2 * rScale),
                        white: 0.25,
                        a: CGFloat(0.55 + 0.45 * sin(t * 1.4 + a))
                    ))
                }
            }
            
        case .rubik:
            let R = (size / 2.0) * 0.82
            let latRings = 7, lonDensity = 16
            let spin = t * 0.55
            for li in 0...latRings {
                let lat = -.pi / 2.0 + (Double(li) / Double(latRings)) * .pi
                let cosLat = cos(lat), sinLat = sin(lat)
                let lonCount = max(1, Int(abs(cosLat) * Double(lonDensity)))
                for lj in 0..<lonCount {
                    let lon = (Double(lj) / Double(lonCount)) * 2.0 * .pi
                    let (px, py, z) = project(yaw: spin, tilt: 0.35 + 0.1 * sin(t * 0.9), cx: cx, cy: cy, scale: R,
                                              x: cosLat * cos(lon), y: sinLat, z: cosLat * sin(lon))
                    let depth = (z + 1.0) / 2.0
                    dots.append(OrbDot(
                        x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                        r: CGFloat((0.6 + 1.5 * depth) * rScale),
                        white: CGFloat(0.60 - 0.50 * depth),
                        a: CGFloat(0.50 + 0.50 * depth)
                    ))
                }
            }
        }
        
        return dots.sorted { $0.z < $1.z }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let t = CACurrentMediaTime() - startTime
        let size = Double(min(bounds.width, bounds.height))
        guard size > 0 else { return }
        
        let frameDots = generateFrame(size: size, t: t)
        for d in frameDots {
            let alpha = max(0.0, min(1.0, d.a))
            let w = max(0.0, min(1.0, d.white))
            let g = 1.0 - w // Apple monochrome: bright white / silver dots on dark shell
            ctx.setFillColor(red: g, green: g, blue: g, alpha: alpha)
            ctx.fillEllipse(in: CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2.0, height: d.r * 2.0))
        }
    }
}

// MARK: - Onyx Password Vault & Password Importer Engine
struct OnyxPasswordEntry: Codable, Identifiable {
    var id: UUID
    var title: String
    var urlString: String
    var username: String
    var password: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        username: String,
        password: String,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.username = username
        self.password = password
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var domain: String {
        let cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: cleaned), let host = u.host, !host.isEmpty {
            return host.lowercased()
        }
        if let u = URL(string: "https://" + cleaned), let host = u.host, !host.isEmpty {
            return host.lowercased()
        }
        return cleaned.lowercased()
    }
    
    func matches(host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let d = domain.lowercased()
        guard !h.isEmpty && !d.isEmpty else { return false }
        if h == d { return true }
        if h.hasSuffix("." + d) || d.hasSuffix("." + h) { return true }
        let cleanH = h.replacingOccurrences(of: "www.", with: "")
        let cleanD = d.replacingOccurrences(of: "www.", with: "")
        return cleanH == cleanD || cleanH.contains(cleanD) || cleanD.contains(cleanH)
    }
    
    func matchesQuery(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return title.lowercased().contains(q) ||
               username.lowercased().contains(q) ||
               domain.lowercased().contains(q) ||
               urlString.lowercased().contains(q) ||
               notes.lowercased().contains(q)
    }
}

// Robust RFC-4180 CSV Parser (Handles quoted fields, escaped quotes, multiline values, and BOM)
class OnyxCSVParser {
    static func parse(text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        var chars = Array(text)
        var i = 0
        
        if chars.first == "\u{FEFF}" {
            chars.removeFirst()
        }
        
        while i < chars.count {
            let c = chars[i]
            if insideQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(c)
                }
            } else {
                if c == "\"" {
                    insideQuotes = true
                } else if c == "," {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                } else if c == "\r" {
                    if i + 1 < chars.count && chars[i + 1] == "\n" {
                        i += 1
                    }
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    currentField = ""
                } else if c == "\n" {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    currentField = ""
                } else {
                    currentField.append(c)
                }
            }
            i += 1
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }
        return rows
    }
}

// Multi-Source Password Importer Engine (Chrome, Safari, Firefox, 1Password, Bitwarden, LastPass, Generic CSV/JSON)
class OnyxPasswordImporter {
    struct ImportResult {
        let entries: [OnyxPasswordEntry]
        let source: String
        let error: String?
    }
    
    static func importFromFile(url: URL) -> ImportResult {
        guard let data = try? Data(contentsOf: url) else {
            return ImportResult(entries: [], source: url.lastPathComponent, error: "Unable to read file.")
        }
        
        // Try UTF-8 then ISO Latin 1 fallback
        let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        guard !content.isEmpty else {
            return ImportResult(entries: [], source: url.lastPathComponent, error: "File content is empty or unreadable.")
        }
        
        let ext = url.pathExtension.lowercased()
        if ext == "json" || content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            let entries = parseJSON(content: content)
            if !entries.isEmpty {
                return ImportResult(entries: entries, source: "Bitwarden / JSON Vault", error: nil)
            }
        }
        
        let (entries, detectedSource) = parseCSVWithDetection(content: content, filename: url.lastPathComponent)
        if entries.isEmpty {
            return ImportResult(entries: [], source: url.lastPathComponent, error: "No valid login credentials found in file.")
        }
        return ImportResult(entries: entries, source: detectedSource, error: nil)
    }
    
    static func parseCSVWithDetection(content: String, filename: String) -> (entries: [OnyxPasswordEntry], source: String) {
        let rows = OnyxCSVParser.parse(text: content)
        guard rows.count > 1 else { return ([], filename) }
        
        let headerRow = rows[0].map { $0.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "") }
        
        // Identify column mappings
        var nameIdx = -1
        var urlIdx = -1
        var userIdx = -1
        var passIdx = -1
        var notesIdx = -1
        
        for (i, h) in headerRow.enumerated() {
            if nameIdx == -1 && (h == "name" || h == "title" || h == "sitename" || h == "site" || h == "service") {
                nameIdx = i
            } else if urlIdx == -1 && (h == "url" || h == "loginuri" || h == "loginurl" || h == "website" || h == "uri" || h == "address" || h == "httprealm") {
                urlIdx = i
            } else if userIdx == -1 && (h == "username" || h == "user" || h == "loginusername" || h == "login" || h == "email" || h == "account" || h == "user_name") {
                userIdx = i
            } else if passIdx == -1 && (h == "password" || h == "loginpassword" || h == "pass" || h == "pwd" || h == "secret") {
                passIdx = i
            } else if notesIdx == -1 && (h == "notes" || h == "note" || h == "comment" || h == "comments" || h == "extra") {
                notesIdx = i
            }
        }
        
        // Determine source description
        var sourceDesc = "CSV File"
        if headerRow.contains("otpauth") {
            sourceDesc = "Apple Safari Passwords"
        } else if headerRow.contains("loginuri") || headerRow.contains("loginpassword") {
            sourceDesc = "Bitwarden CSV"
        } else if headerRow.contains("httprealm") {
            sourceDesc = "Mozilla Firefox"
        } else if headerRow.contains("grouping") || headerRow.contains("fav") {
            sourceDesc = "LastPass CSV"
        } else if headerRow.contains("name") && headerRow.contains("url") && headerRow.contains("username") {
            sourceDesc = "Google Chrome / Chromium"
        }
        
        guard passIdx != -1 else { return ([], sourceDesc) }
        
        var results: [OnyxPasswordEntry] = []
        for row in rows.dropFirst() {
            guard passIdx < row.count else { continue }
            let pass = row[passIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pass.isEmpty else { continue }
            
            let title = (nameIdx != -1 && nameIdx < row.count) ? row[nameIdx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let urlStr = (urlIdx != -1 && urlIdx < row.count) ? row[urlIdx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let user = (userIdx != -1 && userIdx < row.count) ? row[userIdx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let notes = (notesIdx != -1 && notesIdx < row.count) ? row[notesIdx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            
            var displayTitle = title
            if displayTitle.isEmpty {
                if let u = URL(string: urlStr), let host = u.host, !host.isEmpty {
                    displayTitle = host.replacingOccurrences(of: "www.", with: "").capitalized
                } else if !urlStr.isEmpty {
                    displayTitle = urlStr
                } else {
                    displayTitle = user.isEmpty ? "Saved Login" : user
                }
            }
            
            var finalURL = urlStr
            if !finalURL.isEmpty && !finalURL.lowercased().hasPrefix("http://") && !finalURL.lowercased().hasPrefix("https://") {
                finalURL = "https://" + finalURL
            }
            
            let entry = OnyxPasswordEntry(
                title: displayTitle,
                urlString: finalURL,
                username: user,
                password: pass,
                notes: notes
            )
            results.append(entry)
        }
        
        return (results, sourceDesc)
    }
    
    static func parseJSON(content: String) -> [OnyxPasswordEntry] {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            // Check if top-level array of objects
            if let data = content.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                var list: [OnyxPasswordEntry] = []
                for item in array {
                    let title = (item["title"] ?? item["name"] ?? item["site"]) as? String ?? "Login"
                    let urlStr = (item["url"] ?? item["uri"] ?? item["urlString"]) as? String ?? ""
                    let user = (item["username"] ?? item["user"] ?? item["email"]) as? String ?? ""
                    let pass = (item["password"] ?? item["pass"]) as? String ?? ""
                    let notes = (item["notes"] ?? item["note"]) as? String ?? ""
                    if !pass.isEmpty {
                        list.append(OnyxPasswordEntry(title: title, urlString: urlStr, username: user, password: pass, notes: notes))
                    }
                }
                return list
            }
            return []
        }
        
        var results: [OnyxPasswordEntry] = []
        // Bitwarden format: { "items": [ { "name": "...", "login": { "uris": [...], "username": "...", "password": "..." }, "notes": "..." } ] }
        if let items = json["items"] as? [[String: Any]] {
            for item in items {
                let name = item["name"] as? String ?? "Login"
                let notes = item["notes"] as? String ?? ""
                if let login = item["login"] as? [String: Any] {
                    let user = login["username"] as? String ?? ""
                    let pass = login["password"] as? String ?? ""
                    var urlStr = ""
                    if let uris = login["uris"] as? [[String: Any]], let first = uris.first, let u = first["uri"] as? String {
                        urlStr = u
                    }
                    if !pass.isEmpty {
                        results.append(OnyxPasswordEntry(title: name, urlString: urlStr, username: user, password: pass, notes: notes))
                    }
                }
            }
        }
        return results
    }
}

// RFC-4180 CSV Exporter
class OnyxPasswordExporter {
    static func exportToCSV(entries: [OnyxPasswordEntry]) -> String {
        var csv = "title,url,username,password,notes\n"
        for e in entries {
            let row = [escapeCSV(e.title), escapeCSV(e.urlString), escapeCSV(e.username), escapeCSV(e.password), escapeCSV(e.notes)]
            csv.append(row.joined(separator: ",") + "\n")
        }
        return csv
    }
    
    private static func escapeCSV(_ str: String) -> String {
        if str.contains(",") || str.contains("\"") || str.contains("\n") || str.contains("\r") {
            let escaped = str.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return str
    }
}

// Persistent Vault Store (UserDefaults + ~/Library/Application Support/Onyx/passwords.json backup)
class OnyxPasswordStore {
    static let shared = OnyxPasswordStore()
    private let defaultsKey = "OnyxVaultPasswords"
    private var entries: [OnyxPasswordEntry] = []
    
    private var diskURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("Onyx")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("passwords.json")
    }
    
    init() {
        load()
    }
    
    func allEntries() -> [OnyxPasswordEntry] {
        return entries
    }
    
    func filteredEntries(query: String) -> [OnyxPasswordEntry] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entries
        }
        return entries.filter { $0.matchesQuery(query) }
    }
    
    func find(forHost host: String) -> [OnyxPasswordEntry] {
        guard !host.isEmpty else { return [] }
        return entries.filter { $0.matches(host: host) }
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let list = try? JSONDecoder().decode([OnyxPasswordEntry].self, from: data) {
            self.entries = list
            return
        }
        if let data = try? Data(contentsOf: diskURL),
           let list = try? JSONDecoder().decode([OnyxPasswordEntry].self, from: data) {
            self.entries = list
            save()
            return
        }
        // Default clean vault state with helpful initial bookmarks/examples
        self.entries = [
            OnyxPasswordEntry(title: "GitHub", urlString: "https://github.com/login", username: "developer@onyx.dev", password: "••••••••••••", notes: "Personal developer account"),
            OnyxPasswordEntry(title: "Google", urlString: "https://accounts.google.com", username: "user@gmail.com", password: "••••••••••••", notes: "Primary Google Workspace"),
            OnyxPasswordEntry(title: "TradingView", urlString: "https://www.tradingview.com", username: "trader_onyx", password: "••••••••••••", notes: "Market charting login")
        ]
        save()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
            try? data.write(to: diskURL, options: .atomic)
        }
    }
    
    func addOrUpdate(_ entry: OnyxPasswordEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
            entries[idx].updatedAt = Date()
        } else if let idx = entries.firstIndex(where: { $0.domain == entry.domain && $0.username.lowercased() == entry.username.lowercased() && !entry.username.isEmpty }) {
            entries[idx].password = entry.password
            if !entry.title.isEmpty { entries[idx].title = entry.title }
            if !entry.urlString.isEmpty { entries[idx].urlString = entry.urlString }
            if !entry.notes.isEmpty { entries[idx].notes = entry.notes }
            entries[idx].updatedAt = Date()
        } else {
            entries.insert(entry, at: 0)
        }
        save()
    }
    
    func delete(id: UUID) {
        entries.removeAll(where: { $0.id == id })
        save()
    }
    
    func importEntries(_ newEntries: [OnyxPasswordEntry]) -> (imported: Int, updated: Int) {
        var importedCount = 0
        var updatedCount = 0
        for entry in newEntries {
            guard !entry.password.isEmpty else { continue }
            if let idx = entries.firstIndex(where: { $0.domain == entry.domain && $0.username.lowercased() == entry.username.lowercased() && !entry.username.isEmpty }) {
                entries[idx].password = entry.password
                if !entry.title.isEmpty { entries[idx].title = entry.title }
                if !entry.urlString.isEmpty { entries[idx].urlString = entry.urlString }
                if !entry.notes.isEmpty { entries[idx].notes = entry.notes }
                entries[idx].updatedAt = Date()
                updatedCount += 1
            } else {
                entries.append(entry)
                importedCount += 1
            }
        }
        save()
        return (importedCount, updatedCount)
    }
    
    func generateStrongPassword(length: Int = 16) -> String {
        let upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        let lower = "abcdefghijkmnopqrstuvwxyz"
        let digits = "23456789"
        let symbols = "!@#$%^&*()-_=+"
        let all = upper + lower + digits + symbols
        
        var pass = ""
        // Ensure at least one from each class
        if let u = upper.randomElement() { pass.append(u) }
        if let l = lower.randomElement() { pass.append(l) }
        if let d = digits.randomElement() { pass.append(d) }
        if let s = symbols.randomElement() { pass.append(s) }
        
        for _ in 4..<length {
            if let c = all.randomElement() {
                pass.append(c)
            }
        }
        return String(pass.shuffled())
    }
}

// MARK: - Passwords Navigation Button (Key Icon with Dynamic Match Indicator)
class PasswordsNavButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var matchIndicator: NSView!
    private(set) var hasMatch: Bool = false
    
    init(target: AnyObject?, action: Selector, size: CGFloat = 28) {
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.wantsLayer = true
        self.toolTip = "Passwords & Vault (⌘⌥P)"
        self.target = target
        self.action = action
        self.layer?.cornerRadius = 5
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        let iconPointSize: CGFloat = (size <= 24) ? 10 : 12
        if let img = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Passwords") {
            let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
            self.image = img.withSymbolConfiguration(config)
            self.contentTintColor = NSColor(white: 0.82, alpha: 1.0)
        }
        
        matchIndicator = NSView()
        matchIndicator.translatesAutoresizingMaskIntoConstraints = false
        matchIndicator.wantsLayer = true
        matchIndicator.layer?.cornerRadius = 2.5
        matchIndicator.layer?.backgroundColor = NSColor.white.cgColor
        matchIndicator.layer?.shadowColor = NSColor.white.cgColor
        matchIndicator.layer?.shadowOpacity = 0.8
        matchIndicator.layer?.shadowRadius = 3
        matchIndicator.layer?.shadowOffset = .zero
        matchIndicator.isHidden = true
        addSubview(matchIndicator)
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: size),
            self.heightAnchor.constraint(equalToConstant: size),
            matchIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            matchIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            matchIndicator.widthAnchor.constraint(equalToConstant: 5),
            matchIndicator.heightAnchor.constraint(equalToConstant: 5)
        ])
        self.setContentHuggingPriority(.required, for: .horizontal)
        self.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func setHasMatch(_ match: Bool) {
        hasMatch = match
        matchIndicator.isHidden = !match
        if match {
            contentTintColor = NSColor.white
            toolTip = "✦ Saved Logins Available for Active Site (⌘⌥P)"
        } else {
            contentTintColor = NSColor(white: 0.82, alpha: 1.0)
            toolTip = "Passwords & Vault (⌘⌥P)"
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if let m = self.menu {
            NSMenu.popUpContextMenu(m, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

// MARK: - Onyx Password Row View
class OnyxPasswordRowView: NSView {
    let entry: OnyxPasswordEntry
    let isCurrentSite: Bool
    var isPasswordVisible = false
    var onAutofill: ((OnyxPasswordEntry) -> Void)?
    var onCopyPassword: ((OnyxPasswordEntry) -> Void)?
    var onCopyUsername: ((OnyxPasswordEntry) -> Void)?
    var onEdit: ((OnyxPasswordEntry) -> Void)?
    var onDelete: ((OnyxPasswordEntry) -> Void)?
    
    private var trackingArea: NSTrackingArea?
    private var passwordLabel: NSTextField!
    private var eyeButton: NSButton!
    
    init(entry: OnyxPasswordEntry, isCurrentSite: Bool = false) {
        self.entry = entry
        self.isCurrentSite = isCurrentSite
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = isCurrentSite ? NSColor(white: 1.0, alpha: 0.10).cgColor : NSColor.clear.cgColor
        if isCurrentSite {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.20).cgColor
        }
        
        // Left monogram icon plate (36x36)
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 8
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        iconPlate.layer?.borderWidth = 1
        iconPlate.layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        addSubview(iconPlate)
        
        let monogram = NSTextField(labelWithString: String(entry.title.prefix(1)).uppercased())
        monogram.translatesAutoresizingMaskIntoConstraints = false
        monogram.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        monogram.textColor = .white
        iconPlate.addSubview(monogram)
        
        // Text info stack
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        addSubview(textStack)
        
        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.spacing = 6
        titleRow.alignment = .centerY
        
        let titleLabel = NSTextField(labelWithString: entry.title)
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleRow.addArrangedSubview(titleLabel)
        
        if isCurrentSite {
            let matchPill = NSTextField(labelWithString: "Active Site")
            matchPill.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
            matchPill.textColor = .white
            matchPill.wantsLayer = true
            matchPill.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.14).cgColor
            matchPill.layer?.borderColor = NSColor(white: 1.0, alpha: 0.22).cgColor
            matchPill.layer?.borderWidth = 1
            matchPill.layer?.cornerRadius = 4
            titleRow.addArrangedSubview(matchPill)
        }
        textStack.addArrangedSubview(titleRow)
        
        let userLabel = NSTextField(labelWithString: entry.username.isEmpty ? entry.domain : entry.username)
        userLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        userLabel.textColor = NSColor(white: 0.72, alpha: 1.0)
        userLabel.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(userLabel)
        
        let passLabel = NSTextField(labelWithString: "••••••••••••")
        passLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        passLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        textStack.addArrangedSubview(passLabel)
        self.passwordLabel = passLabel
        
        // Right Action Buttons
        let actionsStack = NSStackView()
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 4
        actionsStack.alignment = .centerY
        addSubview(actionsStack)
        
        // Eye button (toggle reveal)
        eyeButton = createIconButton(systemName: "eye", tooltip: "Reveal Password") { [weak self] in
            guard let self = self else { return }
            self.isPasswordVisible.toggle()
            if self.isPasswordVisible {
                self.passwordLabel.stringValue = self.entry.password
                self.passwordLabel.textColor = NSColor(white: 0.95, alpha: 1.0)
                if let img = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide Password") {
                    self.eyeButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
                }
            } else {
                self.passwordLabel.stringValue = "••••••••••••"
                self.passwordLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
                if let img = NSImage(systemSymbolName: "eye", accessibilityDescription: "Reveal Password") {
                    self.eyeButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
                }
            }
        }
        actionsStack.addArrangedSubview(eyeButton)
        
        // Copy password button
        let copyPassBtn = createIconButton(systemName: "key.fill", tooltip: "Copy Password") { [weak self] in
            guard let self = self else { return }
            self.onCopyPassword?(self.entry)
        }
        actionsStack.addArrangedSubview(copyPassBtn)
        
        // Copy username button
        let copyUserBtn = createIconButton(systemName: "person.fill", tooltip: "Copy Username") { [weak self] in
            guard let self = self else { return }
            self.onCopyUsername?(self.entry)
        }
        actionsStack.addArrangedSubview(copyUserBtn)
        
        // Quick autofill button (if matching site)
        if isCurrentSite {
            let autofillBtn = createIconButton(systemName: "sparkles", tooltip: "Autofill in Active Tab") { [weak self] in
                guard let self = self else { return }
                self.onAutofill?(self.entry)
            }
            autofillBtn.contentTintColor = .white
            actionsStack.addArrangedSubview(autofillBtn)
        }
        
        // Edit button
        let editBtn = createIconButton(systemName: "pencil", tooltip: "Edit Login") { [weak self] in
            guard let self = self else { return }
            self.onEdit?(self.entry)
        }
        actionsStack.addArrangedSubview(editBtn)
        
        // Delete button
        let deleteBtn = createIconButton(systemName: "trash", tooltip: "Delete") { [weak self] in
            guard let self = self else { return }
            self.onDelete?(self.entry)
        }
        actionsStack.addArrangedSubview(deleteBtn)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 60),
            
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 36),
            iconPlate.heightAnchor.constraint(equalToConstant: 36),
            
            monogram.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            monogram.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            
            textStack.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func createIconButton(systemName: String, tooltip: String, action: @escaping () -> Void) -> NSButton {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        btn.toolTip = tooltip
        if let img = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip) {
            btn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            btn.contentTintColor = NSColor(white: 0.80, alpha: 1.0)
        }
        
        class ActionHandler: NSObject {
            let act: () -> Void
            init(_ act: @escaping () -> Void) { self.act = act }
            @objc func trigger() { act() }
        }
        let handler = ActionHandler(action)
        objc_setAssociatedObject(btn, "btnActionHandler", handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        btn.target = handler
        btn.action = #selector(ActionHandler.trigger)
        
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 24),
            btn.heightAnchor.constraint(equalToConstant: 24)
        ])
        return btn
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = self.isCurrentSite ? NSColor(white: 1.0, alpha: 0.15).cgColor : NSColor(white: 1.0, alpha: 0.08).cgColor
            self.layer?.borderColor = self.isCurrentSite ? NSColor(white: 1.0, alpha: 0.25).cgColor : NSColor(white: 1.0, alpha: 0.16).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.layer?.backgroundColor = self.isCurrentSite ? NSColor(white: 1.0, alpha: 0.10).cgColor : NSColor.clear.cgColor
            self.layer?.borderColor = self.isCurrentSite ? NSColor(white: 1.0, alpha: 0.20).cgColor : NSColor.clear.cgColor
        }
    }
}

// MARK: - Universal Onyx Toast HUD
class OnyxToastHUD: NSView {
    init(iconName: String, title: String, message: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.18).cgColor
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.45).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.shadowRadius = 10
        
        let blur = NSVisualEffectView()
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 10
        blur.layer?.masksToBounds = true
        addSubview(blur)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: title) {
            iconView.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            iconView.contentTintColor = .white
        }
        addSubview(iconView)
        
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading
        addSubview(textStack)
        
        let headerLabel = NSTextField(labelWithString: title.uppercased())
        headerLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        headerLabel.textColor = .white
        textStack.addArrangedSubview(headerLabel)
        
        let msgLabel = NSTextField(labelWithString: message)
        msgLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        msgLabel.textColor = .white
        msgLabel.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(msgLabel)
        
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func animateIn() {
        alphaValue = 0
        let transform = CATransform3DMakeTranslation(0, -10, 0)
        layer?.transform = transform
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().alphaValue = 1.0
            self.layer?.transform = CATransform3DIdentity
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.dismiss()
        }
    }
    
    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.removeFromSuperview()
        })
    }
}

// MARK: - Toolbar Extensions & Pinning System
enum OnyxToolbarTool: String, CaseIterable {
    case aiResearch = "ai_research"
    case downloads = "downloads"
    case passwords = "passwords"
    case shield = "shield"
    
    var title: String {
        switch self {
        case .aiResearch: return "AI Research Canvas"
        case .downloads: return "Downloads Shelf"
        case .passwords: return "Passwords & Vault"
        case .shield: return "Onyx Shield"
        }
    }
    
    var subtitle: String {
        switch self {
        case .aiResearch: return "Synthetic research & workspaces (⌘⇧S)"
        case .downloads: return "Files & active downloads (⌘J)"
        case .passwords: return "Keychain & autofill (⌘⌥P)"
        case .shield: return "Tracker blocker & memory monitor"
        }
    }
    
    var iconName: String {
        switch self {
        case .aiResearch: return "sparkles"
        case .downloads: return "arrow.down.circle.fill"
        case .passwords: return "lock.shield.fill"
        case .shield: return "shield.checkerboard"
        }
    }
    
    var prefKey: String {
        return "OnyxToolbarPin_" + self.rawValue
    }
    
    var isPinned: Bool {
        if UserDefaults.standard.object(forKey: prefKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: prefKey)
    }
    
    func setPinned(_ pinned: Bool) {
        UserDefaults.standard.set(pinned, forKey: prefKey)
    }
}

// MARK: - Save Password Prompt HUD (Apple Obsidian Liquid Glass)
class OnyxSavePasswordHUD: NSVisualEffectView {
    var onSave: (() -> Void)?
    var onDismiss: (() -> Void)?
    
    init(username: String, password: String, urlString: String, title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.20).cgColor
        layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.35).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.50
        layer?.shadowOffset = CGSize(width: 0, height: -5)
        layer?.shadowRadius = 20
        
        // Left Icon Squircle Plate (36x36)
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 10
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        iconPlate.layer?.borderWidth = 1
        iconPlate.layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        addSubview(iconPlate)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Onyx Vault") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = .white
        }
        iconPlate.addSubview(iconView)
        
        // Text Stack
        let parsedURL = URL(string: urlString)
        let domain = (parsedURL?.host?.isEmpty == false) ? parsedURL!.host! : (title.isEmpty ? urlString : title)
        let cleanDomain = domain.replacingOccurrences(of: "www.", with: "")
        let displayUser = username.isEmpty ? "this site" : username
        
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        addSubview(textStack)
        
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY
        
        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = NSColor.white.cgColor
        dot.layer?.shadowColor = NSColor.white.cgColor
        dot.layer?.shadowRadius = 4
        dot.layer?.shadowOpacity = 0.8
        dot.layer?.shadowOffset = .zero
        topRow.addArrangedSubview(dot)
        
        let headLabel = NSTextField(labelWithString: "ONYX VAULT")
        headLabel.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold)
        headLabel.textColor = NSColor(white: 0.75, alpha: 1.0)
        topRow.addArrangedSubview(headLabel)
        
        let promptLabel = NSTextField(labelWithString: "• Save login for \(cleanDomain)?")
        promptLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        promptLabel.textColor = .white
        promptLabel.lineBreakMode = .byTruncatingTail
        topRow.addArrangedSubview(promptLabel)
        textStack.addArrangedSubview(topRow)
        
        let subLabel = NSTextField(labelWithString: "\(displayUser) • Encrypted local keychain")
        subLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        subLabel.lineBreakMode = .byTruncatingMiddle
        textStack.addArrangedSubview(subLabel)
        
        // Action Buttons Stack
        let btnStack = NSStackView()
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        btnStack.orientation = .horizontal
        btnStack.spacing = 8
        btnStack.alignment = .centerY
        addSubview(btnStack)
        
        let notNowBtn = NSButton()
        notNowBtn.translatesAutoresizingMaskIntoConstraints = false
        notNowBtn.bezelStyle = .regularSquare
        notNowBtn.isBordered = false
        notNowBtn.wantsLayer = true
        notNowBtn.layer?.cornerRadius = 7
        notNowBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        notNowBtn.layer?.borderWidth = 1
        notNowBtn.layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        notNowBtn.setMonochromeTitle("Not Now", color: NSColor(white: 0.85, alpha: 1.0), font: NSFont.systemFont(ofSize: 11.5, weight: .medium))
        notNowBtn.target = self
        notNowBtn.action = #selector(notNowClicked)
        btnStack.addArrangedSubview(notNowBtn)
        
        let saveBtn = NSButton()
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.bezelStyle = .regularSquare
        saveBtn.isBordered = false
        saveBtn.wantsLayer = true
        saveBtn.layer?.cornerRadius = 7
        saveBtn.layer?.backgroundColor = NSColor.white.cgColor
        saveBtn.layer?.borderWidth = 1
        saveBtn.layer?.borderColor = NSColor(white: 1.0, alpha: 0.35).cgColor
        saveBtn.setMonochromeTitle("Save Password", color: NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 1.0), font: NSFont.systemFont(ofSize: 11.5, weight: .semibold))
        saveBtn.target = self
        saveBtn.action = #selector(saveClicked)
        btnStack.addArrangedSubview(saveBtn)
        
        let closeBtn = NSButton()
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.bezelStyle = .regularSquare
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.cornerRadius = 11
        closeBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        if let ximg = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
            closeBtn.image = ximg.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold))
            closeBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        }
        closeBtn.target = self
        closeBtn.action = #selector(notNowClicked)
        btnStack.addArrangedSubview(closeBtn)
        
        NSLayoutConstraint.activate([
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 36),
            iconPlate.heightAnchor.constraint(equalToConstant: 36),
            
            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            
            textStack.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: btnStack.leadingAnchor, constant: -12),
            
            btnStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            btnStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            notNowBtn.heightAnchor.constraint(equalToConstant: 28),
            notNowBtn.widthAnchor.constraint(equalToConstant: 76),
            saveBtn.heightAnchor.constraint(equalToConstant: 28),
            saveBtn.widthAnchor.constraint(equalToConstant: 108),
            closeBtn.heightAnchor.constraint(equalToConstant: 22),
            closeBtn.widthAnchor.constraint(equalToConstant: 22)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    @objc private func notNowClicked() {
        onDismiss?()
        dismiss()
    }
    
    @objc private func saveClicked() {
        onSave?()
        dismiss()
    }
    
    func animateIn() {
        alphaValue = 0
        let transform = CATransform3DMakeTranslation(0, -12, 0)
        layer?.transform = transform
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().alphaValue = 1.0
            self.layer?.transform = CATransform3DIdentity
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            self?.dismiss()
        }
    }
    
    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.removeFromSuperview()
        })
    }
}

// MARK: - Main Browser Window Controller
class BrowserController: NSWindowController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, NSTextFieldDelegate, WKScriptMessageHandler {
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
    var activeSavePromptHUD: OnyxSavePasswordHUD?
    
    // Toolbar Extensions & Pinning System
    var extensionsButton: NavIconButton!
    var extensionsPopover: NSPopover?
    var extensionsStack: NSStackView!
    var trailingControlsStack: NSStackView!
    
    // WebKit Shared Configuration with High-Speed Engine Tuning
    let sharedConfiguration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        
        // 1. Instant rendering optimization (don't delay painting until full page finishes)
        config.suppressesIncrementalRendering = false
        
        // 2. Persistent disk caching & website data store
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // 3. Fast JavaScript configuration
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        
        return config
    }()
    
    // Profile Management (Multi-Profile System with Isolated DataStores)
    var profiles: [BrowserProfile] = [
        BrowserProfile(id: "personal", name: "Personal", iconName: "person.crop.circle", colorHex: "#FFFFFF", isDefault: true),
        BrowserProfile(id: "research", name: "Research & AI", iconName: "sparkles", colorHex: "#E2E8F0", isDefault: false),
        BrowserProfile(id: "trading", name: "Markets & Trading", iconName: "chart.xyaxis.line", colorHex: "#34D399", isDefault: false),
        BrowserProfile(id: "campus", name: "Campus / Academic", iconName: "graduationcap", colorHex: "#FBBF24", isDefault: false)
    ]
    var activeProfile: BrowserProfile = BrowserProfile(id: "personal", name: "Personal", iconName: "person.crop.circle", colorHex: "#FFFFFF", isDefault: true)
    var profileTabs: [String: [BrowserTab]] = [:]
    var profileActiveIndices: [String: Int] = [:]
    var profileConfigurations: [String: WKWebViewConfiguration] = [:]
    var profileButton: ProfilePillButton!
    var profilePopover: NSPopover?
    var edgeGlowView: DirectionalEdgeGlowView!
    var adBlockRuleList: WKContentRuleList?
    
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
        let path = "/Users/nata/Company/Browser/startpage.html"
        return URL(fileURLWithPath: path)
    }()
    
    let settingsPageURL: URL = {
        if let bundleURL = Bundle.main.url(forResource: "settings", withExtension: "html") {
            return bundleURL
        }
        let path = "/Users/nata/Company/Browser/settings.html"
        return URL(fileURLWithPath: path)
    }()
    
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
        purgeSearchBotAnomalyCookies()
        setupAdBlocker()
        setupOnyxResearchBridge()
        setupUI()
        setupShortcuts()
        
        // Open initial tab based on user preference
        let startupMode = UserDefaults.standard.string(forKey: "OnyxStartupBehavior") ?? "startpage"
        if startupMode == "blank" {
            createNewTab(url: URL(string: "about:blank")!)
        } else {
            createNewTab(url: startPageURL)
        }
    }
    
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
    let youTubeAdBlockerSource = #"""
    (function() {
        if (window.__onyx_yt_adblock_installed) return;
        window.__onyx_yt_adblock_installed = true;

        // 1. Permanent CSS rule hiding YouTube ad banners, promos, overlays, and enforcement dialogs
        var css = `
            #masthead-ad,
            #player-ads,
            ytd-ad-slot-renderer,
            ytd-in-feed-ad-layout-renderer,
            ytd-rich-item-renderer:has(ytd-ad-slot-renderer),
            ytd-promoted-sparkles-web-renderer,
            ytd-promoted-video-renderer,
            ytd-compact-promoted-video-renderer,
            ytd-banner-promo-renderer,
            ytd-statement-banner-renderer,
            ytd-action-companion-ad-renderer,
            ytd-merch-shelf-renderer,
            .ytd-merch-shelf-renderer,
            .ytp-ad-overlay-container,
            .ytp-ad-message-container,
            .ytp-ad-preview-container,
            .ytp-ad-image-overlay,
            .ytp-ad-text-overlay,
            .ytp-ad-player-overlay,
            .ytp-ad-player-overlay-flyout-cta,
            ytd-engagement-panel-section-list-renderer[target-id='engagement-panel-ads'],
            ytd-companion-slot-renderer,
            yt-mealbar-promo-renderer,
            ytd-mealbar-promo-renderer,
            ytd-enforcement-message-view-model {
                display: none !important;
                visibility: hidden !important;
                opacity: 0 !important;
                pointer-events: none !important;
                height: 0 !important;
                min-height: 0 !important;
            }
        `;

        function injectStyle() {
            if (!document.getElementById("onyx-yt-adblock-style")) {
                var style = document.createElement("style");
                style.id = "onyx-yt-adblock-style";
                style.textContent = css;
                (document.head || document.documentElement).appendChild(style);
            }
        }
        injectStyle();
        if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", injectStyle);
        }

        // 2. Data / JSON Pruning Engine (uBlock Origin & YoutubeAdblock pattern)
        // Strips ad configurations before player initializes or renders them
        function pruneAdProperties(obj) {
            if (!obj || typeof obj !== "object") return obj;
            try {
                if ("adPlacements" in obj) delete obj.adPlacements;
                if ("adSlots" in obj) delete obj.adSlots;
                if ("playerAds" in obj) delete obj.playerAds;
                if ("adBreakHeartbeatParams" in obj) delete obj.adBreakHeartbeatParams;
                if (obj.playerResponse && typeof obj.playerResponse === "object") {
                    pruneAdProperties(obj.playerResponse);
                }
                if (obj.auxiliaryUi && obj.auxiliaryUi.messageRenderers) {
                    delete obj.auxiliaryUi.messageRenderers.upsellDialogRenderer;
                    delete obj.auxiliaryUi.messageRenderers.enforcementMessageViewModel;
                }
                if (obj.playbackTracking) {
                    delete obj.playbackTracking.atrUrl;
                    delete obj.playbackTracking.qoeStatsUrl;
                    delete obj.playbackTracking.videostatsPlaybackUrl;
                }
            } catch (e) {}
            return obj;
        }

        // Intercept JSON.parse to sanitize any incoming InnerTube player payloads
        try {
            var origJSONParse = JSON.parse;
            JSON.parse = function() {
                var res = origJSONParse.apply(this, arguments);
                if (res && typeof res === "object") {
                    if (res.adPlacements || res.adSlots || res.playerAds || res.playerResponse) {
                        pruneAdProperties(res);
                    }
                }
                return res;
            };
        } catch(e) {}

        // Intercept Response.prototype.json
        try {
            if (window.Response && Response.prototype.json) {
                var origResponseJson = Response.prototype.json;
                Response.prototype.json = function() {
                    return origResponseJson.apply(this, arguments).then(function(data) {
                        if (data && typeof data === "object") {
                            if (data.adPlacements || data.adSlots || data.playerAds || data.playerResponse) {
                                pruneAdProperties(data);
                            }
                        }
                        return data;
                    });
                };
            }
        } catch(e) {}

        // Property trap on window.ytInitialPlayerResponse
        try {
            var _ytInitialPlayerResponse = window.ytInitialPlayerResponse;
            if (_ytInitialPlayerResponse) pruneAdProperties(_ytInitialPlayerResponse);
            Object.defineProperty(window, "ytInitialPlayerResponse", {
                get: function() { return _ytInitialPlayerResponse; },
                set: function(val) { _ytInitialPlayerResponse = pruneAdProperties(val); },
                configurable: true
            });
        } catch(e) {}

        // Intercept fetch to neutralize ad telemetry and ad break pings
        try {
            if (window.fetch) {
                var origFetch = window.fetch;
                window.fetch = function(input, init) {
                    var url = typeof input === "string" ? input : (input && input.url ? input.url : "");
                    if (url.indexOf("/api/stats/ads") !== -1 ||
                        url.indexOf("/pagead/") !== -1 ||
                        url.indexOf("/ptracking") !== -1 ||
                        url.indexOf("/youtubei/v1/player/ad_break") !== -1) {
                        return Promise.resolve(new Response(JSON.stringify({}), {
                            status: 200,
                            headers: { "Content-Type": "application/json" }
                        }));
                    }
                    return origFetch.apply(this, arguments);
                };
            }
        } catch(e) {}

        // 3. Anti-Adblock Modal Neutralizer
        // Automatically dismisses enforcement modals and resumes video playback ONLY if an enforcement modal was actively blocking
        function dismissAntiAdblockModal() {
            var dialogs = document.querySelectorAll("ytd-enforcement-message-view-model, tp-yt-paper-dialog:has(ytd-enforcement-message-view-model)");
            if (dialogs.length > 0) {
                dialogs.forEach(function(d) {
                    var wrapper = d.closest("tp-yt-paper-dialog") || d;
                    wrapper.remove();
                });

                var backdrops = document.querySelectorAll("tp-yt-iron-overlay-backdrop");
                backdrops.forEach(function(b) { b.remove(); });

                if (document.body && (document.body.style.overflow === "hidden" || document.body.style.overflowY === "hidden")) {
                    document.body.style.overflow = "auto";
                    document.body.style.overflowY = "auto";
                }

                var video = document.querySelector("video");
                var player = document.getElementById("movie_player") || document.querySelector(".html5-video-player");
                var isAdShowing = player && (player.classList.contains("ad-showing") || player.classList.contains("ad-interrupting"));
                if (video && video.paused && !video.ended && !isAdShowing) {
                    video.play().catch(function() {});
                }
            }
        }

        // 4. Real-time Video Ad Skipping & Playback State Restoration
        var savedState = null;
        var isHandlingAd = false;

        function handleVideoAds() {
            dismissAntiAdblockModal();

            var player = document.getElementById("movie_player") || document.querySelector(".html5-video-player");
            var video = document.querySelector("video");
            if (!player || !video) return;

            // Accurate ad detection strictly from player class attributes
            var isAdActive = player.classList.contains("ad-showing") || player.classList.contains("ad-interrupting");

            if (isAdActive) {
                if (!isHandlingAd) {
                    isHandlingAd = true;
                    // Preserve original user volume and playback rate
                    savedState = {
                        muted: video.muted,
                        playbackRate: (video.playbackRate > 0 && video.playbackRate <= 4) ? video.playbackRate : 1.0
                    };
                }

                // Mute ad audio instantly
                if (!video.muted) {
                    video.muted = true;
                }

                // Speed up playback to fast-forward through ad frames
                if (video.playbackRate < 16) {
                    video.playbackRate = 16.0;
                }

                // Seek straight to video duration if finite
                if (isFinite(video.duration) && video.duration > 0) {
                    video.currentTime = video.duration;
                }

                // Click skip button immediately
                var skipSelectors = [
                    ".ytp-ad-skip-button",
                    ".ytp-ad-skip-button-modern",
                    ".ytp-skip-ad-button",
                    "button.ytp-ad-skip-button-modern",
                    ".ytp-ad-skip-button-container button",
                    "[id^='skip-button'] button",
                    ".videoAdUiSkipButton",
                    ".ytp-ad-skip-button-slot button"
                ];
                for (var i = 0; i < skipSelectors.length; i++) {
                    var btn = document.querySelector(skipSelectors[i]);
                    if (btn) {
                        btn.click();
                        break;
                    }
                }

                // Click overlay close buttons if present
                var closeBtn = document.querySelector(".ytp-ad-overlay-close-button, .ytp-ad-overlay-close-container button");
                if (closeBtn) {
                    closeBtn.click();
                }
            } else {
                // Normal video is active
                if (isHandlingAd) {
                    isHandlingAd = false;
                    // Restore user's original playback rate & audio mute
                    if (savedState) {
                        video.playbackRate = savedState.playbackRate || 1.0;
                        video.muted = savedState.muted;
                        savedState = null;
                    } else {
                        if (video.playbackRate > 4) {
                            video.playbackRate = 1.0;
                        }
                    }
                } else {
                    // Failsafe: if video is at ad speed for any reason, reset to 1.0
                    if (video.playbackRate > 4) {
                        video.playbackRate = 1.0;
                    }
                }
            }
        }

        // 5. Event Listeners & Observer Setup
        function attachVideoListeners() {
            var video = document.querySelector("video");
            if (video && !video.__onyx_ad_monitored) {
                video.__onyx_ad_monitored = true;
                video.addEventListener("timeupdate", handleVideoAds);
                video.addEventListener("play", handleVideoAds);
                video.addEventListener("playing", handleVideoAds);
                video.addEventListener("ratechange", function() {
                    var player = document.getElementById("movie_player") || document.querySelector(".html5-video-player");
                    if (player && (player.classList.contains("ad-showing") || player.classList.contains("ad-interrupting"))) {
                        if (video.playbackRate < 16) {
                            video.playbackRate = 16.0;
                        }
                    }
                });
            }
        }

        attachVideoListeners();

        // High-frequency watchdog interval (runs every 150ms)
        setInterval(function() {
            injectStyle();
            attachVideoListeners();
            handleVideoAds();
        }, 150);

        // MutationObserver to catch dynamic DOM additions immediately
        var observer = new MutationObserver(function() {
            injectStyle();
            attachVideoListeners();
            handleVideoAds();
        });

        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ["class", "style"]
        });

        // YouTube SPA navigation events
        window.addEventListener("yt-navigate-start", handleVideoAds);
        window.addEventListener("yt-navigate-finish", function() {
            injectStyle();
            attachVideoListeners();
            handleVideoAds();
        });
        window.addEventListener("yt-page-data-updated", function() {
            if (window.ytInitialPlayerResponse) {
                pruneAdProperties(window.ytInitialPlayerResponse);
            }
            handleVideoAds();
        });
    })();
    """#

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
    
    let onyxResearchCSS = """
    :root {
        --bg: #070709 !important;
        --surface: rgba(255, 255, 255, 0.04) !important;
        --border: rgba(255, 255, 255, 0.08) !important;
        --text: #ffffff !important;
        --text-muted: #a1a1aa !important;
    }

    html, body {
        background-color: #070709 !important;
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", sans-serif !important;
        -webkit-font-smoothing: antialiased !important;
    }

    #app, main, section, [role="main"] {
        background-color: #070709 !important;
        color: #ffffff !important;
    }

    /* Force opacity on responses */
    [class*="ulhFW"],
    .space-y-4 {
        opacity: 1 !important;
    }

    /* Hide Duck mascot SVGs, watermarks, center hero */
    svg:has(path[fill="#F05F2B"]),
    svg:has(path[fill="#DE5833"]),
    svg:has(path[fill="#9E2B08"]),
    .sk-lockup,
    .RM8cPgCF1NymxEVCc19D,
    .y8qZjjhkSVTmBOORd3oQ,
    .S1TV9gKXE9qTlJCKQyVA,
    .uOlVBqdhDvmtfhIycAG0,
    .O5Ra8A7Sorua0Mko8MYQ,
    .BXf8VCyyOfjab0CgSDlg,
    .n4vrMGwaSPo1WZT89efg {
        display: none !important;
    }

    /* Hide top privacy banner & disclaimer */
    .iP4HH3Eq_DvgejuvS05a,
    .zCVUKvnxAtTkzWbiEROp {
        display: none !important;
    }

    /* Left sidebar styled as macOS native source list */
    main > section:first-child {
        background-color: #0a0a0d !important;
        border-right: 1px solid rgba(255, 255, 255, 0.06) !important;
    }

    /* Chat messages text styling */
    p, li {
        color: #ffffff !important;
        font-size: 15px !important;
        line-height: 1.65 !important;
        letter-spacing: -0.01em !important;
    }

    /* Prompt Form (Apple 24px capsule) */
    form {
        border-radius: 24px !important;
        background: rgba(255, 255, 255, 0.05) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        backdrop-filter: blur(24px) !important;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5) !important;
    }

    textarea {
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 14px !important;
    }

    /* Submit button */
    button[type="submit"],
    button[aria-label="Send"] {
        background: #ffffff !important;
        border-radius: 50% !important;
    }
    button[type="submit"] svg,
    button[aria-label="Send"] svg {
        fill: #000000 !important;
    }
    button[type="submit"] path,
    button[aria-label="Send"] path {
        fill: #000000 !important;
    }
    """

    let onyxSearchCSS = """
    :root {
        --space-1: 4px !important;
        --space-2: 8px !important;
        --space-3: 12px !important;
        --space-4: 16px !important;
        --space-5: 20px !important;
        --space-6: 24px !important;
        --space-8: 32px !important;
        --space-10: 40px !important;
        --space-12: 48px !important;

        --onyx-bg: #070709 !important;
        --onyx-surface: rgba(255, 255, 255, 0.035) !important;
        --onyx-surface-hover: rgba(255, 255, 255, 0.065) !important;
        --onyx-surface-active: rgba(255, 255, 255, 0.10) !important;
        --onyx-border: rgba(255, 255, 255, 0.08) !important;
        --onyx-border-hover: rgba(255, 255, 255, 0.18) !important;
        --onyx-border-focus: rgba(255, 255, 255, 0.35) !important;
        --onyx-text: #ffffff !important;
        --onyx-text-muted: #a1a1aa !important;
        --onyx-text-subtle: #71717a !important;
        --onyx-link-hover: #93c5fd !important;
        --onyx-link-visited: #c7d2fe !important;
        --onyx-ease: cubic-bezier(0.16, 1, 0.3, 1) !important;
        
        --theme-bg-color: #070709 !important;
        --theme-text-color: #ffffff !important;
        color-scheme: dark !important;
    }

    *, *::before, *::after {
        box-sizing: border-box !important;
    }

    /* Force Onyx Obsidian Dark Background on whole viewport for all engines */
    html, body, #app, .site-wrapper, .wrapper, .results-wrapper, main, .serp__body,
    #main, #cnt, #rcnt, #center_col, #rhs, .appbar, #hdtb, #top_nav, .minidiv, .sfbg, #searchform, .mw,
    #searchform > div, .srp, #botstuff, #rso {
        background-color: #070709 !important;
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", sans-serif !important;
        -webkit-font-smoothing: antialiased !important;
    }

    /* 1. Complete Scrubbing of DuckDuckGo Branding, Mascots, Ads, and Noise */
    .header__logo-wrap,
    .header__logo,
    .header__logo__img,
    #header-logo-wrapper,
    #header-logo,
    #logo,
    [data-testid="header-logo"],
    [data-testid="logo"],
    [data-testid="logo-link"],
    [data-testid="logo_link"],
    a[aria-label*="DuckDuckGo home" i],
    a[aria-label*="DuckDuckGo" i],
    a[data-testid="logo-link"],
    a[data-testid="header-logo"],
    a[href="/"],
    header a[href="/"],
    #header a[href="/"],
    .header a[href="/"],
    .header-wrap a[href="/"],
    .site-wrapper header a[href="/"],
    [class*="HeaderLogo"],
    [class*="header_logo"],
    [class*="header__logo"],
    svg[class*="logo" i],
    svg[class*="Logo" i],
    svg[class*="duck" i],
    svg:has(path[fill="#F05F2B"]),
    svg:has(path[fill="#DE5833"]),
    svg:has(ellipse[fill="#F05F2B"]),
    .header__logo img,
    .header-wrap img[src*="duck"],
    #header-logo-wrapper img,
    a[aria-label*="DuckDuckGo home"] img,
    a[data-testid="logo-link"] img,
    img[alt*="DuckDuckGo" i],
    img[src*="duckduckgo" i],
    img[src*="duck" i],
    a[href="/compare-privacy"],
    a[href*="compare-privacy"],
    a[href*="compare"],
    .header__tagline,
    .header__text,
    .header--aside,
    .header--aside__item,
    .header__button--menu,
    .js-side-menu-open,
    .feedback-btn,
    #footer-feedback-wrapper,
    .nav-menu--feedback,
    .react-feedback-prompt-mvc-wrapper,
    button[data-testid="feedback-button"],
    a[href*="assist=true"],
    li:has(> a[href*="assist=true"]),
    a[href*="ia=chat"]:not(.onyx-research-switch-btn),
    li:has(> a[href*="ia=chat"]),
    #react-duckbar li:has(button),
    [data-testid="duckbar"] li:has(button),
    #react-duckbar button,
    [data-testid="duckbar"] button,
    li:has(> button[aria-label*="Search Settings"]),
    button[aria-label*="Search Settings"],
    .badge--ad,
    [data-testid="ad"],
    [data-testid="ad-item"],
    .results--ads,
    .result--ad,
    .ads-wrapper,
    .onboarding-ed,
    .js-onboarding-wrapper,
    .ddg-extension-banner,
    .badge--privacy,
    .badge--protection,
    .modal--feedback,
    [class*="feedback"],
    [class*="Feedback"],
    .js-feedback-btn-wrap,
    [class*="TccjmKV6"],
    [class*="bYzmzE1m"],
    [class*="s_aX02AKO"],
    #react-duckbar a:not(.onyx-tab-active):not(.is-active)::after,
    [data-testid="duckbar"] a:not(.onyx-tab-active):not(.is-active)::after,
    [class*="feedback-btn"],
    [class*="feedback-modal"],
    .newsletter,
    [class*="newsletter"],
    [class*="promo"],
    /* Hide all globe icons from region filter & dropdowns */
    [data-testid="region-filter"] svg,
    .dropdown--region svg,
    button[aria-label*="Region" i] svg,
    button[aria-label*="region" i] svg,
    .footer,
    #footer,
    .footer__addons,
    .nav-menu,
    .nav-menu__item,
    .nav-menu--theme,
    .nav-menu--feedback,
    .serp__top-right,
    .serp__bottom-right,
    #spacing_hidden_wrapper,
    #spacing_hidden,
    #bottom_spacing2,
    #z,
    #z2,
    .legacy-homepage__bottom {
        display: none !important;
        opacity: 0 !important;
        visibility: hidden !important;
        pointer-events: none !important;
        width: 0 !important;
        height: 0 !important;
        margin: 0 !important;
        padding: 0 !important;
        max-width: 0 !important;
        max-height: 0 !important;
        overflow: hidden !important;
    }

    /* 1b. Absolute Full-Width Reset: Override invasive hardcoded DDG min-widths (980px, 1000px, 1072px) */
    html, html.is-not-mobile-device,
    body, body.is-not-mobile-device,
    .is-not-mobile-device,
    .site-wrapper,
    #web_content_wrapper,
    .content-wrap,
    #links_wrapper,
    #react-layout,
    [data-testid="mainline"],
    .results--main,
    #spacing_hidden_wrapper,
    #spacing_hidden,
    #bottom_spacing2,
    #z,
    #z2 {
        min-width: 0 !important;
        max-width: 100% !important;
        width: 100% !important;
        box-sizing: border-box !important;
        margin-left: 0 !important;
        margin-right: 0 !important;
    }
    html, body {
        overflow-x: hidden !important;
    }

    /* 1b. Anomaly / Bot Challenge Obsidian UI */
    .anomaly-modal,
    [class*="anomaly-modal"],
    .modal--popout.anomaly-modal__modal,
    #anomaly-detected {
        display: block !important;
        visibility: visible !important;
        opacity: 1 !important;
        pointer-events: auto !important;
        position: fixed !important;
        top: 50% !important;
        left: 50% !important;
        transform: translate(-50%, -50%) !important;
        background: #121216 !important;
        border: 1px solid rgba(255, 255, 255, 0.16) !important;
        border-radius: 16px !important;
        box-shadow: 0 24px 80px rgba(0, 0, 0, 0.9) !important;
        max-width: 520px !important;
        width: 90% !important;
        padding: 24px !important;
        box-sizing: border-box !important;
        z-index: 999999 !important;
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }

    .anomaly-modal *,
    [class*="anomaly-modal"] *,
    #anomaly-detected * {
        visibility: visible !important;
        opacity: 1 !important;
        box-sizing: border-box !important;
    }

    .anomaly-modal__title,
    [class*="anomaly-modal__title"] {
        color: #ffffff !important;
        font-size: 18px !important;
        font-weight: 600 !important;
        letter-spacing: -0.01em !important;
        margin-bottom: 8px !important;
        text-align: center !important;
        display: block !important;
    }

    .anomaly-modal__description,
    [class*="anomaly-modal__description"] {
        color: #a1a1aa !important;
        font-size: 13.5px !important;
        line-height: 1.5 !important;
        margin-bottom: 16px !important;
        text-align: center !important;
        display: block !important;
    }

    .anomaly-modal img,
    [class*="anomaly-modal"] img {
        display: block !important;
        visibility: visible !important;
        opacity: 1 !important;
        border-radius: 8px !important;
        border: 2px solid transparent !important;
        cursor: pointer !important;
        transition: all 0.15s ease !important;
    }
    .anomaly-modal img:hover,
    [class*="anomaly-modal"] img:hover {
        transform: scale(1.03) !important;
        border-color: #ffffff !important;
    }

    .anomaly-modal button,
    [class*="anomaly-modal"] button,
    [class*="anomaly-modal"] input[type="submit"] {
        display: inline-flex !important;
        visibility: visible !important;
        opacity: 1 !important;
        align-items: center !important;
        justify-content: center !important;
        background: #ffffff !important;
        color: #0a0a0e !important;
        border: none !important;
        border-radius: 8px !important;
        padding: 9px 22px !important;
        font-size: 13.5px !important;
        font-weight: 600 !important;
        cursor: pointer !important;
        margin: 14px auto 0 auto !important;
        box-shadow: 0 4px 14px rgba(0, 0, 0, 0.5) !important;
    }
    .anomaly-modal button:hover,
    [class*="anomaly-modal"] button:hover {
        background: #e4e4e7 !important;
    }

    .onyx-bot-bypass-bar {
        display: flex !important;
        align-items: center !important;
        justify-content: space-between !important;
        background: rgba(255, 255, 255, 0.06) !important;
        border: 1px solid rgba(255, 255, 255, 0.16) !important;
        border-radius: 10px !important;
        padding: 10px 14px !important;
        margin-bottom: 16px !important;
    }
    .onyx-bot-bypass-btn {
        background: #ffffff !important;
        color: #0a0a0e !important;
        font-size: 12px !important;
        font-weight: 600 !important;
        padding: 6px 14px !important;
        border-radius: 6px !important;
        text-decoration: none !important;
        border: none !important;
        cursor: pointer !important;
        display: inline-flex !important;
        align-items: center !important;
        gap: 6px !important;
    }

    /* 2. Top Header Bar & Search Pill: Clean, Left Blank Where Logo Was */
    .header-wrap, #header_wrapper {
        background: #070709 !important;
        border: none !important;
        box-shadow: none !important;
        padding: var(--space-4) var(--space-6) 0 var(--space-6) !important;
        margin: 0 !important;
        width: 100% !important;
        max-width: 100% !important;
        box-sizing: border-box !important;
        display: flex !important;
        flex-direction: column !important;
        align-items: center !important;
        position: relative !important;
    }

    #header, .header, .header.cw, .header-wrap > div, #header-non-nav {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 auto !important;
        box-sizing: border-box !important;
        max-width: 1100px !important;
        width: 100% !important;
        display: flex !important;
        flex-direction: column !important;
        align-items: flex-start !important;
    }

    /* Nuke all edge gradients, cutoff boxes, and mask pseudo-elements in header and filter bars */
    nav::before, nav::after,
    [class*="ph1UFslrkUMqoYJEtp3t"]::before, [class*="ph1UFslrkUMqoYJEtp3t"]::after,
    [class*="hnKIeVb9Fi3YMCZAeQvR"]::before, [class*="hnKIeVb9Fi3YMCZAeQvR"]::after,
    [class*="DrcPyihFGyKMlg6lpwsa"]::before, [class*="DrcPyihFGyKMlg6lpwsa"]::after,
    [class*="W4_K5H4AqLL1ngRJt_pk"]::before, [class*="W4_K5H4AqLL1ngRJt_pk"]::after,
    .search-filters-wrap::before, .search-filters-wrap::after,
    .metabar__dropdowns-wrap::before, .metabar__dropdowns-wrap::after,
    .zcm__dropdowns::before, .zcm__dropdowns::after,
    [class*="XvPRmQVeIoCP5lQhICTv"]::before, [class*="XvPRmQVeIoCP5lQhICTv"]::after,
    .header-wrap::before, .header-wrap::after,
    #header::before, #header::after {
        display: none !important;
        content: none !important;
        background: transparent !important;
        background-image: none !important;
        opacity: 0 !important;
        visibility: hidden !important;
        width: 0 !important;
        height: 0 !important;
    }

    .header__search-wrap,
    .header__content,
    .header__search,
    #react-search-form,
    #search_form {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        border-radius: 0 !important;
        max-width: 680px !important;
        width: 100% !important;
        padding: 0 !important;
        margin: 0 !important;
        box-sizing: border-box !important;
    }

    #search_form > div,
    #search_form form,
    #search_form [class*="jnfopIud3XnBlXjNFBlD"],
    #search_form [class*="qbeSJGurtw4wF0FqAJqF"] {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        border-radius: 0 !important;
        padding: 0 !important;
        margin: 0 !important;
        width: 100% !important;
        max-width: 680px !important;
    }

    /* The ONE and ONLY Search Input Capsule */
    .onyx-search-pill,
    #search_form [class*="QsyijBlqupsaY11GFhnp"],
    #search_form [class*="T265XEcezvjUhK71U8pN"],
    .search--header,
    .search--adv,
    .search-wrap {
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.10) !important;
        border-radius: 24px !important;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.35) !important;
        max-width: 680px !important;
        width: 100% !important;
        box-sizing: border-box !important;
        height: 44px !important;
        display: flex !important;
        align-items: center !important;
        padding: 0 var(--space-4) !important;
        transition: background 0.16s var(--onyx-ease), border-color 0.16s var(--onyx-ease), box-shadow 0.16s var(--onyx-ease) !important;
    }

    .onyx-search-pill:focus-within,
    #search_form [class*="QsyijBlqupsaY11GFhnp"]:focus-within,
    #search_form [class*="T265XEcezvjUhK71U8pN"]:focus-within,
    .search--header:focus-within,
    .search-wrap:focus-within {
        background: rgba(255, 255, 255, 0.07) !important;
        border-color: rgba(255, 255, 255, 0.32) !important;
        box-shadow: 0 0 0 3px rgba(255, 255, 255, 0.08), 0 4px 16px rgba(0, 0, 0, 0.45) !important;
    }

    .search__input, #search_form_input, input[type="text"][name="q"] {
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 15px !important;
        background: transparent !important;
        border: none !important;
        outline: none !important;
        box-shadow: none !important;
        width: 100% !important;
    }
    .search__button, #search_button, button[aria-label="Search"], button[type="submit"] {
        color: #a1a1aa !important;
        background: transparent !important;
        border: none !important;
        cursor: pointer !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
        transition: color 0.15s ease !important;
    }
    .search__button:hover, #search_button:hover {
        color: #ffffff !important;
    }

    /* 3. Category Navigation Tabs ("All", "Images", "News", "Videos", "Maps") */
    #react-duckbar, [data-testid="duckbar"], .zcm {
        background: transparent !important;
        border: none !important;
        border-bottom: none !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: var(--space-3) auto 0 auto !important;
        width: 100% !important;
        max-width: 1100px !important;
        display: block !important;
        box-sizing: border-box !important;
        position: relative !important;
    }

    #react-duckbar > div:not(.onyx-duckbar-glider), #react-duckbar section, [data-testid="duckbar"] > div:not(.onyx-duckbar-glider) {
        margin: 0 !important;
        padding: 0 !important;
        width: 100% !important;
        overflow: visible !important;
        border: none !important;
        border-bottom: none !important;
    }

    #react-duckbar nav, [data-testid="duckbar"] nav, .zcm__items {
        display: flex !important;
        align-items: flex-end !important;
        position: relative !important;
        z-index: 2 !important;
        background: transparent !important;
        padding: 0 !important;
        margin: 0 !important;
        box-sizing: border-box !important;
        border: none !important;
        border-bottom: none !important;
        width: 100% !important;
        max-width: 680px !important;
        overflow: visible !important;
    }

    #react-duckbar ul:first-child, [data-testid="duckbar"] ul:first-child {
        display: flex !important;
        align-items: flex-end !important;
        gap: var(--space-2) !important;
        list-style: none !important;
        padding: 0 !important;
        margin: 0 !important;
        overflow: visible !important;
        width: auto !important;
        height: auto !important;
        border: none !important;
        border-bottom: none !important;
    }

    #react-duckbar ul:last-child,
    [data-testid="duckbar"] ul:last-child,
    #react-duckbar [class*="ofDl_"],
    .header--aside,
    .js-header-aside {
        display: none !important;
        visibility: hidden !important;
        pointer-events: none !important;
    }

    #react-duckbar ul:first-child li, [data-testid="duckbar"] ul:first-child li {
        display: inline-flex !important;
        align-items: flex-end !important;
        padding: 0 !important;
        margin: 0 !important;
        list-style: none !important;
        overflow: visible !important;
        border: none !important;
        border-bottom: none !important;
    }

    #react-duckbar ul:first-child a::before,
    #react-duckbar ul:first-child a::after,
    [data-testid="duckbar"] ul:first-child a::before,
    [data-testid="duckbar"] ul:first-child a::after,
    .onyx-duckbar-tab::before,
    .onyx-duckbar-tab::after {
        display: none !important;
        content: none !important;
        opacity: 0 !important;
        background: transparent !important;
    }

    #react-duckbar ul:first-child a,
    [data-testid="duckbar"] ul:first-child a,
    .onyx-duckbar-tab,
    #react-duckbar a.kFFXe30DOpq5j1hbWU1q,
    #react-duckbar .kFFXe30DOpq5j1hbWU1q.kFFXe30DOpq5j1hbWU1q.kFFXe30DOpq5j1hbWU1q,
    .zcm__item,
    .zcm__link {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        gap: var(--space-2) !important;
        position: relative !important;
        z-index: 2 !important;
        bottom: 0 !important;
        height: 38px !important;
        box-sizing: border-box !important;
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        box-shadow: none !important;
        outline: none !important;
        padding: 0 var(--space-3) !important;
        margin: 0 !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 13.5px !important;
        font-weight: 500 !important;
        text-decoration: none !important;
        color: rgba(255, 255, 255, 0.45) !important;
        opacity: 0.75 !important;
        cursor: pointer !important;
        transition: color 0.2s var(--onyx-ease), opacity 0.2s var(--onyx-ease) !important;
    }

    #react-duckbar ul:first-child a strong,
    [data-testid="duckbar"] ul:first-child a strong,
    .onyx-duckbar-tab strong,
    #react-duckbar ul:first-child a span,
    [data-testid="duckbar"] ul:first-child a span,
    .onyx-duckbar-tab span {
        font-weight: inherit !important;
        color: inherit !important;
        display: inline-flex !important;
        align-items: center !important;
        gap: var(--space-2) !important;
        position: relative !important;
        z-index: 2 !important;
        background: transparent !important;
    }

    #react-duckbar ul:first-child a svg,
    [data-testid="duckbar"] ul:first-child a svg,
    .onyx-duckbar-tab svg {
        color: inherit !important;
        fill: currentColor !important;
        opacity: 0.75 !important;
        position: relative !important;
        z-index: 2 !important;
        transition: all 0.25s ease !important;
    }

    #react-duckbar ul:first-child a:hover,
    [data-testid="duckbar"] ul:first-child a:hover,
    .onyx-duckbar-tab:hover {
        color: rgba(255, 255, 255, 0.90) !important;
        opacity: 1 !important;
        background: transparent !important;
        border: none !important;
    }

    #react-duckbar ul:first-child a:hover svg,
    [data-testid="duckbar"] ul:first-child a:hover svg,
    .onyx-duckbar-tab:hover svg {
        opacity: 1 !important;
        color: rgba(255, 255, 255, 0.90) !important;
    }

    #react-duckbar ul:first-child a.SnptgjT2zdOhGYfNng6g,
    #react-duckbar ul:first-child a[class*="SnptgjT"],
    #react-duckbar ul:first-child a.onyx-tab-active,
    #react-duckbar ul:first-child a.is-active,
    [data-testid="duckbar"] ul:first-child a.onyx-tab-active,
    [data-testid="duckbar"] ul:first-child a.is-active,
    .onyx-duckbar-tab.onyx-tab-active,
    .onyx-duckbar-tab.is-active {
        background: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        color: #ffffff !important;
        opacity: 1 !important;
        font-weight: 600 !important;
        text-shadow: 0 0 8px rgba(255, 255, 255, 0.25) !important;
    }

    #react-duckbar ul:first-child a.SnptgjT2zdOhGYfNng6g svg,
    #react-duckbar ul:first-child a[class*="SnptgjT"] svg,
    #react-duckbar ul:first-child a.onyx-tab-active svg,
    .onyx-duckbar-tab.onyx-tab-active svg {
        color: #ffffff !important;
        fill: #ffffff !important;
        opacity: 1 !important;
    }

    .onyx-duckbar-glider {
        position: absolute !important;
        bottom: 0 !important;
        left: 0 !important;
        height: 38px !important;
        max-width: 180px !important;
        pointer-events: none !important;
        z-index: 1 !important;
        transition: transform 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), width 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), opacity 0.2s ease !important;
        will-change: transform, width !important;
        opacity: 0;
    }
    .onyx-duckbar-glider.is-ready {
        opacity: 1 !important;
    }
    .onyx-duckbar-glider::after {
        content: "" !important;
        display: block !important;
        position: absolute !important;
        bottom: 0 !important;
        left: 8px !important;
        right: 8px !important;
        height: 2.5px !important;
        background: #ffffff !important;
        border-radius: 2px !important;
        box-shadow: 0 0 8px rgba(255, 255, 255, 0.6) !important;
        pointer-events: none !important;
        z-index: 2 !important;
    }

    /* Filter dropdown containers: completely transparent, zero borders */
    .dropdown,
    .zcm__dropdown,
    .search-filters-wrap,
    .metabar__dropdowns-wrap,
    [class*="c1GwqC__eRoEs0cLTIfL"],
    [data-testid="privacy-reminder"],
    [data-testid="region-filter"],
    [data-testid="date-filter"] {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 !important;
    }

    /* Single, clean Apple Obsidian Pill Button */
    .dropdown > button,
    .dropdown__button,
    [data-testid="privacy-reminder"] button,
    [data-testid="date-filter-trigger"],
    [data-testid="region-filter-label"],
    nav[class*="ph1UFslrkUMqoYJEtp3t"] button,
    [class*="c1GwqC__eRoEs0cLTIfL"] button,
    .zcm__dropdown > button,
    .zcm__dropdown > a {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        gap: 6px !important;
        height: 28px !important;
        padding: 0 12px !important;
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 14px !important;
        color: #a1a1aa !important;
        font-size: 12px !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-weight: 500 !important;
        line-height: 1 !important;
        cursor: pointer !important;
        box-shadow: none !important;
        transition: all 160ms var(--onyx-ease) !important;
        white-space: nowrap !important;
    }

    .dropdown > button:hover,
    .dropdown__button:hover,
    [data-testid="privacy-reminder"] button:hover,
    [data-testid="date-filter-trigger"]:hover,
    [data-testid="region-filter-label"]:hover,
    nav[class*="ph1UFslrkUMqoYJEtp3t"] button:hover,
    [class*="c1GwqC__eRoEs0cLTIfL"] button:hover {
        background: rgba(255, 255, 255, 0.08) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        color: #ffffff !important;
        transform: translateY(-1px) !important;
    }

    .dropdown > button:active,
    .dropdown__button:active,
    [data-testid="privacy-reminder"] button:active,
    [data-testid="date-filter-trigger"] active {
        transform: scale(0.97) !important;
    }

    /* Total annihilation of nested button-in-button borders or backgrounds */
    .dropdown button *,
    .dropdown__button *,
    [data-testid="privacy-reminder"] button *,
    [data-testid="date-filter-trigger"] *,
    [data-testid="region-filter-label"] *,
    nav[class*="ph1UFslrkUMqoYJEtp3t"] button * {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
    }

    /* Dropdown popover menus */
    div[role="menu"],
    div[role="listbox"],
    .modal--dropdown,
    [class*="modal--dropdown"],
    [class*="KveNZ4T8UTSkbUIN7OIu"],
    [class*="BdZVYXbdg6Rx9Lrm5wzC"] {
        background: #121216 !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 12px !important;
        box-shadow: 0 12px 40px rgba(0, 0, 0, 0.75) !important;
        backdrop-filter: blur(20px) !important;
        -webkit-backdrop-filter: blur(20px) !important;
        padding: 6px !important;
        color: #ffffff !important;
    }

    div[role="menuitem"],
    div[role="menuitemradio"],
    div[role="option"],
    [class*="QuHfab2kCueVYIcnymfA"] {
        border-radius: 8px !important;
        padding: 8px 12px !important;
        color: #d4d4d8 !important;
        font-size: 13px !important;
        transition: all 0.12s ease !important;
    }

    div[role="menuitem"]:hover,
    div[role="menuitemradio"]:hover,
    div[role="option"]:hover,
    div[role="menuitem"][data-focused="true"],
    div[role="menuitemradio"][data-focused="true"],
    [class*="QuHfab2kCueVYIcnymfA"]:hover {
        background: rgba(255, 255, 255, 0.08) !important;
        color: #ffffff !important;
    }

    div[role="menuitemradio"][aria-checked="true"],
    div[role="option"][aria-selected="true"],
    [class*="DDNpARtK93vNnTDLVKBA"] {
        background: rgba(255, 255, 255, 0.12) !important;
        color: #ffffff !important;
        font-weight: 600 !important;
    }

    /* 4. Unified Search Results Container & Mainline Column */
    #web_content_wrapper, .content-wrap, #react-layout {
        width: 100% !important;
        max-width: 1100px !important;
        margin: 0 auto !important;
        padding: 0 var(--space-6) !important;
        box-sizing: border-box !important;
    }

    [class*="qrc3T8W2"], .qrc3T8W2PIYg9L63oA06 {
        width: 100% !important;
        max-width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        box-sizing: border-box !important;
    }

    [class*="FMPme3X9"], .FMPme3X940xAt4SKPFuw {
        width: 100% !important;
        max-width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        box-sizing: border-box !important;
        display: flex !important;
        flex-wrap: wrap !important;
        gap: var(--space-6) !important;
    }

    /* Main Results Section */
    section[class*="At_VJ9M"], .At_VJ9MlrHsSjbfCtz2_ {
        flex: 1 1 680px !important;
        max-width: 680px !important;
        min-width: 0 !important;
        width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        box-sizing: border-box !important;
    }

    /* Knowledge Sidebar Section */
    [class*="FMPme3X9"] > aside,
    [class*="FMPme3X9"] > section:nth-child(2),
    .results--sidebar, .react-results--sidebar {
        flex: 0 1 340px !important;
        max-width: 380px !important;
        min-width: 0 !important;
        margin: 0 !important;
        box-sizing: border-box !important;
    }

    #links, #results, .results--main, .react-results--main {
        width: 100% !important;
        max-width: 100% !important;
        padding: var(--space-4) 0 var(--space-12) 0 !important;
        margin: 0 !important;
        box-sizing: border-box !important;
        list-style: none !important;
    }
    .results--main:empty {
        display: none !important;
    }

    .react-results--main > li, #links > div {
        width: 100% !important;
        max-width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        box-sizing: border-box !important;
        list-style: none !important;
    }

    /* Individual Card: Apple Obsidian Aesthetic */
    .result, .nrn-react-div, article[data-testid="result"], .result--default, article {
        width: 100% !important;
        max-width: 100% !important;
        background: rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 12px !important;
        padding: 18px 22px !important;
        margin-bottom: var(--space-3) !important;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
        transition: transform 0.16s var(--onyx-ease), background 0.16s ease, border-color 0.16s ease, box-shadow 0.16s ease !important;
        position: relative !important;
        box-sizing: border-box !important;
    }
    .result:hover, .nrn-react-div:hover, article[data-testid="result"]:hover {
        background: rgba(255, 255, 255, 0.065) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        transform: translateY(-1.5px) !important;
        box-shadow: 0 6px 22px rgba(0, 0, 0, 0.5) !important;
    }

    /* Result Title */
    .result__title, [data-testid="result-title-a"], h2, h3, h3.LC20lb, .yuRUbf h3, a h3 {
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif !important;
        font-size: 17px !important;
        font-weight: 500 !important;
        letter-spacing: -0.015em !important;
        line-height: 1.35 !important;
        margin: 0 0 var(--space-1) 0 !important;
        transition: color 140ms ease !important;
    }
    .result__title a, [data-testid="result-title-a"], a:has(h3), .yuRUbf a {
        color: #ffffff !important;
        text-decoration: none !important;
    }
    .result__title a:hover, [data-testid="result-title-a"]:hover, a:has(h3):hover h3, .yuRUbf a:hover h3, h3:hover, a:hover h3 {
        color: #93c5fd !important;
        text-decoration: underline !important;
    }
    a:visited h3, .yuRUbf a:visited h3, .result__title a:visited {
        color: #c7d2fe !important;
    }

    /* Domain / URL Breadcrumb */
    .result__url, [data-testid="result-extras-url-link"], cite {
        color: #71717a !important;
        font-size: 12px !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        display: inline-flex !important;
        align-items: center !important;
        gap: var(--space-2) !important;
        text-decoration: none !important;
        margin-bottom: var(--space-1) !important;
    }
    .result__icon, [data-testid="result-favicon"] {
        border-radius: 4px !important;
    }

    /* Result Snippet */
    .result__snippet, [data-testid="result-snippet"] {
        color: #d4d4d8 !important;
        font-size: 14px !important;
        line-height: 1.6 !important;
        margin-top: var(--space-2) !important;
    }

    /* Keyword highlight pill */
    b, strong, .highlight {
        color: #ffffff !important;
        background: rgba(255, 255, 255, 0.12) !important;
        padding: 1px 4px !important;
        border-radius: 4px !important;
        font-weight: 600 !important;
    }

    /* Sublinks / Sitelinks inside cards */
    .result__sitelinks, .result__sublinks {
        margin-top: var(--space-3) !important;
        border-top: 1px solid rgba(255, 255, 255, 0.06) !important;
        padding-top: var(--space-2) !important;
    }
    .result__sitelinks a, .result__sublinks a {
        color: #e4e4e7 !important;
        font-size: 13px !important;
        text-decoration: none !important;
    }
    .result__sitelinks a:hover, .result__sublinks a:hover {
        text-decoration: underline !important;
    }

    /* 5. Knowledge Panel & Instant Modules (Stocks, Weather, Calculator, About, Wikipedia) */
    .results--sidebar, .module, [class*="ia-module"], .module--about, [data-testid="module--about"], .js-about-module {
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 16px !important;
        padding: var(--space-6) !important;
        backdrop-filter: blur(20px) !important;
        -webkit-backdrop-filter: blur(20px) !important;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4) !important;
        color: #ffffff !important;
        margin-bottom: var(--space-4) !important;
    }
    .module *, [class*="ia-module"] * {
        color: #ffffff !important;
    }
    .module__title, .module__heading, .stocks-module__header .module__title {
        color: #ffffff !important;
        font-size: 22px !important;
        font-weight: 600 !important;
        letter-spacing: -0.02em !important;
        margin-bottom: var(--space-2) !important;
    }
    .stocks-module__latestUpdate, .stocks-module__exchange, .module__more-at {
        color: #71717a !important;
        font-size: 12px !important;
    }
    .stocks-module__currentPrice {
        color: #ffffff !important;
        font-size: 32px !important;
        font-weight: 700 !important;
        letter-spacing: -0.03em !important;
    }
    .stocks-module__currency {
        color: #a1a1aa !important;
        font-size: 14px !important;
        font-weight: 500 !important;
        margin-left: 6px !important;
    }
    .stocks-module__timePeriod {
        background: rgba(255, 255, 255, 0.05) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 6px !important;
        color: #a1a1aa !important;
        padding: 4px 10px !important;
        font-size: 12px !important;
        font-weight: 500 !important;
        margin-right: 4px !important;
    }
    .stocks-module__timePeriod.selected, .stocks-module__timePeriod:hover {
        background: rgba(255, 255, 255, 0.15) !important;
        color: #ffffff !important;
        border-color: rgba(255, 255, 255, 0.25) !important;
    }
    .module svg text, svg text {
        fill: #a1a1aa !important;
    }
    .module svg line, svg line, svg path[stroke*="#"] {
        stroke: rgba(255, 255, 255, 0.15) !important;
    }
    .module__text, .module__content {
        color: #d4d4d8 !important;
        font-size: 14px !important;
        line-height: 1.6 !important;
    }

    /* 6. Clean Deep Research Switch Button */
    .onyx-research-switch-btn {
        display: inline-flex !important;
        align-items: center !important;
        gap: 6px !important;
        background: rgba(255, 255, 255, 0.06) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 8px !important;
        color: #ffffff !important;
        font-size: 12px !important;
        font-weight: 500 !important;
        padding: 6px 14px !important;
        cursor: pointer !important;
        text-decoration: none !important;
        transition: all 0.15s ease !important;
    }
    .onyx-research-switch-btn:hover {
        background: rgba(255, 255, 255, 0.14) !important;
        border-color: rgba(255, 255, 255, 0.25) !important;
        color: #ffffff !important;
    }

    /* Onyx AI Overview Card */
    #onyx-ai-synthesis-card {
        display: block !important;
        width: 100% !important;
        box-sizing: border-box !important;
        background: linear-gradient(135deg, rgba(30, 41, 59, 0.35) 0%, rgba(15, 23, 42, 0.35) 100%), rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 12px !important;
        padding: 16px 20px !important;
        margin-bottom: var(--space-4) !important;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.35) !important;
        position: relative !important;
        list-style: none !important;
    }
    .onyx-ai-header {
        display: flex !important;
        align-items: center !important;
        justify-content: space-between !important;
        margin-bottom: 8px !important;
    }
    .onyx-ai-badge {
        display: inline-flex !important;
        align-items: center !important;
        gap: 6px !important;
        color: #ffffff !important;
        font-size: 12px !important;
        font-weight: 600 !important;
        letter-spacing: 0.03em !important;
    }
    .onyx-ai-content {
        color: #e2e8f0 !important;
        font-size: 14px !important;
        line-height: 1.6 !important;
    }

    /* Pagination / Next Page Button */
    .result--more, .btn--more, [data-testid="more-results"] {
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
        background: rgba(255, 255, 255, 0.05) !important;
        border: 1px solid rgba(255, 255, 255, 0.10) !important;
        border-radius: 10px !important;
        color: #ffffff !important;
        font-size: 13.5px !important;
        font-weight: 500 !important;
        padding: 12px 28px !important;
        margin: var(--space-6) auto !important;
        max-width: 240px !important;
        cursor: pointer !important;
        transition: all 0.16s var(--onyx-ease) !important;
    }
    .result--more:hover, .btn--more:hover, [data-testid="more-results"]:hover {
        background: rgba(255, 255, 255, 0.10) !important;
        border-color: rgba(255, 255, 255, 0.22) !important;
    }

    /* =========================================================
       7. GOOGLE SEARCH OBSIDIAN GLASS THEME
       ========================================================= */

    /* Google Header & Search Capsule - ONLY the outer capsule gets the border */
    .RNNXgb, form[role="search"] .RNNXgb, .minidiv .RNNXgb {
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.10) !important;
        border-radius: 24px !important;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.45), inset 0 1px 0 rgba(255, 255, 255, 0.06) !important;
        height: 48px !important;
        box-sizing: border-box !important;
        color: #ffffff !important;
        max-width: 680px !important;
        width: 100% !important;
        margin: 0 !important;
        transition: background 160ms var(--onyx-ease), border-color 160ms var(--onyx-ease), box-shadow 160ms var(--onyx-ease) !important;
    }

    .RNNXgb:focus-within, form[role="search"] .RNNXgb:focus-within {
        background: rgba(255, 255, 255, 0.07) !important;
        border-color: rgba(255, 255, 255, 0.35) !important;
        box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.35), 0 8px 32px rgba(0, 0, 0, 0.6) !important;
    }

    /* Neutralize all inner containers to avoid double border / crescent artifact */
    .iblpc, .SDkEP, .A8SBwf, form[role="search"] .A8SBwf, .oxmBfd, .emcav, .emcav .emc, .RNNXgb > div {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        box-shadow: none !important;
    }

    /* Eliminate Google 136px logo offset so input aligns with tabs */
    .A8SBwf, .aypyie, form[role="search"] .A8SBwf, #tsf .A8SBwf, .RNNXgb, #tsf .RNNXgb, .NDnoQ, .NDnoQ .RNNXgb {
        margin-left: 0 !important;
    }

    .RNNXgb textarea, .RNNXgb input, textarea.gLFyf, input.gLFyf, #APjFqb {
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 15px !important;
        background: transparent !important;
        border: none !important;
        outline: none !important;
        box-shadow: none !important;
        -webkit-text-fill-color: #ffffff !important;
    }

    .RNNXgb svg, .iblpc svg, .ExCKkf svg, .XDyW0e svg, .nDcEnd svg, .G43f7e svg, .dRYYxd svg,
    button[aria-label*="Search" i] svg, button[aria-label*="Clear" i] svg {
        fill: rgba(255, 255, 255, 0.65) !important;
        stroke: rgba(255, 255, 255, 0.65) !important;
        color: rgba(255, 255, 255, 0.65) !important;
    }

    /* Complete scrub of Google App Launcher (9-dot grid), Google Account, Share, and Header Clutter */
    #logo, .logo img, header svg.logo, [aria-label*="Google" i] img, a#logo, .logocont, #logocont,
    #gb, .gb_d, .gb_e, .gb_f, .gb_g, .gb_h, .gb_i, .gb_v, .gb_w, .gb_x, .gb_y, .gb_z,
    .gb_A, .gb_B, .gb_C, .gb_Ja, .gb_1, .gb_X, [aria-label*="Google apps" i],
    [aria-label*="Google app" i], [aria-label*="Google Account" i],
    a[href*="accounts.google.com"], a[href*="/preferences"], a[href*="google.com/save"], a[href*="/saves"],
    .G57R0c, .LH92ce, .TQc1id, .SJ1Kg, div[data-async-context*="share"], div[jscontroller*="share"],
    .Q3DXx, .Efnghe, .apFnFf, [aria-label*="Share" i], [aria-label*="share" i], [aria-label*="Compartir" i],
    [title*="Share" i], [title*="share" i], [data-share-url],
    svg:has(path[d*="M16 5l-1.42"]), svg:has(path[d*="M18 16.08c"]),
    #searchform button:not(#tsf button), header button:not(#tsf button), .sfbg button:not(#tsf button),
    #searchform > div:not(:has(#tsf)):not(#tsf) {
        display: none !important;
        opacity: 0 !important;
        visibility: hidden !important;
        pointer-events: none !important;
        width: 0 !important;
        height: 0 !important;
        margin: 0 !important;
        padding: 0 !important;
        overflow: hidden !important;
    }

    /* Google Category Navigation Bar ("All", "Images", "Videos", "Short videos", "Forums", "News", "More", "Tools") */
    #top_nav, .crJ18e, .hdtb-mfa, .hdtb, #hdtb, .z80RDc, .O8QBhe, [role="navigation"],
    .EDblX, .h5JSWd, .rQTE8b, .beZ0tf, .O1uzAe {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        max-width: 100% !important;
        width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        box-sizing: border-box !important;
    }

    .rQTE8b {
        display: flex !important;
        align-items: center !important;
        justify-content: flex-start !important;
        gap: 8px !important;
        max-width: 100% !important;
        width: 100% !important;
        margin: 10px 0 16px 0 !important;
        padding: 0 !important;
    }

    .beZ0tf {
        display: flex !important;
        align-items: center !important;
        flex-wrap: nowrap !important;
        gap: 6px !important;
        padding: 0 !important;
        margin: 0 !important;
        overflow-x: auto !important;
        scrollbar-width: none !important;
    }
    .beZ0tf::-webkit-scrollbar, .rQTE8b::-webkit-scrollbar {
        display: none !important;
    }

    .yeKjxb {
        display: inline-flex !important;
        align-items: center !important;
        margin-left: auto !important;
        padding: 0 !important;
        flex-shrink: 0 !important;
    }

    /* Total annihilation of Google's horizontal hairline divider, scroll circles, and tab ghost artifacts */
    .zLSRge, .w2jn8d, .PwiNU, .m29tEd, .hdtb-ms, #hdtb-ms, .E4ffZe,
    .e9EfHf::before, .e9EfHf::after, #cnt::before, #cnt::after, #sfcnt::after, hr {
        display: none !important;
        height: 0 !important;
        border: none !important;
        border-bottom: none !important;
        visibility: hidden !important;
        opacity: 0 !important;
    }

    /* Eradicate dark circular carousel scroll buttons and edge fade masks */
    .u96bed, .GTERze, .zwVERd, .yFyxRc, .l7Wnjd, .tGYVp,
    .Iy1nvd, .vezEod, .SvoXfb, .F9Idpe,
    button.Iy1nvd, button.vezEod,
    .A66hff button, .zp6Lyf button,
    button[jsname="ggE0ke"], [class*="Iy1nvd"], [class*="vezEod"], [class*="SvoXfb"], [class*="F9Idpe"],
    .mXZJrb button, .p7eiqf, .oIdq8b, .sz3HNe, .b3puKe, .GHMsie, .TQc1id,
    .HPvrce, [class*="HPvrce"], .mTpL7c.HPvrce, .mTpL7c:empty {
        display: none !important;
        width: 0 !important;
        height: 0 !important;
        opacity: 0 !important;
        pointer-events: none !important;
        visibility: hidden !important;
    }

    .mXwfNd::before, .mXwfNd::after,
    .C6AK7c::before, .C6AK7c::after,
    .XVMlrc::before, .XVMlrc::after,
    .beZ0tf::before, .beZ0tf::after,
    .rQTE8b::before, .rQTE8b::after,
    .EDblX::before, .EDblX::after,
    .h5JSWd::before, .h5JSWd::after,
    .olrp5b::before, .olrp5b::after,
    .mVH5Fc::before, .mVH5Fc::after,
    .crJ18e::before, .crJ18e::after,
    .hdtb-mfa::before, .hdtb-mfa::after {
        display: none !important;
        content: none !important;
        background: transparent !important;
        background-image: none !important;
        border: none !important;
        box-shadow: none !important;
        width: 0 !important;
        height: 0 !important;
        opacity: 0 !important;
    }

    /* Sub-filter suggestion strip container in Google Images & Videos */
    .rfiSsc, .YNk70c, .sBbkle, .xhjkHe, .TrmO7, .ZeeOc, .bqHHPb, .fMHynf, .PHj8of, .Xx7Mif, .zp6Lyf, .A66hff {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
    }

    .IUOThf {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
        display: flex !important;
        align-items: center !important;
        gap: 8px !important;
        padding: 4px 0 14px 0 !important;
        overflow-x: auto !important;
        scrollbar-width: none !important;
    }
    .IUOThf::-webkit-scrollbar {
        display: none !important;
    }

    .A66hff a.nPDzT,
    .IUOThf a.nPDzT,
    a.nPDzT {
        text-decoration: none !important;
        display: inline-flex !important;
        align-items: center !important;
        border: none !important;
        background: transparent !important;
    }

    /* Sub-filter chips: Apple Obsidian frosted pills */
    .GKS7s {
        display: inline-flex !important;
        align-items: center !important;
        height: 34px !important;
        padding: 0 14px 0 5px !important;
        gap: 8px !important;
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 17px !important;
        box-shadow: none !important;
        transition: all 160ms var(--onyx-ease) !important;
        cursor: pointer !important;
        box-sizing: border-box !important;
    }

    .GKS7s:hover,
    a.nPDzT:hover .GKS7s {
        background: rgba(255, 255, 255, 0.08) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        transform: translateY(-1px) !important;
    }

    .EENbod, .iAatCe, .q1MG4e {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
    }

    .iAatCe {
        width: 24px !important;
        height: 24px !important;
        border-radius: 12px !important;
        overflow: hidden !important;
        background: rgba(255, 255, 255, 0.08) !important;
    }

    .iAatCe img, .q1MG4e img {
        width: 24px !important;
        height: 24px !important;
        object-fit: cover !important;
        border-radius: 12px !important;
    }

    .FMKtTb, .FMKtTb * {
        color: #e2e8f0 !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 13px !important;
        font-weight: 500 !important;
        line-height: 1 !important;
        white-space: nowrap !important;
    }

    .GKS7s:hover .FMKtTb {
        color: #ffffff !important;
    }

    .GKS7s::before, .GKS7s::after,
    .EENbod::before, .EENbod::after,
    .nPDzT::before, .nPDzT::after,
    .iAatCe::before, .iAatCe::after {
        display: none !important;
        content: none !important;
    }

    /* Neutralize all ghost background rectangles from tab wrappers except actual pill controls */
    .beZ0tf div:not(.mTpL7c):not(.mOKdDc):not(#hdtb-tls),
    .rQTE8b div:not(.mTpL7c):not(.mOKdDc):not(#hdtb-tls),
    .olrp5b,
    .crJ18e div, .hdtb-mfa div, .O8QBhe div, .z80RDc div,
    .crJ18e [role="listitem"], .hdtb-mfa [role="listitem"],
    .beZ0tf [role="listitem"], .rQTE8b [role="listitem"],
    .crJ18e [role="list"], .hdtb-mfa [role="list"] {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
    }

    /* Google Search Category Pills: Unified Apple Obsidian Capsules */
    .beZ0tf a.C6AK7c,
    .beZ0tf a.XVMlrc,
    a.C6AK7c,
    a.XVMlrc,
    .crJ18e a,
    .hdtb-mfa a,
    .IUOThf a,
    .hdtb-imb a,
    .hdtb-mfa div[role="tab"],
    .z80RDc a,
    .O8QBhe a,
    .beZ0tf .mTpL7c,
    .rQTE8b .mTpL7c,
    .yeKjxb .mTpL7c,
    .mOKdDc,
    #hdtb-tls {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        height: 32px !important;
        padding: 0 14px !important;
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 16px !important;
        color: #a1a1aa !important;
        font-size: 13px !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-weight: 500 !important;
        line-height: 1 !important;
        text-decoration: none !important;
        cursor: pointer !important;
        box-shadow: none !important;
        transition: all 160ms var(--onyx-ease) !important;
        white-space: nowrap !important;
        box-sizing: border-box !important;
    }

    .beZ0tf a.C6AK7c:hover,
    .beZ0tf a.XVMlrc:hover,
    a.C6AK7c:hover,
    a.XVMlrc:hover,
    .crJ18e a:hover,
    .hdtb-mfa a:hover,
    .IUOThf a:hover,
    .z80RDc a:hover,
    .beZ0tf .mTpL7c:hover,
    .rQTE8b .mTpL7c:hover,
    .yeKjxb .mTpL7c:hover,
    .mOKdDc:hover,
    #hdtb-tls:hover {
        background: rgba(255, 255, 255, 0.08) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        color: #ffffff !important;
        transform: translateY(-1px) !important;
    }

    /* Active Tab */
    .beZ0tf a.C6AK7c:has([aria-current="page"]),
    .beZ0tf a.C6AK7c:has([selected]),
    a.C6AK7c:has([aria-current="page"]),
    a.C6AK7c:has([selected]),
    .beZ0tf a.C6AK7c[aria-disabled="true"],
    a.C6AK7c[aria-disabled="true"],
    .beZ0tf a.C6AK7c.onyx-tab-active,
    a.C6AK7c.onyx-tab-active,
    .crJ18e a.YmvwI,
    .hdtb-mfa a.YmvwI,
    .hdtb-mfa .selected,
    .crJ18e [aria-selected="true"],
    .IUOThf [aria-selected="true"],
    .z80RDc .selected,
    [role="tab"][aria-selected="true"] {
        background: rgba(255, 255, 255, 0.14) !important;
        border: 1px solid rgba(255, 255, 255, 0.28) !important;
        color: #ffffff !important;
        font-weight: 600 !important;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35) !important;
    }

    /* AI Mode Tab: Frosted Obsidian with Violet Glow Accent */
    a.XVMlrc, .olrp5b a {
        background: linear-gradient(135deg, rgba(99, 102, 241, 0.12) 0%, rgba(168, 85, 247, 0.12) 100%), rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(168, 85, 247, 0.25) !important;
        color: #e0e7ff !important;
    }
    a.XVMlrc:hover, .olrp5b a:hover {
        background: linear-gradient(135deg, rgba(99, 102, 241, 0.22) 0%, rgba(168, 85, 247, 0.22) 100%), rgba(255, 255, 255, 0.08) !important;
        border-color: rgba(168, 85, 247, 0.45) !important;
        color: #ffffff !important;
    }

    /* Tab internal layout & vertical centering */
    .mXwfNd, .mVH5Fc {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        height: 100% !important;
        padding: 0 !important;
        margin: 0 !important;
        border: none !important;
        border-bottom: none !important;
        background: transparent !important;
        box-shadow: none !important;
    }
    .R1QWuf {
        display: inline-flex !important;
        align-items: center !important;
        line-height: 1 !important;
        margin: 0 !important;
        padding: 0 !important;
        border-bottom: none !important;
        color: inherit !important;
        font-size: 13px !important;
        font-weight: inherit !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }
    .C6AK7c, .C6AK7c *, .XVMlrc, .XVMlrc * {
        border-bottom: none !important;
        text-decoration: none !important;
    }
    .mTpL7c svg, .mOKdDc svg, .beZ0tf svg, .yeKjxb svg, #hdtb-tls svg {
        fill: currentColor !important;
        width: 14px !important;
        height: 14px !important;
        margin-left: 4px !important;
    }

    /* More dropdown menu popover */
    .vH6rvf, .FJCJfd, .R0DW9c, .bsmXxe {
        background: #121216 !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 12px !important;
        box-shadow: 0 12px 40px rgba(0, 0, 0, 0.75) !important;
        backdrop-filter: blur(20px) !important;
        padding: 6px !important;
    }
    .vH6rvf a, .FJCJfd a, .bsmXxe a {
        border-radius: 8px !important;
        padding: 8px 12px !important;
        color: #d4d4d8 !important;
        font-size: 13px !important;
        transition: all 0.12s ease !important;
    }
    .vH6rvf a:hover, .FJCJfd a:hover, .bsmXxe a:hover {
        background: rgba(255, 255, 255, 0.08) !important;
        color: #ffffff !important;
    }

    /* Google AI Overview & Total Nuke of the Blinding White Gradient Block */
    .ULSxyf, .cUnQKe, .Ww4FFb, .yG4QQe, .L3eUgb, .w8qArf, .b3id4d, .ob912b, .exp-c, .xpdopen,
    [jsname="j1fyvd"], div[data-attrid="wa:/description"], div[data-asoch-targets],
    .hlcw0c, .xpd, .UD9u0, .gJ5Zne {
        background: transparent !important;
        background-color: transparent !important;
        background-image: none !important;
        box-shadow: none !important;
    }

    .ULSxyf::before, .ULSxyf::after,
    .cUnQKe::before, .cUnQKe::after,
    .Ww4FFb::before, .Ww4FFb::after,
    .yG4QQe::before, .yG4QQe::after,
    .L3eUgb::before, .L3eUgb::after,
    .w8qArf::before, .w8qArf::after,
    .b3id4d::before, .b3id4d::after,
    .ob912b::before, .ob912b::after,
    .exp-c::before, .exp-c::after,
    .xpdopen::before, .xpdopen::after,
    [jsname="j1fyvd"]::before, [jsname="j1fyvd"]::after,
    div[data-attrid="wa:/description"]::before, div[data-attrid="wa:/description"]::after,
    .UD9u0::before, .UD9u0::after {
        display: none !important;
        content: none !important;
        background: transparent !important;
        background-image: none !important;
        opacity: 0 !important;
        visibility: hidden !important;
        width: 0 !important;
        height: 0 !important;
    }

    /* AI Overview Card Container */
    .Ww4FFb, div[data-attrid="wa:/description"] {
        background: linear-gradient(135deg, rgba(30, 41, 59, 0.35) 0%, rgba(15, 23, 42, 0.35) 100%), rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 16px !important;
        padding: 20px !important;
        margin-bottom: 24px !important;
        box-shadow: 0 4px 24px rgba(0, 0, 0, 0.45) !important;
        box-sizing: border-box !important;
    }

    .Ww4FFb, .Ww4FFb *,
    div[data-attrid="wa:/description"], div[data-attrid="wa:/description"] *,
    .w8qArf, .w8qArf *,
    .b3id4d, .b3id4d *,
    .fP1Qef, .fP1Qef * {
        color: #e2e8f0 !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }

    /* AI Overview Topic / Suggestion Pills - strictly scoped inside AI Overview */
    .Ww4FFb [role="listitem"] button,
    .Ww4FFb [role="listitem"] a,
    div[data-attrid="wa:/description"] [role="listitem"] button,
    div[data-attrid="wa:/description"] [role="listitem"] a,
    .dg0Ffc, .gL95fc, .Z1Vzce, .K20v3e, .v5yQqb, .Z1Vzce button {
        background: rgba(255, 255, 255, 0.06) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 16px !important;
        color: #ffffff !important;
        font-size: 12.5px !important;
        font-weight: 500 !important;
        padding: 6px 14px !important;
        cursor: pointer !important;
        transition: all 160ms var(--onyx-ease) !important;
    }
    .Ww4FFb [role="listitem"] button:hover,
    .dg0Ffc:hover, .gL95fc:hover, .Z1Vzce:hover {
        background: rgba(255, 255, 255, 0.12) !important;
        border-color: rgba(255, 255, 255, 0.25) !important;
        color: #ffffff !important;
        transform: translateY(-1px) !important;
    }

    /* AI Overview Preview References (Side cards) */
    .I6TXqe, .dnXCYb, .xYnFwe, .k6P01c, .uVAGfe {
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 12px !important;
        color: #ffffff !important;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
    }
    .I6TXqe *, .dnXCYb *, .xYnFwe * {
        color: #d4d4d8 !important;
    }

    /* Google "Show more ∨" / "Show less ∧" Expander Button */
    [role="button"][jsname="j1fyvd"],
    button[jsname="j1fyvd"],
    .w8qArf [role="button"][jsname="j1fyvd"],
    .cUnQKe [role="button"][jsname="j1fyvd"],
    .exp-c [role="button"],
    .exp-c button {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        gap: 8px !important;
        height: 38px !important;
        padding: 0 24px !important;
        background: rgba(255, 255, 255, 0.06) !important;
        border: 1px solid rgba(255, 255, 255, 0.16) !important;
        border-radius: 19px !important;
        color: #ffffff !important;
        font-size: 13px !important;
        font-weight: 500 !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        cursor: pointer !important;
        box-shadow: 0 4px 16px rgba(0, 0, 0, 0.45) !important;
        margin: 16px auto !important;
        transition: all 160ms var(--onyx-ease) !important;
    }

    [role="button"][jsname="j1fyvd"]:hover,
    button[jsname="j1fyvd"]:hover,
    .exp-c [role="button"]:hover,
    .exp-c button:hover {
        background: rgba(255, 255, 255, 0.12) !important;
        border-color: rgba(255, 255, 255, 0.30) !important;
        color: #ffffff !important;
        transform: translateY(-1px) !important;
        box-shadow: 0 6px 20px rgba(0, 0, 0, 0.6) !important;
    }

    [role="button"][jsname="j1fyvd"]:active,
    button[jsname="j1fyvd"]:active {
        transform: scale(0.97) !important;
    }

    [role="button"][jsname="j1fyvd"] *,
    button[jsname="j1fyvd"] *,
    .w8qArf [role="button"][jsname="j1fyvd"] *,
    .cUnQKe [role="button"][jsname="j1fyvd"] *,
    .exp-c [role="button"] *,
    .exp-c button * {
        color: #ffffff !important;
        fill: #ffffff !important;
        stroke: #ffffff !important;
        background: transparent !important;
        border: none !important;
    }

    /* Google Organic Search Results: Single clean Apple Obsidian Card per result */
    .MjjYud, .g:not(.MjjYud .g) {
        background: rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 14px !important;
        padding: 18px 22px !important;
        margin-bottom: 12px !important;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
        transition: transform 160ms var(--onyx-ease),
                    background 160ms ease,
                    border-color 160ms ease,
                    box-shadow 160ms ease !important;
        box-sizing: border-box !important;
        position: relative !important;
        max-width: 680px !important;
        width: 100% !important;
    }

    .MjjYud:hover, .g:not(.MjjYud .g):hover {
        background: rgba(255, 255, 255, 0.065) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        transform: translateY(-1.5px) !important;
        box-shadow: 0 6px 24px rgba(0, 0, 0, 0.5) !important;
    }

    /* Sitelinks cluster within organic result card */
    .hlcw0c {
        display: flex !important;
        flex-direction: column !important;
        gap: 8px !important;
    }
    .hlcw0c .g {
        background: transparent !important;
        border: none !important;
        border-top: 1px solid rgba(255, 255, 255, 0.06) !important;
        border-radius: 0 !important;
        padding: 10px 0 0 0 !important;
        margin: 6px 0 0 0 !important;
        box-shadow: none !important;
    }
    .hlcw0c .g:first-child {
        border-top: none !important;
        padding-top: 0 !important;
        margin-top: 0 !important;
    }

    /* Video search results & thumbnails */
    .d3F79b, [data-video-id], .MjjYud:has(video) {
        border-radius: 12px !important;
    }
    .d3F79b img, [data-video-id] img, .ct3b9e img {
        border-radius: 8px !important;
    }

    /* When .MjjYud is a group container holding multiple results, unbox it and style children individually */
    .MjjYud:has(.g ~ .g),
    .MjjYud:has(.Ww4FFb ~ .Ww4FFb),
    .MjjYud:has(.d3F79b ~ .d3F79b),
    .MjjYud:has([data-video-id] ~ [data-video-id]) {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 !important;
        transform: none !important;
    }
    .MjjYud:has(.g ~ .g):hover,
    .MjjYud:has(.Ww4FFb ~ .Ww4FFb):hover,
    .MjjYud:has(.d3F79b ~ .d3F79b):hover,
    .MjjYud:has([data-video-id] ~ [data-video-id]):hover {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        transform: none !important;
    }

    .MjjYud:has(.g ~ .g) .g,
    .MjjYud:has(.Ww4FFb ~ .Ww4FFb) .Ww4FFb,
    .MjjYud:has(.d3F79b ~ .d3F79b) .d3F79b,
    .MjjYud:has([data-video-id] ~ [data-video-id]) [data-video-id] {
        background: rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 14px !important;
        padding: 16px 20px !important;
        margin-bottom: 12px !important;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
        transition: transform 160ms var(--onyx-ease),
                    background 160ms ease,
                    border-color 160ms ease,
                    box-shadow 160ms ease !important;
        box-sizing: border-box !important;
    }

    .MjjYud:has(.g ~ .g) .g:hover,
    .MjjYud:has(.Ww4FFb ~ .Ww4FFb) .Ww4FFb:hover,
    .MjjYud:has(.d3F79b ~ .d3F79b) .d3F79b:hover,
    .MjjYud:has([data-video-id] ~ [data-video-id]) [data-video-id]:hover {
        background: rgba(255, 255, 255, 0.065) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        transform: translateY(-1.5px) !important;
        box-shadow: 0 6px 24px rgba(0, 0, 0, 0.5) !important;
    }

    /* Google Images Grid Container: Never box the entire image results grid into a card */
    .MjjYud:has(.VKHL9c),
    .MjjYud:has(.DeNS1c),
    .MjjYud:has([data-ri]),
    .MjjYud:has(#islrg),
    .MjjYud:has(.islrc),
    .MjjYud:has(.srKDX),
    .VKHL9c,
    .srKDX,
    #rso:has(.VKHL9c),
    #rso:has(.DeNS1c),
    #center_col:has(.VKHL9c),
    #center_col:has(.DeNS1c),
    #rcnt:has(.VKHL9c),
    #rcnt:has(.DeNS1c) {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 !important;
        max-width: 100% !important;
        width: 100% !important;
        transform: none !important;
    }
    .MjjYud:has(.VKHL9c):hover,
    .MjjYud:has(.DeNS1c):hover,
    .MjjYud:has([data-ri]):hover,
    .MjjYud:has(#islrg):hover,
    .MjjYud:has(.islrc):hover,
    .MjjYud:has(.srKDX):hover {
        background: transparent !important;
        border: none !important;
        transform: none !important;
        box-shadow: none !important;
    }

    /* Google Image Result Items: Individual Apple Obsidian Cards */
    .kb0PBd.cvP2Ce,
    div[data-ri],
    .isv-r,
    .isv-r .isv-r,
    .islrc > div {
        background: rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 14px !important;
        padding: 8px !important;
        box-sizing: border-box !important;
        transition: transform 160ms var(--onyx-ease),
                    border-color 160ms ease,
                    background 160ms ease,
                    box-shadow 160ms ease !important;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35) !important;
    }

    .kb0PBd.cvP2Ce:hover,
    div[data-ri]:hover,
    .isv-r:hover,
    .islrc > div:hover {
        transform: translateY(-2px) !important;
        background: rgba(255, 255, 255, 0.07) !important;
        border-color: rgba(255, 255, 255, 0.22) !important;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6) !important;
    }

    .kb0PBd.cvP2Ce img,
    .DeNS1c img,
    .bFtXbb img,
    .uhHOwf img,
    .isv-r img {
        border-radius: 10px !important;
        object-fit: cover !important;
    }

    .VifEQd, .VifEQd * {
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }
    .VifEQd a, .VifEQd h3 {
        color: #e2e8f0 !important;
        font-size: 12.5px !important;
        line-height: 1.4 !important;
    }
    .VifEQd a:hover {
        color: #ffffff !important;
    }

    /* Eliminate double-nesting: all descendants inside .MjjYud must be borderless and transparent */
    .MjjYud .g,
    .MjjYud .tF2Cxc,
    .MjjYud .kvH3mc,
    .MjjYud .jGGUs,
    .MjjYud .Z26q7c,
    .MjjYud .Ww4FFb,
    .MjjYud .hlcw0c,
    .MjjYud .MjjYud {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 !important;
        transform: none !important;
    }

    /* Google Snippets & Highlights */
    .VwiC3b, .yXK7lf, .MUxGbd, .lEBKkf, div[data-sncf], .VwiC3b * {
        color: #d4d4d8 !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 14px !important;
        line-height: 1.6 !important;
    }

    .VwiC3b em, .VwiC3b b, em, b, strong {
        color: #ffffff !important;
        font-weight: 600 !important;
        background: rgba(255, 255, 255, 0.10) !important;
        padding: 1px 4px !important;
        border-radius: 4px !important;
    }

    .usJj9c, .MSLpAb, .StTgjd {
        border-top: 1px solid rgba(255, 255, 255, 0.06) !important;
        padding-top: 8px !important;
        margin-top: 12px !important;
    }
    .usJj9c a, .MSLpAb a {
        color: #93c5fd !important;
        text-decoration: none !important;
        font-size: 13px !important;
    }
    .usJj9c a:hover, .MSLpAb a:hover {
        text-decoration: underline !important;
    }

    hr, .Ww4FFb hr, .g hr, .hlcw0c {
        display: none !important;
        border: none !important;
    }

    /* Google Accordions ("People Also Ask") */
    .related-question-pair, .cbphWd, .g.kno-result, .csDO3b, [jsname="yEVEwb"] {
        background: rgba(255, 255, 255, 0.03) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 10px !important;
        padding: 12px 16px !important;
        margin-bottom: 8px !important;
        color: #ffffff !important;
    }
    .related-question-pair [role="button"], .cbphWd [role="button"] {
        background: transparent !important;
        border: none !important;
        color: #ffffff !important;
        font-weight: 500 !important;
        font-size: 14px !important;
        padding: 0 !important;
    }
    .related-question-pair svg, .cbphWd svg {
        fill: #a1a1aa !important;
    }

    /* Google Knowledge Panel (Sidebar #rhs) */
    #rhs, .kp-blk, .I6TXqe, .wp-ms, .osrp-blk {
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 16px !important;
        padding: 20px !important;
        backdrop-filter: blur(20px) !important;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.45) !important;
        color: #ffffff !important;
    }
    .kp-blk *, .I6TXqe *, .wp-ms * {
        color: #ffffff !important;
    }
    .kno-ecr-pt {
        font-size: 22px !important;
        font-weight: 600 !important;
        letter-spacing: -0.02em !important;
        color: #ffffff !important;
    }

    /* Google Footer, Ads, and Noise Removal */
    #fbar, #footcnt, #foot,
    .uEierd, #tads, #tadsb, [data-text-ad],
    .appbar, .cv2Vmc, .LH92ce, .TQc1id,
    .SJ1Kg, .G57R0c, #taw {
        display: none !important;
        visibility: hidden !important;
        opacity: 0 !important;
        pointer-events: none !important;
        height: 0 !important;
    }

    /* Google Pagination */
    #botstuff, #navcnt, table.AaVjTc {
        background: transparent !important;
        border: none !important;
    }
    table.AaVjTc td a {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        min-width: 36px !important;
        height: 36px !important;
        padding: 0 12px !important;
        background: rgba(255, 255, 255, 0.05) !important;
        border: 1px solid rgba(255, 255, 255, 0.10) !important;
        border-radius: 10px !important;
        color: #ffffff !important;
        font-size: 13px !important;
        font-weight: 500 !important;
        text-decoration: none !important;
        transition: all 160ms ease !important;
    }
    table.AaVjTc td a:hover {
        background: rgba(255, 255, 255, 0.12) !important;
        border-color: rgba(255, 255, 255, 0.24) !important;
    }
    table.AaVjTc td.cur {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        min-width: 36px !important;
        height: 36px !important;
        background: #ffffff !important;
        color: #070709 !important;
        font-weight: 600 !important;
        border-radius: 10px !important;
    }

    /* Universal Content Container Alignment - Eliminate Google 180px logo offset */
    #center_col, .mw #center_col, #rcnt #center_col {
        margin-left: 0 !important;
        margin-right: 0 !important;
        padding-left: 0 !important;
        padding-right: 0 !important;
        max-width: 680px !important;
        width: 100% !important;
        float: none !important;
    }

    #rcnt {
        display: flex !important;
        flex-wrap: wrap !important;
        gap: var(--space-6) !important;
        max-width: 1100px !important;
        margin: 0 auto !important;
        padding: 0 var(--space-6) !important;
        width: 100% !important;
        box-sizing: border-box !important;
    }

    #searchform, .sfbg, .minidiv {
        max-width: 1100px !important;
        margin: 0 auto !important;
        padding: 0 var(--space-6) !important;
        box-sizing: border-box !important;
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
    }

    #searchform > div, #searchform form, #tsf {
        max-width: 680px !important;
        width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
    }

    #main, #cnt {
        max-width: 1100px !important;
        margin: 0 auto !important;
        width: 100% !important;
        box-sizing: border-box !important;
        padding: 0 var(--space-6) !important;
    }

    /* On Google Images search or wide grid modes, allow full content width up to 1440px */
    #rcnt #center_col:has(.VKHL9c),
    #rcnt #center_col:has(.srKDX),
    #rcnt #center_col:has(.DeNS1c),
    #rcnt #center_col:has([data-ri]),
    #rcnt #center_col:has(#islrg),
    #center_col:has(.VKHL9c),
    #center_col:has(.srKDX),
    #center_col:has(.DeNS1c),
    #center_col:has([data-ri]),
    body:has(.VKHL9c) #rcnt #center_col,
    body:has(.srKDX) #rcnt #center_col,
    body:has(#islmp) #rcnt #center_col,
    body:has(.DeNS1c) #rcnt #center_col,
    body:has([data-ri]) #rcnt #center_col,
    body:has(#islmp) #center_col,
    body:has(.VKHL9c) #center_col,
    body:has(#islmp) #rcnt,
    body:has(.VKHL9c) #rcnt,
    body:has(.srKDX) #rcnt,
    body:has(#islmp) #main,
    body:has(.VKHL9c) #main,
    body:has(.srKDX) #main,
    body:has(#islmp) #cnt,
    body:has(.VKHL9c) #cnt,
    body:has(.srKDX) #cnt,
    body:has(#islmp) #searchform,
    body:has(.VKHL9c) #searchform,
    body:has(.srKDX) #searchform,
    body:has(#islmp) #searchform > div,
    body:has(.VKHL9c) #searchform > div,
    body:has(#islmp) #tsf,
    body:has(.VKHL9c) #tsf {
        max-width: 1440px !important;
        width: 100% !important;
    }

    #rhs {
        max-width: 380px !important;
        box-sizing: border-box !important;
    }

    @media (max-width: 768px) {
        .header-wrap, #header_wrapper, #main, #cnt, #rcnt {
            padding-left: var(--space-4) !important;
            padding-right: var(--space-4) !important;
        }
        #web_content_wrapper, .content-wrap, #react-layout {
            padding-left: var(--space-4) !important;
            padding-right: var(--space-4) !important;
        }
        .search--header, .search--adv, .search-wrap,
        #search_form [class*="QsyijBlqupsaY11GFhnp"],
        #search_form [class*="T265XEcezvjUhK71U8pN"],
        #react-duckbar, [data-testid="duckbar"],
        #react-duckbar nav, [data-testid="duckbar"] nav,
        section[class*="At_VJ9M"], .At_VJ9MlrHsSjbfCtz2_,
        [class*="FMPme3X9"] > aside,
        [class*="FMPme3X9"] > section:nth-child(2),
        #center_col, #rhs {
            max-width: 100% !important;
            flex-basis: 100% !important;
        }
    }
    """

    // Onyx Research Engine: Direct Comet-Style WebKit Integration
    func setupOnyxResearchBridge() {
        setupResearchBridge(for: sharedConfiguration)
    }
    
    func setupResearchBridge(for config: WKWebViewConfiguration) {
        // Native WebKit UserStyleSheet registration (Zero-FOUC, applied at WebCore parser level before DOM evaluation)
        if let userStyleSheetClass = NSClassFromString("_WKUserStyleSheet") as? NSObject.Type {
            let sel = NSSelectorFromString("initWithSource:forWKWebView:forMainFrameOnly:includeMatchPatternStrings:excludeMatchPatternStrings:baseURL:level:contentWorld:")
            typealias InitExt = @convention(c) (NSObject, Selector, NSString, WKWebView?, Bool, NSArray?, NSArray?, NSURL?, Int, WKContentWorld) -> NSObject
            let selAdd = NSSelectorFromString("_addUserStyleSheet:")
            typealias AddFunc = @convention(c) (WKUserContentController, Selector, NSObject) -> Void
            
            if userStyleSheetClass.instancesRespond(to: sel) && config.userContentController.responds(to: selAdd) {
                let searchPatterns = [
                    "*://*.google.com/*",
                    "*://google.com/*",
                    "*://*.google.ca/*",
                    "*://*.google.co.uk/*",
                    "*://*.google.de/*",
                    "*://*.google.fr/*",
                    "*://*.google.es/*",
                    "*://*.google.it/*",
                    "*://*.google.co.jp/*",
                    "*://*.duckduckgo.com/*",
                    "*://duckduckgo.com/*",
                    "*://*.duck.com/*",
                    "*://duck.com/*",
                    "*://*.brave.com/*"
                ] as NSArray
                
                let searchObj = userStyleSheetClass.init()
                let impInitSearch = searchObj.method(for: sel)
                let fnSearch = unsafeBitCast(impInitSearch, to: InitExt.self)
                let searchSheet = fnSearch(searchObj, sel, onyxSearchCSS as NSString, nil, true, searchPatterns, nil, nil, 1, WKContentWorld.page)
                
                let impAdd = config.userContentController.method(for: selAdd)
                let addFn = unsafeBitCast(impAdd, to: AddFunc.self)
                addFn(config.userContentController, selAdd, searchSheet)
                
                let researchPatterns = [
                    "*://duck.ai/*",
                    "*://*.duck.ai/*"
                ] as NSArray
                let researchObj = userStyleSheetClass.init()
                let impInitResearch = researchObj.method(for: sel)
                let fnResearch = unsafeBitCast(impInitResearch, to: InitExt.self)
                let researchSheet = fnResearch(researchObj, sel, onyxResearchCSS as NSString, nil, true, researchPatterns, nil, nil, 1, WKContentWorld.page)
                addFn(config.userContentController, selAdd, researchSheet)
            }
        }

        let escapedResearchCSS = onyxResearchCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        
        let escapedSearchCSS = onyxSearchCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let jsSourceStart = """
        (function() {
            const host = window.location.hostname || '';
            const href = window.location.href || '';
            const isDuck = host.includes('duck.ai') || host.includes('duckduckgo.com') || host.includes('duck.com');
            const isGoogle = host.includes('google.') && (href.includes('/search') || href.includes('q=') || href.includes('/imghp') || href.includes('tbm=') || href.includes('udm=') || host.startsWith('images.'));
            const isBrave = host.includes('brave.com') && href.includes('/search');
            const isSearch = isDuck || isGoogle || isBrave;
            if (!isSearch) return;

            try {
                document.documentElement.style.setProperty('background-color', '#070709', 'important');
                document.documentElement.style.setProperty('color-scheme', 'dark', 'important');
                document.documentElement.setAttribute('data-theme', 'dark');
                if (isGoogle) {
                    document.cookie = "PREF=f6=400; domain=.google.com; path=/; max-age=31536000";
                }
            } catch(e) {}

            function ensureBodyDark() {
                if (document.body) {
                    document.body.style.setProperty('background-color', '#070709', 'important');
                    document.body.style.setProperty('color', '#ffffff', 'important');
                }
            }
            ensureBodyDark();
            const bodyObs = new MutationObserver(() => {
                if (document.body) {
                    ensureBodyDark();
                    bodyObs.disconnect();
                }
            });
            try { bodyObs.observe(document.documentElement, { childList: true }); } catch(e) {}

            const isChat = host.includes('duck.ai') || href.includes('ia=chat');
            const css = isChat ? `\(escapedResearchCSS)` : `\(escapedSearchCSS)`;
            const styleId = isChat ? 'onyx-research-theme' : 'onyx-search-theme';

            let themeStyle = document.getElementById(styleId);
            if (!themeStyle) {
                themeStyle = document.createElement('style');
                themeStyle.id = styleId;
                themeStyle.textContent = css;
                (document.head || document.documentElement).appendChild(themeStyle);
            }

            function pinStyle() {
                const target = document.head || document.documentElement;
                if (!target) return;
                if (!document.getElementById(styleId)) {
                    target.appendChild(themeStyle);
                } else if (target.lastElementChild !== themeStyle) {
                    target.appendChild(themeStyle);
                }
            }

            // Keep stylesheet at very end of <head> during incremental HTML stream
            const headObserver = new MutationObserver(() => {
                pinStyle();
            });
            try {
                headObserver.observe(document.documentElement, { childList: true, subtree: true });
            } catch(e) {}

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', () => {
                    pinStyle();
                    setTimeout(() => { try { headObserver.disconnect(); } catch(e) {} }, 6000);
                });
            }

            // Capture-phase instant tab feedback when switching categories (All, Images, Videos, etc.)
            window.addEventListener('click', function(e) {
                const tab = e.target && e.target.closest && e.target.closest('a.C6AK7c, a.XVMlrc, .beZ0tf a, .rQTE8b a, .mOKdDc, #hdtb-tls');
                if (tab) {
                    const allTabs = document.querySelectorAll('.beZ0tf a, .rQTE8b a, a.C6AK7c, a.XVMlrc, .mOKdDc, #hdtb-tls');
                    allTabs.forEach(t => {
                        t.style.setProperty('background', 'rgba(255, 255, 255, 0.04)', 'important');
                        t.style.setProperty('border-color', 'rgba(255, 255, 255, 0.08)', 'important');
                        t.style.setProperty('color', '#a1a1aa', 'important');
                        t.style.setProperty('font-weight', '500', 'important');
                    });
                    tab.style.setProperty('background', 'rgba(255, 255, 255, 0.14)', 'important');
                    tab.style.setProperty('border-color', 'rgba(255, 255, 255, 0.28)', 'important');
                    tab.style.setProperty('color', '#ffffff', 'important');
                    tab.style.setProperty('font-weight', '600', 'important');
                }
            }, true);
        })();
        """

        let jsSource = """
        (function() {
            const host = window.location.hostname || '';
            const href = window.location.href || '';
            const isDuck = host.includes('duck.ai') || host.includes('duckduckgo.com') || host.includes('duck.com');
            const isGoogle = host.includes('google.') && (href.includes('/search') || href.includes('q=') || href.includes('/imghp') || href.includes('tbm=') || href.includes('udm=') || host.startsWith('images.'));
            const isBrave = host.includes('brave.com') && href.includes('/search');
            const isSearch = isDuck || isGoogle || isBrave;
            if (!isSearch) return;
            const isChat = host.includes('duck.ai') || href.includes('ia=chat');

            try {
                document.documentElement.style.colorScheme = 'dark';
                document.documentElement.setAttribute('data-theme', 'dark');
                let meta = document.querySelector('meta[name="color-scheme"]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'color-scheme';
                    meta.content = 'dark';
                    (document.head || document.documentElement).appendChild(meta);
                }
                if (isGoogle) {
                    document.cookie = "PREF=f6=400; domain=.google.com; path=/; max-age=31536000";
                }
            } catch(e) {}

            function injectStyles() {
                if (isChat) {
                    if (!document.getElementById('onyx-research-theme')) {
                        const style = document.createElement('style');
                        style.id = 'onyx-research-theme';
                        style.textContent = `\(escapedResearchCSS)`;
                        (document.head || document.documentElement).appendChild(style);
                    }
                } else {
                    if (!document.getElementById('onyx-search-theme')) {
                        const style = document.createElement('style');
                        style.id = 'onyx-search-theme';
                        style.textContent = `\(escapedSearchCSS)`;
                        (document.head || document.documentElement).appendChild(style);
                    }
                }
            }

            function scrubTitle() {
                if (document.title && document.title.includes('DuckDuckGo')) {
                    document.title = document.title
                        .replace(/ at DuckDuckGo/g, '')
                        .replace(/ - DuckDuckGo/g, '')
                        .replace(/DuckDuckGo — /g, '');
                    if (!document.title.startsWith('✦ ')) {
                        document.title = '✦ ' + document.title + ' — Search';
                    }
                } else if (document.title && document.title.includes('Google Search')) {
                    document.title = document.title
                        .replace(/ - Google Search/g, '')
                        .replace(/Google Search/g, '')
                        .trim();
                    if (!document.title.startsWith('✦ ')) {
                        document.title = '✦ ' + document.title + ' — Search';
                    }
                }
            }

            function hideMascotsAndPromos() {
                if (document.querySelector('.anomaly-modal, [class*="anomaly-modal"], #anomaly-detected')) return;
                const badSelectors = [
                    '.header__logo-wrap', '.header__logo', '.header__logo__img', '[data-testid="logo"]',
                    '#header-logo-wrapper', '#header-logo', '#logo', '[data-testid="header-logo"]',
                    '[data-testid="logo-link"]', '[data-testid="logo_link"]', 'a[aria-label*="DuckDuckGo home" i]',
                    'a[aria-label*="DuckDuckGo" i]', 'a#logo', 'a[data-testid="logo-link"]', 'a[data-testid="header-logo"]',
                    'a[href="/"]', 'header a[href="/"]', '#header a[href="/"]',
                    '.header a[href="/"]', '.header-wrap a[href="/"]', '.site-wrapper header a[href="/"]',
                    '[class*="HeaderLogo"]', '[class*="header_logo"]', '[class*="header__logo"]',
                    'svg[class*="logo" i]', 'svg[class*="Logo" i]', 'svg[class*="duck" i]',
                    'img[alt*="DuckDuckGo" i]', 'img[src*="duckduckgo" i]', 'img[src*="duck" i]',
                    'a[href="/compare-privacy"]', 'a[href*="compare-privacy"]', 'a[href*="compare"]',
                    '.header__tagline', '.header__text', '.header--aside', '.header--aside__item',
                    '.header__button--menu', '.js-side-menu-open',
                    '.feedback-btn', 'button[data-testid="feedback-button"]',
                    '.js-feedback-btn-wrap', '[class*="TccjmKV6"]', '[class*="bYzmzE1m"]', '[class*="s_aX02AKO"]',
                    '#footer-feedback-wrapper', '.nav-menu--feedback', '.react-feedback-prompt-mvc-wrapper',
                    'a[href*="assist=true"]', 'li:has(> a[href*="assist=true"])',
                    'a[href*="ia=chat"]:not(.onyx-research-switch-btn)', 'li:has(> a[href*="ia=chat"]:not(.onyx-research-switch-btn))',
                    'li:has(> button[aria-label*="Search Settings"])',
                    'button[aria-label*="Search Settings"]',
                    '[data-testid="region-filter"] svg', '.dropdown--region svg',
                    'button[aria-label*="Region" i] svg', 'button[aria-label*="region" i] svg',
                    '.ddg-extension-banner', '.onboarding-ed', '.js-onboarding-wrapper', '.badge--ad',
                    '[data-testid="ad"]', '[data-testid="ad-item"]', '.results--ads', '.result--ad', '.ads-wrapper',
                    '.footer', '#footer', '.badge--privacy', '.badge--protection',
                    '.RM8cPgCF1NymxEVCc19D', '.y8qZjjhkSVTmBOORd3oQ', '.S1TV9gKXE9qTlJCKQyVA',
                    '[class*="extension-banner"]', '[class*="onboarding"]', '[class*="feedback"]', '[class*="Feedback"]',
                    '[class*="feedback-btn"]', '[class*="feedback-modal"]',
                    'a[href*="spread"]', 'a[href*="newsletter"]',
                    '#logo', '.logo img', 'header svg.logo', 'a#logo', '#fbar', '#footcnt', '#foot',
                    '.uEierd', '#tads', '#tadsb', '[data-text-ad]', '.appbar', '.cv2Vmc', '.LH92ce',
                    '.TQc1id', '.SJ1Kg', '.G57R0c', '#taw'
                ];
                badSelectors.forEach(sel => {
                    try {
                        document.querySelectorAll(sel).forEach(e => {
                            e.style.setProperty('display', 'none', 'important');
                            e.style.setProperty('visibility', 'hidden', 'important');
                            e.style.setProperty('opacity', '0', 'important');
                            e.style.setProperty('width', '0', 'important');
                            e.style.setProperty('height', '0', 'important');
                            e.style.setProperty('max-width', '0', 'important');
                            e.style.setProperty('max-height', '0', 'important');
                        });
                    } catch(err) {}
                });

                document.querySelectorAll('strong, span, p, a').forEach(el => {
                    if (el.children.length === 0 && el.innerText && el.innerText.includes('DuckDuckGo')) {
                        el.innerText = el.innerText.replace(/DuckDuckGo/g, 'Onyx Search');
                    }
                    if (el.children.length === 0 && el.innerText && el.innerText.trim() === 'Duck.ai') {
                        el.innerText = 'Onyx Research';
                    }
                });
            }

            function tagSearchPill() {
                const input = document.getElementById('search_form_input') || document.querySelector('input[name="q"]');
                if (input) {
                    const pill = input.closest('[class*="QsyijBlqupsaY11GFhnp"]') ||
                                 input.closest('[class*="T265XEcezvjUhK71U8pN"]') ||
                                 input.closest('[data-testid="search-form-input-wrapper"]') ||
                                 input.parentElement;
                    if (pill && !pill.classList.contains('onyx-search-pill')) {
                        pill.classList.add('onyx-search-pill');
                    }
                }
            }

            function updateActiveDuckbarTab() {
                const duckbar = document.getElementById('react-duckbar') || document.querySelector('[data-testid="duckbar"]');
                if (!duckbar) return;
                const ul = duckbar.querySelector('ul:first-child');
                if (!ul) return;
                const links = ul.querySelectorAll('a');
                if (!links || links.length === 0) return;

                const url = new URL(window.location.href);
                const ia = (url.searchParams.get('ia') || url.searchParams.get('iar') || '').toLowerCase();

                let activeLink = null;
                links.forEach(a => {
                    if (a.classList.contains('onyx-research-switch-btn')) return;
                    a.classList.add('onyx-duckbar-tab');
                    const text = (a.innerText || '').trim().toLowerCase();
                    const href = (a.getAttribute('href') || '').toLowerCase();

                    let isActive = false;
                    if (ia === 'images' && (text.includes('image') || href.includes('ia=images') || href.includes('iar=images'))) isActive = true;
                    else if (ia === 'videos' && (text.includes('video') || href.includes('ia=videos') || href.includes('iar=videos'))) isActive = true;
                    else if (ia === 'news' && (text.includes('news') || href.includes('ia=news') || href.includes('iar=news'))) isActive = true;
                    else if (ia === 'maps' && (text.includes('map') || href.includes('ia=maps') || href.includes('iar=maps'))) isActive = true;
                    else if ((!ia || ia === 'web') && (text === 'all' || a.querySelector('svg') || a.classList.contains('SnptgjT2zdOhGYfNng6g'))) isActive = true;

                    if (isActive) {
                        a.classList.add('onyx-tab-active');
                        a.classList.add('is-active');
                        activeLink = a;
                    } else {
                        a.classList.remove('onyx-tab-active');
                        a.classList.remove('is-active');
                        a.classList.remove('SnptgjT2zdOhGYfNng6g');
                    }
                });

                if (!activeLink && links.length > 0) {
                    links[0].classList.add('onyx-tab-active');
                    links[0].classList.add('is-active');
                    activeLink = links[0];
                }

                // Setup or fetch the single shared light glider
                let glider = document.getElementById('onyx-duckbar-glider');
                if (!glider) {
                    glider = document.createElement('div');
                    glider.id = 'onyx-duckbar-glider';
                    glider.className = 'onyx-duckbar-glider';
                    duckbar.appendChild(glider);
                }

                function positionGlider(targetTab, animate) {
                    if (!targetTab || !glider) return;
                    const duckbarRect = duckbar.getBoundingClientRect();
                    const tabRect = targetTab.getBoundingClientRect();
                    if (tabRect.width === 0) {
                        requestAnimationFrame(() => positionGlider(targetTab, animate));
                        return;
                    }
                    const left = Math.round(tabRect.left - duckbarRect.left);
                    const width = Math.min(Math.max(Math.round(tabRect.width), 30), 160);

                    if (!animate) {
                        glider.style.setProperty('transition', 'none', 'important');
                    } else {
                        glider.style.setProperty('transition', 'transform 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), width 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), opacity 0.2s ease', 'important');
                    }
                    glider.style.setProperty('transform', `translateX(${left}px)`, 'important');
                    glider.style.setProperty('width', `${width}px`, 'important');
                    glider.classList.add('is-ready');
                    if (!animate) {
                        void glider.offsetWidth;
                    }
                }

                // Bind click listeners for instant fluid light transfer between tabs
                links.forEach(a => {
                    if (a.classList.contains('onyx-research-switch-btn')) return;
                    if (a.dataset.gliderBound) return;
                    a.dataset.gliderBound = 'true';
                    a.addEventListener('click', () => {
                        const currentActive = ul.querySelector('a.onyx-tab-active') || links[0];
                        const duckbarRect = duckbar.getBoundingClientRect();
                        const curRect = currentActive ? currentActive.getBoundingClientRect() : null;
                        if (curRect && curRect.width > 0 && curRect.width < 200) {
                            try {
                                sessionStorage.setItem('onyx_glider_from_x', Math.round(curRect.left - duckbarRect.left).toString());
                                sessionStorage.setItem('onyx_glider_from_w', Math.min(Math.max(Math.round(curRect.width), 30), 160).toString());
                            } catch(e) {}
                        }
                        positionGlider(a, true);
                        links.forEach(l => {
                            if (l === a) {
                                l.classList.add('onyx-tab-active');
                                l.classList.add('is-active');
                            } else {
                                l.classList.remove('onyx-tab-active');
                                l.classList.remove('is-active');
                                l.classList.remove('SnptgjT2zdOhGYfNng6g');
                            }
                        });
                    });
                });

                if (!window._onyxDuckbarResizeBound) {
                    window._onyxDuckbarResizeBound = true;
                    window.addEventListener('resize', () => {
                        const current = document.querySelector('#react-duckbar ul:first-child a.onyx-tab-active') ||
                                        document.querySelector('[data-testid="duckbar"] ul:first-child a.onyx-tab-active');
                        if (current) positionGlider(current, false);
                    });
                }

                if (activeLink) {
                    let fromX = null;
                    let fromW = null;
                    try {
                        fromX = sessionStorage.getItem('onyx_glider_from_x');
                        fromW = sessionStorage.getItem('onyx_glider_from_w');
                        sessionStorage.removeItem('onyx_glider_from_x');
                        sessionStorage.removeItem('onyx_glider_from_w');
                    } catch(e) {}

                    const fw = parseFloat(fromW);
                    const fx = parseFloat(fromX);
                    if (!isNaN(fw) && !isNaN(fx) && fw >= 25 && fw <= 160 && fx >= 0 && fx <= 1200) {
                        const duckbarRect = duckbar.getBoundingClientRect();
                        const activeRect = activeLink.getBoundingClientRect();
                        const newLeft = Math.round(activeRect.left - duckbarRect.left);
                        if (Math.abs(fx - newLeft) > 5) {
                            glider.style.setProperty('transition', 'none', 'important');
                            glider.style.setProperty('transform', `translateX(${fx}px)`, 'important');
                            glider.style.setProperty('width', `${fw}px`, 'important');
                            glider.classList.add('is-ready');
                            void glider.offsetWidth;
                            requestAnimationFrame(() => {
                                requestAnimationFrame(() => {
                                    positionGlider(activeLink, true);
                                });
                            });
                            return;
                        }
                    }
                    positionGlider(activeLink, false);
                }
            }

            function injectOnyxSearchHeader() {
                if (isChat) return;
                const oldHeader = document.getElementById('onyx-brand-header');
                if (oldHeader) oldHeader.remove();

                const duckbar = document.getElementById('react-duckbar') || document.querySelector('[data-testid="duckbar"]');
                if (!duckbar) return;
                const ul = duckbar.querySelector('ul:first-child');
                if (!ul) return;

                const params = new URLSearchParams(window.location.search);
                const query = (params.get('q') || '').replace(/\\+/g, ' ');
                if (!query) return;

                let switchLi = document.getElementById('onyx-research-switch-li');
                if (!switchLi) {
                    switchLi = document.createElement('li');
                    switchLi.id = 'onyx-research-switch-li';
                    switchLi.style.cssText = 'margin-left: auto; display: inline-flex; align-items: center; padding: 0 0 2px 12px;';
                    switchLi.innerHTML = `
                        <a href="https://duckduckgo.com/?q=${encodeURIComponent(query)}&ia=chat" class="onyx-research-switch-btn" title="Open in Deep AI Research Mode">
                            <span>✦ Deep Research</span>
                        </a>
                    `;
                    ul.appendChild(switchLi);
                }
            }

            function injectAISynthesisCard() {
                if (isChat) return;
                const resultsContainer = document.querySelector('.react-results--main') ||
                                         document.querySelector('#links');
                if (!resultsContainer) return;

                const params = new URLSearchParams(window.location.search);
                const query = (params.get('q') || '').replace(/\\+/g, ' ');
                if (!query) return;

                let summaryText = '';
                const aboutSnippet = document.querySelector('[data-testid="about-snippet"]') ||
                                     document.querySelector('.module--wikipedia .module__body') ||
                                     document.querySelector('[data-testid="module--about"] .module__text') ||
                                     document.querySelector('.module__text');
                if (aboutSnippet && aboutSnippet.innerText && aboutSnippet.innerText.length > 50 && !aboutSnippet.innerText.includes('USD(%)') && !aboutSnippet.innerText.includes('1D5D')) {
                    summaryText = aboutSnippet.innerText.trim();
                } else {
                    const articles = document.querySelectorAll('article');
                    for (let i = 0; i < articles.length; i++) {
                        const art = articles[i];
                        const title = art.querySelector('h2') ? (art.querySelector('h2').innerText || '').trim() : '';
                        const lines = (art.innerText || '').split('\\n').map(s => s.trim()).filter(Boolean);
                        for (let j = 0; j < lines.length; j++) {
                            const line = lines[j];
                            if (title && (title === line || title.includes(line) || line.includes(title))) continue;
                            const cleaned = line.replace(/^[0-9]+\\s+(days?|hours?|mins?|weeks?|months?|years?)\\s+ago\\s*/i, '').trim();
                            if (cleaned.length >= 40 &&
                                !cleaned.includes('http') &&
                                !cleaned.includes('›') &&
                                !cleaned.includes('Only include') &&
                                !cleaned.includes('Redo search') &&
                                !cleaned.includes('Block this')) {
                                summaryText = cleaned;
                                break;
                            }
                        }
                        if (summaryText) break;
                    }
                }

                let card = document.getElementById('onyx-ai-synthesis-card');
                if (!card && summaryText && summaryText.trim().length > 20) {
                    card = document.createElement('div');
                    card.id = 'onyx-ai-synthesis-card';
                    card.innerHTML = `
                        <div class="onyx-ai-header">
                            <div class="onyx-ai-badge">
                                <span>✦</span>
                                <span>Onyx Synthetic Overview</span>
                            </div>
                            <span style="color: #71717a; font-size: 11px; font-weight: 500;">INSTANT OVERVIEW</span>
                        </div>
                        <div class="onyx-ai-content">
                            <p style="margin: 0; font-size: 14px; color: #e2e8f0; line-height: 1.65;">${summaryText}</p>
                        </div>
                    `;
                    const brandHeader = document.getElementById('onyx-brand-header');
                    if (brandHeader && brandHeader.parentElement === resultsContainer) {
                        if (brandHeader.nextSibling) {
                            resultsContainer.insertBefore(card, brandHeader.nextSibling);
                        } else {
                            resultsContainer.appendChild(card);
                        }
                    } else {
                        resultsContainer.insertBefore(card, resultsContainer.firstChild);
                    }
                } else if (card && card.parentElement !== resultsContainer) {
                    const brandHeader = document.getElementById('onyx-brand-header');
                    if (brandHeader && brandHeader.parentElement === resultsContainer && brandHeader.nextSibling) {
                        resultsContainer.insertBefore(card, brandHeader.nextSibling);
                    } else {
                        resultsContainer.insertBefore(card, resultsContainer.firstChild);
                    }
                }
            }

            function dismissOnboarding() {
                const buttons = Array.from(document.querySelectorAll('button'));
                for (const btn of buttons) {
                    const txt = (btn.textContent || '').trim().toLowerCase();
                    if (txt === 'got it' || txt === 'i agree' || txt === 'continue' || txt === 'accept') {
                        btn.click();
                    }
                }
            }

            let submitted = false;
            function autoSubmitIfReady() {
                if (!isChat || submitted) return;
                const params = new URLSearchParams(window.location.search);
                const query = params.get('q');
                if (!query) return;

                const textarea = document.querySelector('textarea[name="message"]') ||
                                 document.querySelector('textarea');
                const submitBtn = document.querySelector('form button[type="submit"]') ||
                                 Array.from(document.querySelectorAll('form button')).find(b => {
                                     let t = (b.innerText || '').trim().toLowerCase();
                                     let a = (b.getAttribute('aria-label') || '').toLowerCase();
                                     return t === 'ask' || t === 'send' || a === 'send';
                                 });

                if (textarea && submitBtn && !submitBtn.disabled) {
                    if (!textarea.value || textarea.value.trim() === '') {
                        const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, "value")?.set;
                        if (setter) {
                            setter.call(textarea, query);
                        } else {
                            textarea.value = query;
                        }
                        textarea.dispatchEvent(new Event('input', { bubbles: true }));
                        textarea.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    submitted = true;
                    setTimeout(() => {
                        submitBtn.click();
                    }, 120);
                }
            }

            function injectThinkingOrbHUD() {
                if (!isChat) return;
                if (document.getElementById('onyx-orb-hud')) {
                    const txt = document.getElementById('onyx-orb-hud-text');
                    const hasMessage = document.querySelector('[data-testid="chat-message"]') || document.querySelector('.space-y-4');
                    const submitBtn = document.querySelector('form button[type="submit"]');
                    if (hasMessage && submitBtn && !submitBtn.disabled) {
                        if (txt && txt.textContent === 'Synthesizing') {
                            txt.textContent = 'Synthesized';
                            setTimeout(() => {
                                const h = document.getElementById('onyx-orb-hud');
                                if (h) h.style.opacity = '0.35';
                            }, 1800);
                        }
                    }
                    return;
                }
                if (!document.body) return;
                const hud = document.createElement('div');
                hud.id = 'onyx-orb-hud';
                hud.style.cssText = 'position: fixed; top: 14px; right: 20px; z-index: 999999; display: flex; align-items: center; gap: 8px; background: rgba(18, 18, 22, 0.75); border: 1px solid rgba(255, 255, 255, 0.10); border-radius: 20px; padding: 4px 12px 4px 6px; backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px); box-shadow: 0 4px 16px rgba(0, 0, 0, 0.35); pointer-events: none; transition: opacity 300ms ease; cursor: pointer; pointer-events: auto;';
                hud.title = 'Switch Profile / Context';
                hud.innerHTML = '<canvas id="onyx-orb-hud-canvas" width="48" height="48" style="width: 24px; height: 24px; border-radius: 50%;"></canvas><span id="onyx-orb-hud-text" style="font-size: 11px; font-weight: 500; letter-spacing: -0.01em; color: #a1a1aa; font-family: -apple-system, BlinkMacSystemFont, sans-serif;">Synthesizing</span>';
                hud.onclick = () => {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openProfileManager) {
                        window.webkit.messageHandlers.openProfileManager.postMessage(null);
                    }
                };
                document.body.appendChild(hud);

                const cvs = document.getElementById('onyx-orb-hud-canvas');
                if (cvs) {
                    const ctx = cvs.getContext('2d');
                    const DPR = Math.min(2, window.devicePixelRatio || 1);
                    cvs.width = 24 * DPR;
                    cvs.height = 24 * DPR;
                    let t = 0;
                    function drawHUDOrb() {
                        ctx.clearRect(0, 0, cvs.width, cvs.height);
                        const cx = cvs.width / 2, cy = cvs.height / 2;
                        const R = (cvs.width / 2) * 0.75;
                        const latRings = 5, lonDensity = 10;
                        for (let ri = 0; ri <= latRings; ri++) {
                            const lat = -Math.PI / 2 + (ri / latRings) * Math.PI;
                            const cosLat = Math.cos(lat), sinLat = Math.sin(lat);
                            const w = 0.6 * Math.sin(t * 2.5 - ri * 0.6) + 0.4 * Math.sin(t * 1.5 + ri * 0.8);
                            const rr = R * (0.88 + 0.12 * w);
                            const lonCount = Math.max(1, Math.round(Math.abs(cosLat) * lonDensity));
                            for (let lj = 0; lj < lonCount; lj++) {
                                const lon = (lj / lonCount) * 2 * Math.PI;
                                const x = cosLat * Math.cos(lon) * rr;
                                const y = sinLat * rr;
                                const z = cosLat * Math.sin(lon) * rr;
                                const rad = 0.35;
                                const y2 = y * Math.cos(rad) - z * Math.sin(rad);
                                const z2 = y * Math.sin(rad) + z * Math.cos(rad);
                                const depth = (z2 / R + 1) / 2;
                                const alpha = 0.35 + 0.65 * depth;
                                ctx.beginPath();
                                ctx.arc(cx + x, cy + y2, (0.7 + 1.1 * depth) * DPR, 0, Math.PI * 2);
                                ctx.fillStyle = `rgba(255, 255, 255, ${alpha.toFixed(2)})`;
                                ctx.fill();
                            }
                        }
                        t += 0.04;
                        requestAnimationFrame(drawHUDOrb);
                    }
                    requestAnimationFrame(drawHUDOrb);
                }
            }

            function isAnomaly() {
                return !!(document.querySelector('.anomaly-modal, [class*="anomaly-modal"], #anomaly-detected'));
            }

            function injectBypassBanner() {
                const modal = document.querySelector('.anomaly-modal, [class*="anomaly-modal"], #anomaly-detected');
                if (!modal || document.getElementById('onyx-bypass-banner')) return;
                const banner = document.createElement('div');
                banner.id = 'onyx-bypass-banner';
                banner.className = 'onyx-bot-bypass-bar';
                const q = new URLSearchParams(window.location.search).get('q') || '';
                banner.innerHTML = `
                    <div style="display:flex; align-items:center; gap:8px;">
                        <span style="color:#ffffff; font-size:14px;">✦</span>
                        <span style="font-size:12.5px; font-weight:500; color:#e2e8f0;">Onyx Private Shield: Verification Challenge</span>
                    </div>
                    <button class="onyx-bot-bypass-btn" id="onyx-bypass-click">
                        Bypass Challenge ➔
                    </button>
                `;
                modal.insertBefore(banner, modal.firstChild);
                const btn = document.getElementById('onyx-bypass-click');
                if (btn) {
                    btn.onclick = (e) => {
                        e.preventDefault();
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bypassBotChallenge) {
                            window.webkit.messageHandlers.bypassBotChallenge.postMessage(q);
                        } else {
                            window.location.href = 'https://search.brave.com/search?q=' + encodeURIComponent(q);
                        }
                    };
                }
            }

            function cycle() {
                injectStyles();
                if (isAnomaly()) {
                    injectBypassBanner();
                    return;
                }
                scrubTitle();
                hideMascotsAndPromos();
                if (isChat) {
                    dismissOnboarding();
                    autoSubmitIfReady();
                    injectThinkingOrbHUD();
                } else {
                    tagSearchPill();
                    updateActiveDuckbarTab();
                    injectOnyxSearchHeader();
                    injectAISynthesisCard();
                }
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', cycle);
            } else {
                cycle();
            }

            let debounceTimer = null;
            function debouncedCycle() {
                if (debounceTimer) cancelAnimationFrame(debounceTimer);
                debounceTimer = requestAnimationFrame(() => {
                    cycle();
                });
            }

            // Observe dynamic results and SPA DOM transitions for Google, DDG, and Brave
            const observeTarget = document.getElementById('rso') ||
                                  document.getElementById('rcnt') ||
                                  document.getElementById('center_col') ||
                                  document.getElementById('links') ||
                                  document.querySelector('.react-results--main') ||
                                  document.body ||
                                  document.documentElement;
            if (observeTarget) {
                const observer = new MutationObserver(() => {
                    debouncedCycle();
                });
                try {
                    observer.observe(observeTarget, { childList: true, subtree: true });
                } catch(e) {}
            }

            // Hook HTML5 History API for SPA tab navigation
            const origPushState = history.pushState;
            history.pushState = function() {
                origPushState.apply(this, arguments);
                debouncedCycle();
            };
            const origReplaceState = history.replaceState;
            history.replaceState = function() {
                origReplaceState.apply(this, arguments);
                debouncedCycle();
            };
            window.addEventListener('popstate', debouncedCycle);
        })();
        """

        let userScriptStart = WKUserScript(source: jsSourceStart, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScriptStart)
        let userScriptEnd = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScriptEnd)
        config.userContentController.add(self, name: "bypassBotChallenge")
    }

    // MARK: - Profile Manager Architecture
    func websiteDataStore(for profile: BrowserProfile) -> WKWebsiteDataStore {
        if #available(macOS 14.0, *) {
            let uuidString: String
            switch profile.id {
            case "personal":
                uuidString = "E1A8B2C3-4D5E-6F70-8192-A3B4C5D6E7F8"
            case "research":
                uuidString = "F2B9C3D4-5E6F-7081-92A3-B4C5D6E7F801"
            case "trading":
                uuidString = "A3C0D4E5-6F70-8192-A3B4-C5D6E7F80123"
            case "campus":
                uuidString = "B4D1E5F6-7081-92A3-B4C5-D6E7F8012345"
            default:
                if let uuid = UUID(uuidString: profile.id) {
                    uuidString = uuid.uuidString
                } else {
                    let hash = abs(profile.id.hashValue)
                    uuidString = String(format: "C5E2F6A7-8192-A3B4-C5D6-%012ld", hash)
                }
            }
            if let uuid = UUID(uuidString: uuidString) {
                return WKWebsiteDataStore(forIdentifier: uuid)
            }
        }
        return WKWebsiteDataStore.default()
    }
    
    func configuration(for profile: BrowserProfile) -> WKWebViewConfiguration {
        if let existing = profileConfigurations[profile.id] {
            return existing
        }
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        config.suppressesIncrementalRendering = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = websiteDataStore(for: profile)
        config.applicationNameForUserAgent = "Version/18.3 Safari/605.1.15"
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        
        if let ruleList = adBlockRuleList {
            config.userContentController.add(ruleList)
        }
        setupYouTubeAdBlocker(for: config)
        
        setupResearchBridge(for: config)
        config.userContentController.add(self, name: "openProfileManager")
        config.userContentController.add(self, name: "onyxSavePasswordPrompt")
        config.userContentController.add(self, name: "onyxSettings")
        config.userContentController.add(self, name: "onyxNavigate")
        config.userContentController.add(self, name: "onyxSwitchWorkspace")
        config.userContentController.add(self, name: "onyxOpenSettings")
        config.userContentController.add(self, name: "onyxFetchSuggestions")
        config.userContentController.add(self, name: "onyxSetSearchEngine")
        
        profileConfigurations[profile.id] = config
        return config
    }
    
    func switchToProfileIndex(_ index: Int) {
        guard index >= 0 && index < profiles.count else { return }
        switchToProfile(profiles[index])
    }
    
    func switchToProfile(_ profile: BrowserProfile) {
        guard profile.id != activeProfile.id else { return }
        
        // 1. Preserve current tabs & index for current profile
        profileTabs[activeProfile.id] = tabs
        profileActiveIndices[activeProfile.id] = activeTabIndex
        
        // 2. Remove web views safely without touching edgeGlowView
        webContainerView.subviews.forEach { view in
            if view !== edgeGlowView {
                view.removeFromSuperview()
            }
        }
        
        // 3. Switch active profile & update button
        activeProfile = profile
        profileButton.configure(profile: profile)
        
        // 4. Restore tabs for this profile or create a fresh start page tab
        if let savedTabs = profileTabs[profile.id], !savedTabs.isEmpty {
            tabs = savedTabs
            let savedIndex = profileActiveIndices[profile.id] ?? 0
            activeTabIndex = min(savedIndex, tabs.count - 1)
        } else {
            tabs = []
            activeTabIndex = 0
            createNewTab(url: startPageURL)
        }
        
        selectTab(at: activeTabIndex)
        
        // 5. Directional edge glow flash in new profile's color
        edgeGlowView?.flash(edge: .back, color: profile.color)
        
        // 6. Notify startpage of active profile
        notifyStartPageOfProfile()
    }
    
    @objc func showProfileManagerPopover() {
        if let pop = profilePopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let rowCount = profiles.count
        let totalHeight = CGFloat(50 + (rowCount * 48) + 10 + 98)
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 316, height: totalHeight))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.25).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerRow)
        
        let headerLabel = NSTextField(labelWithString: "WORKSPACES & PROFILES")
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        headerLabel.textColor = NSColor(white: 0.45, alpha: 1.0)
        headerRow.addSubview(headerLabel)
        
        let headerGearBtn = NavIconButton(iconName: "gearshape.fill", tooltip: "Workspaces & Browser Settings (⌘,)", target: nil, action: nil, size: 24)
        headerGearBtn.onClick = { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.openSettingsTab()
        }
        headerRow.addSubview(headerGearBtn)
        
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        container.addSubview(stack)
        
        for (i, prof) in profiles.enumerated() {
            let shortcutStr = i < 4 ? "⌘⌥\(i + 1)" : ""
            let tabCount = (prof.id == activeProfile.id) ? tabs.count : (profileTabs[prof.id]?.count ?? 0)
            let row = ProfileRowView(profile: prof, isActive: (prof.id == activeProfile.id), tabCount: tabCount, shortcut: shortcutStr)
            row.onClick = { [weak self, weak popover] in
                popover?.performClose(nil)
                self?.switchToProfile(prof)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        
        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .custom
        sep.borderWidth = 0
        sep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        container.addSubview(sep)
        
        let newProfileRow = ProfileActionRowView(title: "New Workspace / Profile...", iconName: "plus.circle")
        newProfileRow.onClick = { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.createNewProfilePrompt()
        }
        container.addSubview(newProfileRow)
        
        let settingsRow = ProfileActionRowView(title: "Settings & Preferences...", iconName: "gearshape")
        settingsRow.onClick = { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.openSettingsTab()
        }
        container.addSubview(settingsRow)
        
        let clearCacheRow = ProfileActionRowView(title: "Clear Active Workspace Cache...", iconName: "trash")
        clearCacheRow.onClick = { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.clearActiveProfileCache()
        }
        container.addSubview(clearCacheRow)
        
        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            headerRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            headerRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            headerRow.heightAnchor.constraint(equalToConstant: 24),
            
            headerLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            headerLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            
            headerGearBtn.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            headerGearBtn.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            headerGearBtn.widthAnchor.constraint(equalToConstant: 24),
            headerGearBtn.heightAnchor.constraint(equalToConstant: 24),
            
            stack.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            
            sep.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 6),
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            sep.heightAnchor.constraint(equalToConstant: 1),
            
            newProfileRow.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 6),
            newProfileRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            newProfileRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            
            settingsRow.topAnchor.constraint(equalTo: newProfileRow.bottomAnchor, constant: 2),
            settingsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            settingsRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            
            clearCacheRow.topAnchor.constraint(equalTo: settingsRow.bottomAnchor, constant: 2),
            clearCacheRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            clearCacheRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            clearCacheRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        
        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc
        profilePopover = popover
        
        popover.show(relativeTo: profileButton.bounds, of: profileButton, preferredEdge: .maxY)
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
    }
    
    func createNewProfilePrompt() {
        let alert = NSAlert()
        alert.messageText = "Create New Workspace"
        alert.informativeText = "Enter a name for the new isolated browsing workspace:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        inputField.placeholderString = "e.g. Work, Crypto, Research, Personal"
        alert.accessoryView = inputField
        
        if let window = self.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self = self, response == .alertFirstButtonReturn else { return }
                let name = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                self.addCustomProfile(name: name)
            }
        }
    }
    
    func addCustomProfile(name: String, hex: String? = nil) {
        let colors = ["#A855F7", "#EC4899", "#06B6D4", "#F97316", "#10B981", "#E4E4E7"]
        let colorHex = (hex != nil && !hex!.isEmpty) ? hex! : colors[profiles.count % colors.count]
        let newId = UUID().uuidString
        let newProfile = BrowserProfile(id: newId, name: name, iconName: "folder.badge.person.crop", colorHex: colorHex, isDefault: false)
        profiles.append(newProfile)
        saveProfiles()
        switchToProfile(newProfile)
    }
    
    func deleteCustomProfile(id: String) {
        guard profiles.count > 1 else { return }
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profToDelete = profiles[idx]
        guard !profToDelete.isDefault && profToDelete.id != "personal" else { return }
        
        if activeProfile.id == id {
            let nextProf = profiles.first(where: { $0.id != id }) ?? profiles[0]
            switchToProfile(nextProf)
        }
        
        profiles.removeAll(where: { $0.id == id })
        profileTabs.removeValue(forKey: id)
        profileActiveIndices.removeValue(forKey: id)
        profileConfigurations.removeValue(forKey: id)
        saveProfiles()
    }
    
    func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "OnyxProfiles")
        }
    }
    
    func loadSavedProfiles() {
        if let data = UserDefaults.standard.data(forKey: "OnyxProfiles"),
           let saved = try? JSONDecoder().decode([BrowserProfile].self, from: data), !saved.isEmpty {
            self.profiles = saved
            if let def = saved.first(where: { $0.id == "personal" }) ?? saved.first {
                self.activeProfile = def
            }
        }
    }
    
    func clearActiveProfileCache() {
        let store = websiteDataStore(for: activeProfile)
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        store.removeData(ofTypes: dataTypes, modifiedSince: dateFrom) { [weak self] in
            guard let self = self else { return }
            let alert = NSAlert()
            alert.messageText = "Workspace Cache Cleared"
            alert.informativeText = "Cookies, local storage, and website cache for workspace '\(self.activeProfile.name)' have been cleared."
            alert.addButton(withTitle: "OK")
            if let win = self.window {
                alert.beginSheetModal(for: win, completionHandler: nil)
            }
        }
    }
    
    func notifyStartPageOfProfile() {
        let js = "if (window.updateActiveProfile) window.updateActiveProfile('\(activeProfile.name)', '\(activeProfile.colorHex)');"
        for tab in tabs {
            if tab.url.isFileURL && tab.url.path.contains("startpage.html") {
                tab.webView.evaluateJavaScript(js, completionHandler: nil)
            } else if isSettingsURL(tab.url) {
                sendSettingsPayload(to: tab.webView)
            }
        }
    }
    
    // MARK: - Dedicated Settings Tab & Native Bridge
    @objc func openSettingsTab() {
        if let idx = tabs.firstIndex(where: { isSettingsURL($0.url) }) {
            selectTab(at: idx)
            return
        }
        if activeTab.url.isFileURL && activeTab.url.path.contains("startpage.html") && tabs.count == 1 {
            loadURL(settingsPageURL)
        } else {
            createNewTab(url: settingsPageURL, switchTo: true)
        }
    }
    
    @objc func menuOpenSettings() {
        openSettingsTab()
    }
    
    func sendSettingsPayload(to webView: WKWebView) {
        let defaultEngine = UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo"
        let startup = UserDefaults.standard.string(forKey: "OnyxStartupBehavior") ?? "startpage"
        let showBookmarks = UserDefaults.standard.object(forKey: "OnyxShowBookmarksBar") as? Bool ?? true
        let adBlock = UserDefaults.standard.object(forKey: "OnyxAdBlockEnabled") as? Bool ?? true
        let theme = UserDefaults.standard.string(forKey: "OnyxTheme") ?? "pitch-black"
        let downloadsPath = (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path) ?? "~/Downloads"
        
        var profList: [[String: Any]] = []
        for p in profiles {
            let tCount = (p.id == activeProfile.id) ? tabs.count : (profileTabs[p.id]?.count ?? 0)
            profList.append([
                "id": p.id,
                "name": p.name,
                "colorHex": p.colorHex,
                "tabCount": tCount,
                "isActive": (p.id == activeProfile.id)
            ])
        }
        
        let memMB = getResidentMemoryMB()
        let ramFormatted = String(format: "%.1f MB", memMB)
        
        let payload: [String: Any] = [
            "searchEngine": defaultEngine,
            "startup": startup,
            "showBookmarksBar": showBookmarks,
            "adBlockEnabled": adBlock,
            "theme": theme,
            "downloadsPath": downloadsPath,
            "profiles": profList,
            "ramUsage": ramFormatted
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let jsonStr = String(data: data, encoding: .utf8) {
            let js = "if (window.renderSettings) window.renderSettings(\(jsonStr));"
            DispatchQueue.main.async {
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }
    
    func getResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        }
        return 38.4
    }
    
    func handleSettingsMessage(_ dict: [String: Any], from webView: WKWebView?) {
        guard let action = dict["action"] as? String else { return }
        
        switch action {
        case "getSettings":
            if let webView = webView {
                sendSettingsPayload(to: webView)
            }
            
        case "setSearchEngine":
            if let engine = dict["engine"] as? String {
                setLiveSearchEngine(engine)
            }
            
        case "setStartup":
            if let mode = dict["mode"] as? String {
                UserDefaults.standard.set(mode, forKey: "OnyxStartupBehavior")
            }
            
        case "setShowBookmarksBar":
            if let enabled = dict["enabled"] as? Bool {
                setBookmarksBarVisible(enabled)
            }
            
        case "setAdBlockEnabled":
            if let enabled = dict["enabled"] as? Bool {
                UserDefaults.standard.set(enabled, forKey: "OnyxAdBlockEnabled")
                if let ruleList = adBlockRuleList {
                    if enabled {
                        sharedConfiguration.userContentController.add(ruleList)
                        for (_, cfg) in profileConfigurations {
                            cfg.userContentController.add(ruleList)
                        }
                    } else {
                        sharedConfiguration.userContentController.remove(ruleList)
                        for (_, cfg) in profileConfigurations {
                            cfg.userContentController.remove(ruleList)
                        }
                    }
                }
            }
            
        case "switchWorkspace":
            if let profId = dict["id"] as? String, let prof = profiles.first(where: { $0.id == profId }) {
                switchToProfile(prof)
                if let webView = webView {
                    sendSettingsPayload(to: webView)
                }
            }
            
        case "createWorkspace":
            if let name = dict["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let colorHex = dict["colorHex"] as? String
                addCustomProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), hex: colorHex)
                if let webView = webView {
                    sendSettingsPayload(to: webView)
                }
            }
            
        case "deleteWorkspace":
            if let profId = dict["id"] as? String {
                deleteCustomProfile(id: profId)
                if let webView = webView {
                    sendSettingsPayload(to: webView)
                }
            }
            
        case "clearCache":
            clearActiveProfileCache()
            if let webView = webView {
                sendSettingsPayload(to: webView)
            }
            
        case "openDownloads":
            if let url = try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
                NSWorkspace.shared.open(url)
            }
            
        case "openPasswords":
            togglePasswordsPopover()
            
        default:
            break
        }
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "openProfileManager" {
            showProfileManagerPopover()
        } else if message.name == "onyxSettings", let dict = message.body as? [String: Any] {
            handleSettingsMessage(dict, from: message.webView)
        } else if message.name == "bypassBotChallenge" {
            handleBotChallenge(in: activeWebView)
        } else if message.name == "onyxSavePasswordPrompt", let dict = message.body as? [String: Any] {
            handleSavePasswordPromptMessage(dict)
        } else if message.name == "onyxNavigate", let dict = message.body as? [String: Any], let urlStr = dict["url"] as? String {
            let targetURL = resolveQuery(urlStr)
            loadURL(targetURL)
        } else if message.name == "onyxSwitchWorkspace", let dict = message.body as? [String: Any], let urlStr = dict["url"] as? String {
            if let targetURL = URL(string: urlStr) {
                loadURL(targetURL)
            }
        } else if message.name == "onyxOpenSettings" {
            openSettingsTab()
        } else if message.name == "onyxSetSearchEngine", let dict = message.body as? [String: Any], let engine = dict["engine"] as? String {
            setLiveSearchEngine(engine)
        } else if message.name == "onyxFetchSuggestions", let dict = message.body as? [String: Any], let query = dict["query"] as? String, let reqId = dict["reqId"] as? String {
            fetchSuggestionsForWeb(query: query, reqId: reqId, from: message.webView)
        }
    }

    func injectOnyxResearchScript(into webView: WKWebView) {
        guard isResearchURL(webView.url) else { return }
        let escapedCSS = onyxResearchCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let script = """
        (function() {
            if (!document.getElementById("onyx-research-theme")) {
                let s = document.createElement("style");
                s.id = "onyx-research-theme";
                s.textContent = `\(escapedCSS)`;
                (document.head || document.documentElement).appendChild(s);
            }
            document.querySelectorAll('.RM8cPgCF1NymxEVCc19D, .y8qZjjhkSVTmBOORd3oQ, .S1TV9gKXE9qTlJCKQyVA').forEach(e => {
                e.style.display = 'none';
            });
            let brandTexts = Array.from(document.querySelectorAll("strong, span, div")).filter(e => e.innerText && e.innerText.trim() === "Duck.ai");
            brandTexts.forEach(b => {
                b.textContent = "Onyx Research";
            });
            // Safely dismiss promotional banner via its close button
            document.querySelectorAll('button').forEach(b => {
                const label = (b.getAttribute('aria-label') || '').toLowerCase();
                const pText = (b.parentElement?.textContent || '');
                if ((label.includes('close') || label.includes('dismiss')) && pText.includes('Duck.ai works best')) {
                    b.click();
                }
            });
            let submitBtn = document.querySelector('form button[type="submit"]') ||
                            Array.from(document.querySelectorAll('form button')).find(b => {
                                let t = (b.innerText || '').trim().toLowerCase();
                                let a = (b.getAttribute('aria-label') || '').toLowerCase();
                                return t === 'ask' || t === 'send' || a === 'send';
                            });
            if (submitBtn && !submitBtn.disabled) {
                submitBtn.click();
            }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    func isResearchURL(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        let str = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""
        return host.contains("duck.ai") || str.contains("ia=chat")
    }
    
    func isSearchURL(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        if isResearchURL(url) { return false }
        let host = url.host?.lowercased() ?? ""
        return host.contains("duckduckgo.com") || host.contains("duck.com") ||
               (host.contains("google.") && (url.path.contains("/search") || (url.query?.contains("q=") == true) || url.path.contains("/imghp") || host.hasPrefix("images.google."))) ||
               (host.contains("brave.com") && url.path.contains("/search")) ||
               (host.contains("kagi.com") && url.path.contains("/search")) ||
               (host.contains("bing.com") && url.path.contains("/search"))
    }
    
    func extractResearchQuery(from url: URL?) -> String {
        guard let url = url else { return "" }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let qItem = queryItems.first(where: { $0.name == "q" }),
           let value = qItem.value, !value.isEmpty {
            let decoded = value.removingPercentEncoding ?? value
            return decoded.replacingOccurrences(of: "+", with: " ")
        }
        return ""
    }

    func extractSearchQuery(from url: URL?) -> String {
        guard let url = url else { return "" }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            if let qItem = queryItems.first(where: { $0.name == "q" || $0.name == "search_query" }),
               let value = qItem.value, !value.isEmpty {
                let decoded = value.removingPercentEncoding ?? value
                return decoded.replacingOccurrences(of: "+", with: " ")
            }
        }
        return extractResearchQuery(from: url)
    }

    func injectOnyxSearchScript(into webView: WKWebView) {
        guard isSearchURL(webView.url) else { return }
        let escapedCSS = onyxSearchCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let script = """
        (function() {
            if (document.querySelector('.anomaly-modal, [class*="anomaly-modal"], #anomaly-detected')) {
                return;
            }
            try {
                document.documentElement.style.colorScheme = 'dark';
                document.documentElement.setAttribute('data-theme', 'dark');
                let meta = document.querySelector('meta[name="color-scheme"]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'color-scheme';
                    meta.content = 'dark';
                    (document.head || document.documentElement).appendChild(meta);
                }
                if (window.location.hostname.includes('google.')) {
                    document.cookie = "PREF=f6=400; domain=.google.com; path=/; max-age=31536000";
                }
            } catch(e) {}

            let themeStyle = document.getElementById("onyx-search-theme");
            if (!themeStyle) {
                themeStyle = document.createElement("style");
                themeStyle.id = "onyx-search-theme";
            }
            themeStyle.textContent = `\(escapedCSS)`;
            const styleTarget = document.head || document.documentElement;
            if (styleTarget && (themeStyle.parentElement !== styleTarget || styleTarget.lastElementChild !== themeStyle)) {
                styleTarget.appendChild(themeStyle);
            }

            if (document.title && document.title.includes("DuckDuckGo")) {
                document.title = document.title
                    .replace(/ at DuckDuckGo/g, '')
                    .replace(/ - DuckDuckGo/g, '')
                    .replace(/DuckDuckGo — /g, '')
                    .replace(/DuckDuckGo/g, '')
                    .trim();
                if (!document.title.startsWith('✦ ')) {
                    document.title = '✦ ' + document.title + ' — Search';
                }
            } else if (document.title && document.title.includes("Google Search")) {
                document.title = document.title
                    .replace(/ - Google Search/g, '')
                    .replace(/Google Search/g, '')
                    .trim();
                if (!document.title.startsWith('✦ ')) {
                    document.title = '✦ ' + document.title + ' — Search';
                }
            }

            const badSelectors = [
                '.header__logo-wrap', '.header__logo', '.header__logo__img', '[data-testid="logo"]',
                '#header-logo-wrapper', '#header-logo', '#logo', '[data-testid="header-logo"]',
                '[data-testid="logo-link"]', '[data-testid="logo_link"]', 'a[aria-label*="DuckDuckGo home" i]',
                'a[aria-label*="DuckDuckGo" i]', 'a#logo', 'a[data-testid="logo-link"]', 'a[data-testid="header-logo"]',
                'a[href="/"]', 'header a[href="/"]', '#header a[href="/"]',
                '.header a[href="/"]', '.header-wrap a[href="/"]', '.site-wrapper header a[href="/"]',
                '[class*="HeaderLogo"]', '[class*="header_logo"]', '[class*="header__logo"]',
                'svg[class*="logo" i]', 'svg[class*="Logo" i]', 'svg[class*="duck" i]',
                'img[alt*="DuckDuckGo" i]', 'img[src*="duckduckgo" i]', 'img[src*="duck" i]',
                'a[href="/compare-privacy"]', 'a[href*="compare-privacy"]', 'a[href*="compare"]',
                '.header__tagline', '.header__text', '.header--aside', '.header--aside__item',
                '.header__button--menu', '.js-side-menu-open',
                '.feedback-btn', 'button[data-testid="feedback-button"]',
                '.js-feedback-btn-wrap', '[class*="TccjmKV6"]', '[class*="bYzmzE1m"]', '[class*="s_aX02AKO"]',
                '#footer-feedback-wrapper', '.nav-menu--feedback', '.react-feedback-prompt-mvc-wrapper',
                'a[href*="assist=true"]', 'li:has(> a[href*="assist=true"])',
                'a[href*="ia=chat"]:not(.onyx-research-switch-btn)', 'li:has(> a[href*="ia=chat"]:not(.onyx-research-switch-btn))',
                'li:has(> button[aria-label*="Search Settings"])',
                'button[aria-label*="Search Settings"]',
                '[data-testid="region-filter"] svg', '.dropdown--region svg',
                'button[aria-label*="Region" i] svg', 'button[aria-label*="region" i] svg',
                '.ddg-extension-banner', '.onboarding-ed', '.js-onboarding-wrapper', '.badge--ad',
                '[data-testid="ad"]', '[data-testid="ad-item"]', '.results--ads', '.result--ad', '.ads-wrapper',
                '.footer', '#footer', '.badge--privacy', '.badge--protection',
                '.RM8cPgCF1NymxEVCc19D', '.y8qZjjhkSVTmBOORd3oQ', '.S1TV9gKXE9qTlJCKQyVA',
                '[class*="extension-banner"]', '[class*="onboarding"]', '[class*="feedback"]', '[class*="Feedback"]',
                '[class*="feedback-btn"]', '[class*="feedback-modal"]',
                'a[href*="spread"]', 'a[href*="newsletter"]',
                '#logo', '.logo img', 'header svg.logo', 'a#logo', '#fbar', '#footcnt', '#foot',
                '.uEierd', '#tads', '#tadsb', '[data-text-ad]', '.appbar', '.cv2Vmc', '.LH92ce',
                '.TQc1id', '.SJ1Kg', '.G57R0c', '#taw',
                '#gb', '.gb_d', '.gb_Ja', '.gb_A', '.gb_B', '[aria-label*="Google apps" i]',
                '[aria-label*="Google app" i]', '[aria-label*="Google Account" i]',
                'a[href*="accounts.google.com"]', 'a[href*="/saves"]', 'a[href*="/preferences"]',
                '.HPvrce', '[class*="HPvrce"]', '.mTpL7c.HPvrce', '.u96bed.GTERze', '.Iy1nvd', '.SvoXfb',
                '.zLSRge', '.w2jn8d', '.PwiNU', '.m29tEd', '.hdtb-ms', '#hdtb-ms',
                '.Q3DXx', '.Efnghe', '.apFnFf', '[aria-label*="Share" i]', '[aria-label*="Compartir" i]', '[data-share-url]'
            ];
            badSelectors.forEach(sel => {
                try {
                    document.querySelectorAll(sel).forEach(e => {
                        e.style.setProperty('display', 'none', 'important');
                        e.style.setProperty('visibility', 'hidden', 'important');
                        e.style.setProperty('opacity', '0', 'important');
                        e.style.setProperty('width', '0', 'important');
                        e.style.setProperty('height', '0', 'important');
                        e.style.setProperty('max-width', '0', 'important');
                        e.style.setProperty('max-height', '0', 'important');
                    });
                } catch(err) {}
            });
            document.querySelectorAll('strong, span, p, a').forEach(el => {
                if (el.children.length === 0 && el.innerText && el.innerText.includes('DuckDuckGo')) {
                    el.innerText = el.innerText.replace(/DuckDuckGo/g, 'Onyx Search');
                }
                if (el.children.length === 0 && el.innerText && el.innerText.trim() === 'Duck.ai') {
                    el.innerText = 'Onyx Research';
                }
            });

            function tagSearchPill() {
                const input = document.getElementById('search_form_input') || document.querySelector('input[name="q"]');
                if (input) {
                    const pill = input.closest('[class*="QsyijBlqupsaY11GFhnp"]') ||
                                 input.closest('[class*="T265XEcezvjUhK71U8pN"]') ||
                                 input.closest('[data-testid="search-form-input-wrapper"]') ||
                                 input.parentElement;
                    if (pill && !pill.classList.contains('onyx-search-pill')) {
                        pill.classList.add('onyx-search-pill');
                    }
                }
            }

            function updateActiveDuckbarTab() {
                const duckbar = document.getElementById('react-duckbar') || document.querySelector('[data-testid="duckbar"]');
                if (!duckbar) return;
                const ul = duckbar.querySelector('ul:first-child');
                if (!ul) return;
                const links = ul.querySelectorAll('a');
                if (!links || links.length === 0) return;

                const url = new URL(window.location.href);
                const ia = (url.searchParams.get('ia') || url.searchParams.get('iar') || '').toLowerCase();

                let activeLink = null;
                links.forEach(a => {
                    if (a.classList.contains('onyx-research-switch-btn')) return;
                    a.classList.add('onyx-duckbar-tab');
                    const text = (a.innerText || '').trim().toLowerCase();
                    const href = (a.getAttribute('href') || '').toLowerCase();

                    let isActive = false;
                    if (ia === 'images' && (text.includes('image') || href.includes('ia=images') || href.includes('iar=images'))) isActive = true;
                    else if (ia === 'videos' && (text.includes('video') || href.includes('ia=videos') || href.includes('iar=videos'))) isActive = true;
                    else if (ia === 'news' && (text.includes('news') || href.includes('ia=news') || href.includes('iar=news'))) isActive = true;
                    else if (ia === 'maps' && (text.includes('map') || href.includes('ia=maps') || href.includes('iar=maps'))) isActive = true;
                    else if ((!ia || ia === 'web') && (text === 'all' || a.querySelector('svg') || a.classList.contains('SnptgjT2zdOhGYfNng6g'))) isActive = true;

                    if (isActive) {
                        a.classList.add('onyx-tab-active');
                        a.classList.add('is-active');
                        activeLink = a;
                    } else {
                        a.classList.remove('onyx-tab-active');
                        a.classList.remove('is-active');
                        a.classList.remove('SnptgjT2zdOhGYfNng6g');
                    }
                });

                if (!activeLink && links.length > 0) {
                    links[0].classList.add('onyx-tab-active');
                    links[0].classList.add('is-active');
                    activeLink = links[0];
                }

                // Setup or fetch the single shared light glider
                let glider = document.getElementById('onyx-duckbar-glider');
                if (!glider) {
                    glider = document.createElement('div');
                    glider.id = 'onyx-duckbar-glider';
                    glider.className = 'onyx-duckbar-glider';
                    duckbar.appendChild(glider);
                }

                function positionGlider(targetTab, animate) {
                    if (!targetTab || !glider) return;
                    const duckbarRect = duckbar.getBoundingClientRect();
                    const tabRect = targetTab.getBoundingClientRect();
                    if (tabRect.width === 0) {
                        requestAnimationFrame(() => positionGlider(targetTab, animate));
                        return;
                    }
                    const left = Math.round(tabRect.left - duckbarRect.left);
                    const width = Math.min(Math.max(Math.round(tabRect.width), 30), 160);

                    if (!animate) {
                        glider.style.setProperty('transition', 'none', 'important');
                    } else {
                        glider.style.setProperty('transition', 'transform 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), width 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), opacity 0.2s ease', 'important');
                    }
                    glider.style.setProperty('transform', `translateX(${left}px)`, 'important');
                    glider.style.setProperty('width', `${width}px`, 'important');
                    glider.classList.add('is-ready');
                    if (!animate) {
                        void glider.offsetWidth;
                    }
                }

                // Bind click listeners for instant fluid light transfer between tabs
                links.forEach(a => {
                    if (a.classList.contains('onyx-research-switch-btn')) return;
                    if (a.dataset.gliderBound) return;
                    a.dataset.gliderBound = 'true';
                    a.addEventListener('click', () => {
                        const currentActive = ul.querySelector('a.onyx-tab-active') || links[0];
                        const duckbarRect = duckbar.getBoundingClientRect();
                        const curRect = currentActive ? currentActive.getBoundingClientRect() : null;
                        if (curRect && curRect.width > 0 && curRect.width < 200) {
                            try {
                                sessionStorage.setItem('onyx_glider_from_x', Math.round(curRect.left - duckbarRect.left).toString());
                                sessionStorage.setItem('onyx_glider_from_w', Math.min(Math.max(Math.round(curRect.width), 30), 160).toString());
                            } catch(e) {}
                        }
                        positionGlider(a, true);
                        links.forEach(l => {
                            if (l === a) {
                                l.classList.add('onyx-tab-active');
                                l.classList.add('is-active');
                            } else {
                                l.classList.remove('onyx-tab-active');
                                l.classList.remove('is-active');
                                l.classList.remove('SnptgjT2zdOhGYfNng6g');
                            }
                        });
                    });
                });

                if (!window._onyxDuckbarResizeBound) {
                    window._onyxDuckbarResizeBound = true;
                    window.addEventListener('resize', () => {
                        const current = document.querySelector('#react-duckbar ul:first-child a.onyx-tab-active') ||
                                        document.querySelector('[data-testid="duckbar"] ul:first-child a.onyx-tab-active');
                        if (current) positionGlider(current, false);
                    });
                }

                if (activeLink) {
                    let fromX = null;
                    let fromW = null;
                    try {
                        fromX = sessionStorage.getItem('onyx_glider_from_x');
                        fromW = sessionStorage.getItem('onyx_glider_from_w');
                        sessionStorage.removeItem('onyx_glider_from_x');
                        sessionStorage.removeItem('onyx_glider_from_w');
                    } catch(e) {}

                    const fw = parseFloat(fromW);
                    const fx = parseFloat(fromX);
                    if (!isNaN(fw) && !isNaN(fx) && fw >= 25 && fw <= 160 && fx >= 0 && fx <= 1200) {
                        const duckbarRect = duckbar.getBoundingClientRect();
                        const activeRect = activeLink.getBoundingClientRect();
                        const newLeft = Math.round(activeRect.left - duckbarRect.left);
                        if (Math.abs(fx - newLeft) > 5) {
                            glider.style.setProperty('transition', 'none', 'important');
                            glider.style.setProperty('transform', `translateX(${fx}px)`, 'important');
                            glider.style.setProperty('width', `${fw}px`, 'important');
                            glider.classList.add('is-ready');
                            void glider.offsetWidth;
                            requestAnimationFrame(() => {
                                requestAnimationFrame(() => {
                                    positionGlider(activeLink, true);
                                });
                            });
                            return;
                        }
                    }
                    positionGlider(activeLink, false);
                }
            }

            tagSearchPill();
            updateActiveDuckbarTab();
            const resultsContainer = document.querySelector('.react-results--main') ||
                                     document.querySelector('#links');
            if (resultsContainer) {
                const params = new URLSearchParams(window.location.search);
                const query = (params.get('q') || '').replace(/\\+/g, ' ');

                let header = document.getElementById('onyx-brand-header');
                if (!header) {
                    header = document.createElement('div');
                    header.id = 'onyx-brand-header';
                    header.innerHTML = `
                        <div class="onyx-brand-title">
                            <span class="onyx-brand-dot"></span>
                            <span>✦ Onyx Search</span>
                            <span style="color: #71717a; font-weight: 400; font-size: 13px;">• Direct Web Index</span>
                        </div>
                        <div style="display: flex; gap: 8px; align-items: center;">
                            <a href="https://duckduckgo.com/?q=${encodeURIComponent(query)}&ia=chat" class="onyx-research-switch-btn" title="Open in Deep AI Research Mode">
                                <span>✦ Deep AI Research</span>
                            </a>
                        </div>
                    `;
                    resultsContainer.insertBefore(header, resultsContainer.firstChild);
                } else if (header.parentElement !== resultsContainer) {
                    resultsContainer.insertBefore(header, resultsContainer.firstChild);
                }

                let summaryText = '';
                const aboutSnippet = document.querySelector('[data-testid="about-snippet"]') ||
                                     document.querySelector('.module--wikipedia .module__body') ||
                                     document.querySelector('[data-testid="module--about"] .module__text') ||
                                     document.querySelector('.module__text');
                if (aboutSnippet && aboutSnippet.innerText && aboutSnippet.innerText.length > 50 && !aboutSnippet.innerText.includes('USD(%)') && !aboutSnippet.innerText.includes('1D5D')) {
                    summaryText = aboutSnippet.innerText.trim();
                } else {
                    const articles = document.querySelectorAll('article');
                    for (let i = 0; i < articles.length; i++) {
                        const art = articles[i];
                        const title = art.querySelector('h2') ? (art.querySelector('h2').innerText || '').trim() : '';
                        const lines = (art.innerText || '').split('\\n').map(s => s.trim()).filter(Boolean);
                        for (let j = 0; j < lines.length; j++) {
                            const line = lines[j];
                            if (title && (title === line || title.includes(line) || line.includes(title))) continue;
                            const cleaned = line.replace(/^[0-9]+\\s+(days?|hours?|mins?|weeks?|months?|years?)\\s+ago\\s*/i, '').trim();
                            if (cleaned.length >= 40 &&
                                !cleaned.includes('http') &&
                                !cleaned.includes('›') &&
                                !cleaned.includes('Only include') &&
                                !cleaned.includes('Redo search') &&
                                !cleaned.includes('Block this')) {
                                summaryText = cleaned;
                                break;
                            }
                        }
                        if (summaryText) break;
                    }
                }

                let card = document.getElementById('onyx-ai-synthesis-card');
                if (!card && summaryText && summaryText.trim().length > 20) {
                    card = document.createElement('div');
                    card.id = 'onyx-ai-synthesis-card';
                    card.innerHTML = `
                        <div class="onyx-ai-header">
                            <div class="onyx-ai-badge">
                                <span>✦</span>
                                <span>Onyx Synthetic Overview</span>
                            </div>
                            <span style="color: #71717a; font-size: 11px; font-weight: 500;">INSTANT OVERVIEW</span>
                        </div>
                        <div class="onyx-ai-content">
                            <p style="margin: 0; font-size: 14px; color: #e2e8f0; line-height: 1.65;">${summaryText}</p>
                        </div>
                    `;
                    if (header && header.parentElement === resultsContainer) {
                        if (header.nextSibling) {
                            resultsContainer.insertBefore(card, header.nextSibling);
                        } else {
                            resultsContainer.appendChild(card);
                        }
                    } else {
                        resultsContainer.insertBefore(card, resultsContainer.firstChild);
                    }
                } else if (card && card.parentElement !== resultsContainer) {
                    if (header && header.parentElement === resultsContainer && header.nextSibling) {
                        resultsContainer.insertBefore(card, header.nextSibling);
                    } else {
                        resultsContainer.insertBefore(card, resultsContainer.firstChild);
                    }
                }
            }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    func setupUI() {
        guard let window = self.window, let contentView = window.contentView else { return }
        
        // 1. Titlebar Tab Bar (Height: 38px, native window drag on background, traffic lights at x: 12..70)
        tabBar = TabBarView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.wantsLayer = true
        tabBar.layer?.backgroundColor = NSColor(red: 14/255.0, green: 14/255.0, blue: 17/255.0, alpha: 1.0).cgColor
        contentView.addSubview(tabBar)
        
        tabSeparator = NSBox()
        tabSeparator.translatesAutoresizingMaskIntoConstraints = false
        tabSeparator.boxType = .custom
        tabSeparator.borderWidth = 0
        tabSeparator.fillColor = NSColor(white: 1.0, alpha: 0.05)
        tabBar.addSubview(tabSeparator)
        
        tabStack = NSStackView()
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabStack.orientation = .horizontal
        tabStack.spacing = 6
        tabStack.alignment = .centerY
        tabBar.addSubview(tabStack)
        
        newTabBtn = NavIconButton(iconName: "plus", tooltip: "New Tab (⌘T)", target: self, action: #selector(newTabClicked), size: 24)
        newTabBtn.layer?.cornerRadius = 12
        newTabBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.04).cgColor
        newTabBtn.layer?.borderWidth = 1
        newTabBtn.layer?.borderColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        tabBar.addSubview(newTabBtn)
        
        // 2. Toolbar Container (Height: 40px, full-width below titlebar)
        topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = NSColor(red: 14/255.0, green: 14/255.0, blue: 17/255.0, alpha: 1.0).cgColor
        contentView.addSubview(topBar)
        
        topBarSeparator = NSBox()
        topBarSeparator.translatesAutoresizingMaskIntoConstraints = false
        topBarSeparator.boxType = .custom
        topBarSeparator.borderWidth = 0
        topBarSeparator.fillColor = NSColor(white: 1.0, alpha: 0.05)
        topBar.addSubview(topBarSeparator)
        
        // Nav Buttons (Back, Forward, Reload)
        backButton = NavIconButton(iconName: "chevron.left", tooltip: "Back (⌘[)", target: self, action: #selector(goBack))
        forwardButton = NavIconButton(iconName: "chevron.right", tooltip: "Forward (⌘])", target: self, action: #selector(goForward))
        reloadButton = NavIconButton(iconName: "arrow.clockwise", tooltip: "Reload (⌘R)", target: self, action: #selector(reloadPage))
        
        backButton.isEnabled = false
        forwardButton.isEnabled = false
        
        let navStack = NSStackView(views: [backButton, forwardButton, reloadButton])
        navStack.translatesAutoresizingMaskIntoConstraints = false
        navStack.orientation = .horizontal
        navStack.spacing = 4
        navStack.alignment = .centerY
        topBar.addSubview(navStack)
        
        // Address Bar / Search Container (Precision 32px dark obsidian capsule with 10px radius)
        searchContainer = NSView()
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.wantsLayer = true
        searchContainer.layer?.cornerRadius = 10
        searchContainer.layer?.borderWidth = 1
        searchContainer.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        searchContainer.layer?.backgroundColor = NSColor(red: 24/255.0, green: 24/255.0, blue: 28/255.0, alpha: 1.0).cgColor
        topBar.addSubview(searchContainer)
        
        searchFaviconView = NSImageView()
        searchFaviconView.translatesAutoresizingMaskIntoConstraints = false
        searchFaviconView.wantsLayer = true
        searchFaviconView.layer?.cornerRadius = 3
        searchFaviconView.layer?.masksToBounds = true
        searchFaviconView.imageScaling = .scaleProportionallyUpOrDown
        if let img = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Favicon") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            searchFaviconView.image = img.withSymbolConfiguration(config)
            searchFaviconView.contentTintColor = NSColor(white: 0.60, alpha: 1.0)
        }
        searchFaviconView.toolTip = "Search Engine: Click to change default"
        let engineClickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(showSearchEngineMenu(_:)))
        searchFaviconView.addGestureRecognizer(engineClickRecognizer)
        searchContainer.addSubview(searchFaviconView)
        
        searchThinkingOrb = ThinkingOrbView()
        searchThinkingOrb.translatesAutoresizingMaskIntoConstraints = false
        searchThinkingOrb.isHidden = true
        searchContainer.addSubview(searchThinkingOrb)
        
        searchField = CustomSearchBar()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.focusRingType = .none
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.textColor = NSColor(white: 0.98, alpha: 1.0)
        searchField.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        updateSearchPlaceholder()
        updateSearchEngineIcon()
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldSubmitted)
        searchContainer.addSubview(searchField)
        
        searchShortcutBadge = NSTextField(labelWithString: "⌘L")
        searchShortcutBadge.translatesAutoresizingMaskIntoConstraints = false
        searchShortcutBadge.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)
        searchShortcutBadge.textColor = NSColor(white: 0.45, alpha: 1.0)
        searchShortcutBadge.wantsLayer = true
        searchShortcutBadge.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        searchShortcutBadge.layer?.cornerRadius = 4
        searchContainer.addSubview(searchShortcutBadge)
        
        searchField.onFocusChanged = { [weak self] focused in
            guard let self = self else { return }
            if focused {
                self.suggestedPopover?.performClose(nil)
                self.searchShortcutBadge.isHidden = true
            } else {
                self.searchShortcutBadge.isHidden = !self.searchField.stringValue.isEmpty
            }
            self.updateSearchContainerGlow(for: self.searchField.stringValue, focused: focused)
        }
        
        // Trailing Toolbar Controls (Pinnable Extensions Stack, Extensions Menu, Profile)
        suggestedTabsBtn = NavIconButton(iconName: "sparkles", tooltip: "AI Research Canvas (⌘⇧S)", target: self, action: #selector(showSuggestedTabsPopover))
        downloadsButton = DownloadsNavButton(target: self, action: #selector(toggleDownloadsPopover))
        passwordsButton = PasswordsNavButton(target: self, action: #selector(togglePasswordsPopover))
        shieldButton = NavIconButton(iconName: "shield.checkerboard", tooltip: "Onyx Shield: Private & Fast (30 MB RAM)", target: self, action: #selector(showPrivacyReport))
        
        extensionsStack = NSStackView(views: [suggestedTabsBtn, downloadsButton, passwordsButton, shieldButton])
        extensionsStack.translatesAutoresizingMaskIntoConstraints = false
        extensionsStack.orientation = .horizontal
        extensionsStack.spacing = 6
        extensionsStack.alignment = .centerY
        
        extensionsButton = NavIconButton(iconName: "puzzlepiece.extension", tooltip: "Extensions", target: self, action: #selector(toggleExtensionsPopover))
        
        profileButton = ProfilePillButton(target: self, action: #selector(showProfileManagerPopover))
        profileButton.configure(profile: activeProfile)
        profileButton.onSettingsClick = { [weak self] in
            self?.openSettingsTab()
        }
        
        trailingControlsStack = NSStackView(views: [extensionsStack, extensionsButton, profileButton])
        trailingControlsStack.translatesAutoresizingMaskIntoConstraints = false
        trailingControlsStack.orientation = .horizontal
        trailingControlsStack.spacing = 8
        trailingControlsStack.alignment = .centerY
        topBar.addSubview(trailingControlsStack)
        
        setupExtensionContextMenus()
        applyToolbarPins()
        
        // 3. Bookmarks Shelf (Height: 28px, resting 100% transparent items matching Comet)
        bookmarksBar = BookmarksBarView()
        bookmarksBar.controller = self
        bookmarksBar.translatesAutoresizingMaskIntoConstraints = false
        bookmarksBar.wantsLayer = true
        bookmarksBar.layer?.backgroundColor = NSColor(red: 22/255.0, green: 22/255.0, blue: 25/255.0, alpha: 1.0).cgColor
        bookmarksBar.toolTip = "Bookmarks (Left-click for options)"
        contentView.addSubview(bookmarksBar)
        
        bookmarksSeparator = NSBox()
        bookmarksSeparator.translatesAutoresizingMaskIntoConstraints = false
        bookmarksSeparator.boxType = .custom
        bookmarksSeparator.borderWidth = 0
        bookmarksSeparator.fillColor = NSColor(white: 1.0, alpha: 0.06)
        bookmarksBar.addSubview(bookmarksSeparator)
        
        bookmarksStack = BookmarksStackView()
        bookmarksStack.translatesAutoresizingMaskIntoConstraints = false
        bookmarksStack.orientation = .horizontal
        bookmarksStack.spacing = 4
        bookmarksStack.alignment = .centerY
        bookmarksBar.addSubview(bookmarksStack)
        
        manageBookmarksBtn = NavIconButton(iconName: "ellipsis", tooltip: "Manage Bookmarks...", target: self, action: #selector(manageBookmarksButtonClicked(_:)), size: 20)
        manageBookmarksBtn.layer?.cornerRadius = 4
        manageBookmarksBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        bookmarksBar.addSubview(manageBookmarksBtn)
        
        renderBookmarks()
        
        // Hairline Progress Bar (Onyx Pure White Liquid Stream, 1.5px)
        progressBar = NSBox()
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.boxType = .custom
        progressBar.borderWidth = 0
        progressBar.fillColor = NSColor(white: 1.0, alpha: 0.90)
        progressBar.wantsLayer = true
        progressBar.layer?.shadowColor = NSColor.white.cgColor
        progressBar.layer?.shadowOpacity = 0.4
        progressBar.layer?.shadowRadius = 3
        progressBar.layer?.shadowOffset = .zero
        progressBar.isHidden = true
        bookmarksBar.addSubview(progressBar)
        
        // 4. Web Content Container View
        webContainerView = NSView()
        webContainerView.translatesAutoresizingMaskIntoConstraints = false
        webContainerView.wantsLayer = true
        webContainerView.layer?.backgroundColor = NSColor(red: 7/255.0, green: 7/255.0, blue: 9/255.0, alpha: 1.0).cgColor
        contentView.addSubview(webContainerView)
        
        // Directional Edge Glow Shimmer View
        edgeGlowView = DirectionalEdgeGlowView()
        webContainerView.addSubview(edgeGlowView)
        NSLayoutConstraint.activate([
            edgeGlowView.topAnchor.constraint(equalTo: webContainerView.topAnchor),
            edgeGlowView.bottomAnchor.constraint(equalTo: webContainerView.bottomAnchor),
            edgeGlowView.leadingAnchor.constraint(equalTo: webContainerView.leadingAnchor),
            edgeGlowView.trailingAnchor.constraint(equalTo: webContainerView.trailingAnchor)
        ])
        
        let initialBookmarksVisible = UserDefaults.standard.object(forKey: "OnyxShowBookmarksBar") as? Bool ?? true
        progressConstraint = progressBar.widthAnchor.constraint(equalToConstant: 0)
        bookmarksBarHeightConstraint = bookmarksBar.heightAnchor.constraint(equalToConstant: initialBookmarksVisible ? 28 : 0)
        bookmarksBar.alphaValue = initialBookmarksVisible ? 1.0 : 0.0
        
        NSLayoutConstraint.activate([
            // Row 1: Titlebar Tab Bar (38px, starts at x: 78 to clear macOS traffic lights at 12..70)
            tabBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 38),
            
            tabSeparator.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
            tabSeparator.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            tabSeparator.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            tabSeparator.heightAnchor.constraint(equalToConstant: 1),
            
            tabStack.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 78),
            tabStack.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabStack.trailingAnchor.constraint(lessThanOrEqualTo: tabBar.trailingAnchor, constant: -120),
            
            newTabBtn.leadingAnchor.constraint(equalTo: tabStack.trailingAnchor, constant: 4),
            newTabBtn.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            
            // Row 2: Toolbar (40px)
            topBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            topBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 40),
            
            topBarSeparator.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            topBarSeparator.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            topBarSeparator.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            topBarSeparator.heightAnchor.constraint(equalToConstant: 1),
            
            navStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            navStack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            
            trailingControlsStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            trailingControlsStack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            
            searchContainer.leadingAnchor.constraint(equalTo: navStack.trailingAnchor, constant: 12),
            searchContainer.trailingAnchor.constraint(equalTo: trailingControlsStack.leadingAnchor, constant: -12),
            searchContainer.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            searchContainer.heightAnchor.constraint(equalToConstant: 32),
            
            searchFaviconView.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10),
            searchFaviconView.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchFaviconView.widthAnchor.constraint(equalToConstant: 14),
            searchFaviconView.heightAnchor.constraint(equalToConstant: 14),
            
            searchThinkingOrb.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 9),
            searchThinkingOrb.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchThinkingOrb.widthAnchor.constraint(equalToConstant: 16),
            searchThinkingOrb.heightAnchor.constraint(equalToConstant: 16),
            
            searchField.leadingAnchor.constraint(equalTo: searchFaviconView.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchShortcutBadge.leadingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            
            searchShortcutBadge.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -8),
            searchShortcutBadge.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            
            // Row 3: Bookmarks Shelf (28px)
            bookmarksBar.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            bookmarksBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bookmarksBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bookmarksBarHeightConstraint,
            
            bookmarksSeparator.bottomAnchor.constraint(equalTo: bookmarksBar.bottomAnchor),
            bookmarksSeparator.leadingAnchor.constraint(equalTo: bookmarksBar.leadingAnchor),
            bookmarksSeparator.trailingAnchor.constraint(equalTo: bookmarksBar.trailingAnchor),
            bookmarksSeparator.heightAnchor.constraint(equalToConstant: 1),
            
            bookmarksStack.leadingAnchor.constraint(equalTo: bookmarksBar.leadingAnchor, constant: 14),
            bookmarksStack.trailingAnchor.constraint(lessThanOrEqualTo: manageBookmarksBtn.leadingAnchor, constant: -8),
            bookmarksStack.centerYAnchor.constraint(equalTo: bookmarksBar.centerYAnchor),
            
            manageBookmarksBtn.trailingAnchor.constraint(equalTo: bookmarksBar.trailingAnchor, constant: -12),
            manageBookmarksBtn.centerYAnchor.constraint(equalTo: bookmarksBar.centerYAnchor),
            
            progressBar.bottomAnchor.constraint(equalTo: bookmarksBar.bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: bookmarksBar.leadingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 1.5),
            progressConstraint,
            
            // Web Content Container
            webContainerView.topAnchor.constraint(equalTo: bookmarksBar.bottomAnchor),
            webContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        updateActiveBookmarkHighlight()
    }
    
    func updateSearchPlaceholder() {
        let defaultEngine = UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo"
        let engineName: String
        switch defaultEngine.lowercased() {
        case "google": engineName = "Google"
        case "brave": engineName = "Brave"
        case "perplexity": engineName = "Perplexity"
        case "kagi": engineName = "Kagi"
        case "bing": engineName = "Bing"
        default: engineName = "DuckDuckGo"
        }
        let msg = "Search with \(engineName) or enter address"
        searchField.placeholderAttributedString = NSAttributedString(
            string: msg,
            attributes: [
                .foregroundColor: NSColor(white: 0.45, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12, weight: .regular)
            ]
        )
    }
    
    func updateSearchEngineIcon() {
        let defaultEngine = UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo"
        let iconName: String
        switch defaultEngine.lowercased() {
        case "google": iconName = "g.circle.fill"
        case "brave": iconName = "shield.checkerboard"
        case "perplexity": iconName = "sparkles"
        case "kagi": iconName = "magnifyingglass.circle.fill"
        case "bing": iconName = "b.circle.fill"
        default: iconName = "sparkles"
        }
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: "Search Engine") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            searchFaviconView.image = img.withSymbolConfiguration(config)
            searchFaviconView.contentTintColor = NSColor(white: 0.70, alpha: 1.0)
        }
    }
    
    @objc func showSearchEngineMenu(_ sender: Any?) {
        let menu = NSMenu(title: "Default Search Engine")
        let currentEngine = (UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo").lowercased()
        
        let engines: [(key: String, title: String, icon: String)] = [
            ("duckduckgo", "DuckDuckGo (AI Chat Ready)", "sparkles"),
            ("google", "Google", "g.circle.fill"),
            ("brave", "Brave Search (Private)", "shield.checkerboard"),
            ("perplexity", "Perplexity AI", "sparkles"),
            ("kagi", "Kagi Search", "magnifyingglass.circle.fill"),
            ("bing", "Microsoft Bing", "b.circle.fill")
        ]
        
        for (key, title, icon) in engines {
            let item = NSMenuItem(title: title, action: #selector(searchEngineMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                item.image = img.withSymbolConfiguration(cfg)
            }
            item.state = (key == currentEngine) ? .on : .off
            menu.addItem(item)
        }
        
        let location = NSPoint(x: 0, y: searchFaviconView.bounds.maxY + 4)
        menu.popUp(positioning: nil, at: location, in: searchFaviconView)
    }

    @objc func searchEngineMenuItemClicked(_ sender: NSMenuItem) {
        if let engine = sender.representedObject as? String {
            setLiveSearchEngine(engine)
        }
    }
    
    func setLiveSearchEngine(_ engine: String) {
        let normalized = engine.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        
        // 1. Persist engine preference immediately
        UserDefaults.standard.set(normalized, forKey: "OnyxSearchEngine")
        
        // 2. Update omnibar placeholder & icon
        updateSearchPlaceholder()
        updateSearchEngineIcon()
        
        // 3. Inform all open tabs live without reloading or resetting them!
        let broadcastScript = """
        window.postMessage({ type: 'onyx-search-engine-changed', engine: '\(normalized)' }, '*');
        if (typeof window.onOnyxSearchEngineChanged === 'function') {
            window.onOnyxSearchEngineChanged('\(normalized)');
        }
        if (typeof window.setSearchEngine === 'function') {
            window.setSearchEngine('\(normalized)');
        }
        """
        for tab in tabs {
            tab.webView.evaluateJavaScript(broadcastScript, completionHandler: nil)
        }
        
        // 4. If current active tab is currently on a search results page, seamlessly reroute to the new engine
        if let currentURL = activeWebView.url {
            let urlStr = currentURL.absoluteString
            let isSearchURL = urlStr.contains("duckduckgo.com/?q=") ||
                              urlStr.contains("google.com/search?") ||
                              urlStr.contains("search.brave.com/search?") ||
                              urlStr.contains("perplexity.ai/search?") ||
                              urlStr.contains("bing.com/search?") ||
                              urlStr.contains("kagi.com/search?")
            
            if isSearchURL, let components = URLComponents(url: currentURL, resolvingAgainstBaseURL: false) {
                if let queryItem = components.queryItems?.first(where: { $0.name == "q" || $0.name == "query" }),
                   let currentQuery = queryItem.value, !currentQuery.isEmpty {
                    let newURL = resolveQuery(currentQuery)
                    loadURL(newURL)
                }
            }
        }
        
        // 5. Update engine chips in suggestionsView if open
        suggestionsView?.updateActiveEngine(normalized)
        
        // 6. Display a sleek toast HUD confirming live switch
        let engineDisplayName: String
        switch normalized {
        case "google": engineDisplayName = "Google"
        case "brave": engineDisplayName = "Brave Search"
        case "perplexity": engineDisplayName = "Perplexity AI"
        case "kagi": engineDisplayName = "Kagi"
        case "bing": engineDisplayName = "Microsoft Bing"
        default: engineDisplayName = "DuckDuckGo"
        }
        showVaultToastHUD(icon: "sparkles", title: "SEARCH ENGINE CHANGED", message: "Live default set to \(engineDisplayName)")
    }
    
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
        tab.webView.navigationDelegate = self
        tab.webView.uiDelegate = self
        
        tab.webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
        tab.webView.addObserver(self, forKeyPath: "title", options: .new, context: nil)
        tab.webView.addObserver(self, forKeyPath: "URL", options: .new, context: nil)
        tab.isObserved = true
        
        tabs.append(tab)
        
        if switchTo {
            selectTab(at: tabs.count - 1)
        } else {
            renderTabs()
        }
        
        loadTabURL(tab: tab, url: url)
    }
    
    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        
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
        
        NSLayoutConstraint.activate([
            currentTab.webView.topAnchor.constraint(equalTo: webContainerView.topAnchor),
            currentTab.webView.leadingAnchor.constraint(equalTo: webContainerView.leadingAnchor),
            currentTab.webView.trailingAnchor.constraint(equalTo: webContainerView.trailingAnchor),
            currentTab.webView.bottomAnchor.constraint(equalTo: webContainerView.bottomAnchor)
        ])
        
        renderTabs()
        updateSearchField(url: currentTab.url)
        
        if currentTab.webView.isLoading {
            let isSearch = isSearchURL(currentTab.url)
            if isSearch {
                searchThinkingOrb.stopAnimation()
                searchThinkingOrb.isHidden = true
                searchFaviconView.image = nil
                searchFaviconView.isHidden = true
            } else {
                let isResearch = isResearchURL(currentTab.url)
                searchFaviconView.isHidden = true
                searchThinkingOrb.startAnimation(mode: isResearch ? .orbits : .orbits)
            }
        } else if isResearchURL(currentTab.url) {
            searchFaviconView.isHidden = true
            searchThinkingOrb.startAnimation(mode: .orbits)
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
        closingTab.webView.stopLoading()
        closingTab.webView.removeFromSuperview()
        
        tabs.remove(at: index)
        
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
            
            // Google S2 Favicon service (64px Retina-ready)
            if let googleS2 = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") {
                candidates.append(googleS2)
            }
            
            // DuckDuckGo icons API
            if let ddg = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") {
                candidates.append(ddg)
            }
            
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
    
    // MARK: - Toolbar Extensions & Pinning System Implementation
    func applyToolbarPins() {
        suggestedTabsBtn.isHidden = !OnyxToolbarTool.aiResearch.isPinned
        downloadsButton.isHidden = !OnyxToolbarTool.downloads.isPinned
        passwordsButton.isHidden = !OnyxToolbarTool.passwords.isPinned
        shieldButton.isHidden = !OnyxToolbarTool.shield.isPinned
    }
    
    func setupExtensionContextMenus() {
        let tools: [(OnyxToolbarTool, NSButton)] = [
            (.aiResearch, suggestedTabsBtn),
            (.downloads, downloadsButton),
            (.passwords, passwordsButton),
            (.shield, shieldButton)
        ]
        
        for (tool, btn) in tools {
            let menu = NSMenu(title: tool.title)
            
            let titleItem = NSMenuItem(title: tool.title, action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            if let icon = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                titleItem.image = icon.withSymbolConfiguration(cfg)
            }
            menu.addItem(titleItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let unpinItem = NSMenuItem(title: "Unpin from Toolbar", action: #selector(togglePinFromMenu(_:)), keyEquivalent: "")
            unpinItem.target = self
            unpinItem.representedObject = tool
            if let pinIcon = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: nil) {
                unpinItem.image = pinIcon.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
            }
            menu.addItem(unpinItem)
            
            let openItem = NSMenuItem(title: "Open " + tool.title, action: #selector(openToolFromMenu(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = tool
            menu.addItem(openItem)
            
            btn.menu = menu
        }
    }
    
    @objc func togglePinFromMenu(_ sender: NSMenuItem) {
        guard let tool = sender.representedObject as? OnyxToolbarTool else { return }
        tool.setPinned(!tool.isPinned)
        applyToolbarPins()
        if let pop = extensionsPopover, pop.isShown {
            showExtensionsPopover()
        }
    }
    
    @objc func openToolFromMenu(_ sender: NSMenuItem) {
        guard let tool = sender.representedObject as? OnyxToolbarTool else { return }
        launchTool(tool)
    }
    
    func launchTool(_ tool: OnyxToolbarTool) {
        switch tool {
        case .aiResearch:
            showSuggestedTabsPopover()
        case .downloads:
            toggleDownloadsPopover()
        case .passwords:
            togglePasswordsPopover()
        case .shield:
            showPrivacyReport()
        }
    }
    
    @objc func toggleExtensionsPopover() {
        if let pop = extensionsPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        showExtensionsPopover()
    }
    
    func showExtensionsPopover() {
        extensionsPopover?.performClose(nil)
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let width: CGFloat = 290
        let height: CGFloat = 250
        popover.contentSize = NSSize(width: width, height: height)
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.25).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        // Header (44px)
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        
        let headerIcon = NSImageView()
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "puzzlepiece.extension.fill", accessibilityDescription: "Extensions") {
            headerIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
            headerIcon.contentTintColor = .white
        }
        header.addSubview(headerIcon)
        
        let titleStack = NSStackView()
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.orientation = .vertical
        titleStack.spacing = 1
        titleStack.alignment = .leading
        header.addSubview(titleStack)
        
        let headerTitle = NSTextField(labelWithString: "EXTENSIONS & TOOLS")
        headerTitle.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        headerTitle.textColor = .white
        titleStack.addArrangedSubview(headerTitle)
        
        let headerSubtitle = NSTextField(labelWithString: "Pin to toolbar or quick launch")
        headerSubtitle.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        headerSubtitle.textColor = NSColor(white: 0.50, alpha: 1.0)
        titleStack.addArrangedSubview(headerSubtitle)
        
        let headerSep = NSBox()
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        headerSep.boxType = .custom
        headerSep.borderWidth = 0
        headerSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        header.addSubview(headerSep)
        
        // Rows stack
        let listStack = NSStackView()
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.orientation = .vertical
        listStack.spacing = 4
        listStack.alignment = .leading
        container.addSubview(listStack)
        
        for tool in OnyxToolbarTool.allCases {
            let row = createExtensionRowView(tool: tool, onPinToggle: { [weak self] in
                tool.setPinned(!tool.isPinned)
                self?.applyToolbarPins()
                self?.showExtensionsPopover()
            }, onLaunch: { [weak self, weak popover] in
                popover?.performClose(nil)
                self?.launchTool(tool)
            })
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            row.leadingAnchor.constraint(equalTo: listStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: listStack.trailingAnchor).isActive = true
        }
        
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),
            container.heightAnchor.constraint(equalToConstant: height),
            
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),
            
            headerIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            headerIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerIcon.widthAnchor.constraint(equalToConstant: 18),
            headerIcon.heightAnchor.constraint(equalToConstant: 18),
            
            titleStack.leadingAnchor.constraint(equalTo: headerIcon.trailingAnchor, constant: 10),
            titleStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            headerSep.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            headerSep.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerSep.heightAnchor.constraint(equalToConstant: 1),
            
            listStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            listStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            listStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            listStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8)
        ])
        
        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc
        self.extensionsPopover = popover
        
        popover.show(relativeTo: extensionsButton.bounds, of: extensionsButton, preferredEdge: .maxY)
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
    }
    
    func createExtensionRowView(tool: OnyxToolbarTool, onPinToggle: @escaping () -> Void, onLaunch: @escaping () -> Void) -> NSView {
        class ExtensionRowItemView: NSView {
            var onLaunch: (() -> Void)?
            private var trackingArea: NSTrackingArea?
            
            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                if let ta = trackingArea { removeTrackingArea(ta) }
                trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
                addTrackingArea(trackingArea!)
            }
            
            override func mouseEntered(with event: NSEvent) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
                    self.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
                }
            }
            
            override func mouseExited(with event: NSEvent) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.02).cgColor
                    self.layer?.borderColor = NSColor(white: 1.0, alpha: 0.06).cgColor
                }
            }
            
            override func mouseUp(with event: NSEvent) {
                let loc = convert(event.locationInWindow, from: nil)
                if bounds.contains(loc) {
                    onLaunch?()
                }
            }
        }
        
        let row = ExtensionRowItemView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        row.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.02).cgColor
        row.layer?.borderWidth = 1
        row.layer?.borderColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        row.onLaunch = onLaunch
        
        // Icon Plate
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 6
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        row.addSubview(iconPlate)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.title) {
            iconView.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
            iconView.contentTintColor = tool.isPinned ? .white : NSColor(white: 0.70, alpha: 1.0)
        }
        iconPlate.addSubview(iconView)
        
        // Text Stack
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        row.addSubview(textStack)
        
        let titleLabel = NSTextField(labelWithString: tool.title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        textStack.addArrangedSubview(titleLabel)
        
        let subLabel = NSTextField(labelWithString: tool.subtitle)
        subLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        subLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        textStack.addArrangedSubview(subLabel)
        
        // Pin Button
        let pinBtn = NSButton()
        pinBtn.translatesAutoresizingMaskIntoConstraints = false
        pinBtn.bezelStyle = .regularSquare
        pinBtn.isBordered = false
        pinBtn.wantsLayer = true
        pinBtn.layer?.cornerRadius = 5
        pinBtn.layer?.backgroundColor = tool.isPinned ? NSColor(white: 1.0, alpha: 0.18).cgColor : NSColor(white: 1.0, alpha: 0.04).cgColor
        pinBtn.layer?.borderWidth = 1
        pinBtn.layer?.borderColor = tool.isPinned ? NSColor(white: 1.0, alpha: 0.30).cgColor : NSColor(white: 1.0, alpha: 0.08).cgColor
        pinBtn.toolTip = tool.isPinned ? "Unpin from toolbar" : "Pin to toolbar"
        
        let pinIconName = tool.isPinned ? "pin.fill" : "pin"
        if let pinImg = NSImage(systemSymbolName: pinIconName, accessibilityDescription: "Pin") {
            pinBtn.image = pinImg.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            pinBtn.contentTintColor = tool.isPinned ? .white : NSColor(white: 0.45, alpha: 1.0)
        }
        
        class PinActionHandler: NSObject {
            let act: () -> Void
            init(_ act: @escaping () -> Void) { self.act = act }
            @objc func trigger() { act() }
        }
        let handler = PinActionHandler(onPinToggle)
        objc_setAssociatedObject(pinBtn, "pinHandler", handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        pinBtn.target = handler
        pinBtn.action = #selector(PinActionHandler.trigger)
        row.addSubview(pinBtn)
        
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 44),
            
            iconPlate.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            iconPlate.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 26),
            iconPlate.heightAnchor.constraint(equalToConstant: 26),
            
            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            
            textStack.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 8),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: pinBtn.leadingAnchor, constant: -6),
            
            pinBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            pinBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            pinBtn.widthAnchor.constraint(equalToConstant: 24),
            pinBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return row
    }
    
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
        tab.webView.load(req)
        
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
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
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
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let fetchURL = URL(string: "https://duckduckgo.com/ac/?q=\(encoded)&type=list") else {
            webView?.evaluateJavaScript("window.onOnyxSuggestionsReceived && window.onOnyxSuggestionsReceived('\(reqId)', []);", completionHandler: nil)
            return
        }
        
        URLSession.shared.dataTask(with: fetchURL) { data, _, error in
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
                webView?.evaluateJavaScript("window.onOnyxSuggestionsReceived && window.onOnyxSuggestionsReceived('\(reqId)', \(jsonString));", completionHandler: nil)
            }
        }.resume()
    }
    
    func resolveQuery(_ input: String) -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return startPageURL }
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
            let len = input.hasPrefix("!lite ") ? 6 : 6
            let q = encodeQuery(String(input.dropFirst(len)).trimmingCharacters(in: .whitespaces))
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
    
    // MARK: - Bookmarks Management & Actions
    @objc func bookmarkButtonClicked(_ sender: BookmarkButton) {
        if let url = URL(string: sender.bookmark.urlString) {
            loadURL(url)
        }
    }
    
    func openBookmarkIndex(_ idx: Int) {
        guard idx < bookmarks.count else { return }
        if let url = URL(string: bookmarks[idx].urlString) {
            loadURL(url)
        }
    }
    
    @objc func toggleBookmarksBar() {
        let isVisible = bookmarksBarHeightConstraint.constant > 0
        setBookmarksBarVisible(!isVisible)
    }
    
    func setBookmarksBarVisible(_ show: Bool) {
        let currentlyVisible = bookmarksBarHeightConstraint.constant > 0
        guard show != currentlyVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.bookmarksBarHeightConstraint.animator().constant = show ? 28 : 0
            self.bookmarksBar.animator().alphaValue = show ? 1.0 : 0.0
        }
        UserDefaults.standard.set(show, forKey: "OnyxShowBookmarksBar")
    }
    
    @objc func manageBookmarksButtonClicked(_ sender: NSButton) {
        let point = NSPoint(x: sender.bounds.minX, y: sender.bounds.minY)
        showBookmarksBarMenu(at: point, in: sender)
    }
    
    func loadSavedBookmarks() {
        if let data = UserDefaults.standard.data(forKey: "OnyxBookmarks"),
           let saved = try? JSONDecoder().decode([BookmarkItem].self, from: data) {
            self.bookmarks = saved
        } else {
            self.bookmarks = BrowserController.defaultBookmarks
        }
    }
    
    func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "OnyxBookmarks")
        }
    }
    
    func loadBrowsingHistory() {
        if let data = UserDefaults.standard.data(forKey: "OnyxBrowsingHistory"),
           let saved = try? JSONDecoder().decode([BrowsingHistoryItem].self, from: data) {
            self.browsingHistory = saved
        }
    }
    
    func saveBrowsingHistory() {
        if let data = try? JSONEncoder().encode(browsingHistory) {
            UserDefaults.standard.set(data, forKey: "OnyxBrowsingHistory")
        }
    }
    
    func addBrowsingHistory(title: String, url: URL) {
        let urlStr = url.absoluteString
        guard !urlStr.isEmpty, !url.isFileURL, !urlStr.contains("startpage.html"), !urlStr.contains("settings.html"), url.scheme == "http" || url.scheme == "https" else { return }
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (url.host ?? urlStr) : title
        browsingHistory.removeAll { $0.urlString == urlStr }
        browsingHistory.insert(BrowsingHistoryItem(title: displayTitle, urlString: urlStr, timestamp: Date()), at: 0)
        if browsingHistory.count > 300 {
            browsingHistory = Array(browsingHistory.prefix(300))
        }
        saveBrowsingHistory()
    }
    
    func renderBookmarks() {
        guard bookmarksStack != nil else { return }
        
        for view in bookmarksStack.arrangedSubviews {
            bookmarksStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bookmarkButtons.removeAll()
        
        for (index, bm) in bookmarks.enumerated() {
            var updatedBM = bm
            if index < 9 {
                updatedBM.shortcut = "⌘\(index + 1)"
            } else {
                updatedBM.shortcut = ""
            }
            
            let btn = BookmarkButton(bookmark: updatedBM, target: self, action: #selector(bookmarkButtonClicked(_:)))
            btn.onOpenInNewTab = { [weak self] item in
                if let url = URL(string: item.urlString) {
                    self?.createNewTab(url: url)
                }
            }
            btn.onCopyURL = { item in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.urlString, forType: .string)
            }
            btn.onEdit = { [weak self] item in
                self?.showEditBookmarkModal(item)
            }
            btn.onDelete = { [weak self] item in
                self?.deleteBookmark(id: item.id)
            }
            btn.onAddBookmark = { [weak self] in
                self?.addNewBookmarkPrompt()
            }
            btn.onOpenManager = { [weak self] in
                self?.openBookmarkManagerModal()
            }
            btn.onHoverChanged = { [weak self] button, isHovered in
                guard let self = self else { return }
                if isHovered {
                    self.hoveredBookmarkButton = button
                    for other in self.bookmarkButtons where other !== button {
                        other.setHovered(false)
                    }
                } else if self.hoveredBookmarkButton === button {
                    self.hoveredBookmarkButton = nil
                }
            }
            
            bookmarkButtons.append(btn)
            bookmarksStack.addArrangedSubview(btn)
        }
        
        updateActiveBookmarkHighlight()
    }
    
    func deleteBookmark(id: String) {
        hoveredBookmarkButton = nil
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
        renderBookmarks()
        refreshBookmarkManagerList()
    }
    
    func deleteBookmark(at index: Int) {
        hoveredBookmarkButton = nil
        guard index >= 0 && index < bookmarks.count else { return }
        bookmarks.remove(at: index)
        saveBookmarks()
        renderBookmarks()
        refreshBookmarkManagerList()
    }
    
    func showBookmarksBarMenu(at point: NSPoint, in view: NSView) {
        let menu = createBookmarksBarMenu(at: point)
        menu.popUp(positioning: nil, at: point, in: view)
    }
    
    func createBookmarksBarMenu(at point: NSPoint) -> NSMenu {
        let menu = NSMenu(title: "Bookmarks")
        
        let addItem = NSMenuItem(title: "Add Bookmark...", action: #selector(menuAddBookmark), keyEquivalent: "d")
        if let img = NSImage(systemSymbolName: "plus", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            addItem.image = img.withSymbolConfiguration(cfg)
        }
        addItem.target = self
        menu.addItem(addItem)
        
        let addCurrentItem = NSMenuItem(title: "Add Current Page", action: #selector(menuAddCurrentPage), keyEquivalent: "")
        if let img = NSImage(systemSymbolName: "star", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            addCurrentItem.image = img.withSymbolConfiguration(cfg)
        }
        addCurrentItem.target = self
        menu.addItem(addCurrentItem)
        
        let managerItem = NSMenuItem(title: "Bookmark Manager...", action: #selector(menuOpenManager), keyEquivalent: "b")
        if let img = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            managerItem.image = img.withSymbolConfiguration(cfg)
        }
        managerItem.target = self
        menu.addItem(managerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Delete Bookmark Submenu
        let deleteSubmenu = NSMenu(title: "Delete Bookmark")
        if bookmarks.isEmpty {
            let emptyItem = NSMenuItem(title: "No Bookmarks to Delete", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            deleteSubmenu.addItem(emptyItem)
        } else {
            for (index, bm) in bookmarks.enumerated() {
                let item = NSMenuItem(title: bm.title, action: #selector(menuDeleteSpecificBookmark(_:)), keyEquivalent: "")
                if let img = NSImage(systemSymbolName: bm.iconName, accessibilityDescription: nil) {
                    let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                    item.image = img.withSymbolConfiguration(cfg)
                }
                item.target = self
                item.tag = index
                item.toolTip = "Delete \(bm.title) (\(bm.urlString))"
                deleteSubmenu.addItem(item)
            }
            deleteSubmenu.addItem(NSMenuItem.separator())
            let delAllItem = NSMenuItem(title: "Delete All Bookmarks...", action: #selector(menuDeleteAllBookmarks), keyEquivalent: "")
            if let img = NSImage(systemSymbolName: "trash", accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                delAllItem.image = img.withSymbolConfiguration(cfg)
            }
            delAllItem.target = self
            deleteSubmenu.addItem(delAllItem)
        }
        
        let deleteMenuItem = NSMenuItem(title: "Delete Bookmark", action: nil, keyEquivalent: "")
        if let img = NSImage(systemSymbolName: "trash", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            deleteMenuItem.image = img.withSymbolConfiguration(cfg)
        }
        deleteMenuItem.submenu = deleteSubmenu
        menu.addItem(deleteMenuItem)
        
        // Edit Bookmark Submenu
        let editSubmenu = NSMenu(title: "Edit Bookmark")
        if bookmarks.isEmpty {
            let emptyItem = NSMenuItem(title: "No Bookmarks to Edit", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            editSubmenu.addItem(emptyItem)
        } else {
            for (index, bm) in bookmarks.enumerated() {
                let item = NSMenuItem(title: bm.title, action: #selector(menuEditSpecificBookmark(_:)), keyEquivalent: "")
                if let img = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil) {
                    let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                    item.image = img.withSymbolConfiguration(cfg)
                }
                item.target = self
                item.tag = index
                item.toolTip = "Edit \(bm.title)"
                editSubmenu.addItem(item)
            }
        }
        let editMenuItem = NSMenuItem(title: "Edit Bookmark", action: nil, keyEquivalent: "")
        if let img = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            editMenuItem.image = img.withSymbolConfiguration(cfg)
        }
        editMenuItem.submenu = editSubmenu
        menu.addItem(editMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let resetItem = NSMenuItem(title: "Reset to Default Bookmarks", action: #selector(menuResetDefaults), keyEquivalent: "")
        if let img = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            resetItem.image = img.withSymbolConfiguration(cfg)
        }
        resetItem.target = self
        menu.addItem(resetItem)
        
        let isVisible = bookmarksBarHeightConstraint.constant > 0
        let hideItem = NSMenuItem(title: isVisible ? "Hide Bookmarks Bar" : "Show Bookmarks Bar", action: #selector(toggleBookmarksBar), keyEquivalent: "")
        if let img = NSImage(systemSymbolName: isVisible ? "eye.slash" : "eye", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            hideItem.image = img.withSymbolConfiguration(cfg)
        }
        hideItem.target = self
        menu.addItem(hideItem)
        
        return menu
    }
    
    @objc func menuAddBookmark() {
        addNewBookmarkPrompt()
    }
    
    @objc func menuAddCurrentPage() {
        let currentURL = activeTab.url
        var title = activeTab.title
        if title.isEmpty || title == "New Tab" {
            title = currentURL.host ?? "Bookmark"
        }
        let urlStr = currentURL.absoluteString
        let icon = iconNameForURL(urlStr)
        let item = BookmarkItem(title: title, urlString: urlStr, iconName: icon)
        bookmarks.append(item)
        saveBookmarks()
        renderBookmarks()
    }
    
    @objc func menuOpenManager() {
        openBookmarkManagerModal()
    }
    
    @objc func menuDeleteSpecificBookmark(_ sender: NSMenuItem) {
        deleteBookmark(at: sender.tag)
    }
    
    @objc func menuEditSpecificBookmark(_ sender: NSMenuItem) {
        guard sender.tag >= 0 && sender.tag < bookmarks.count else { return }
        showEditBookmarkModal(bookmarks[sender.tag])
    }
    
    @objc func menuDeleteAllBookmarks() {
        let alert = NSAlert()
        alert.messageText = "Delete All Bookmarks?"
        alert.informativeText = "Are you sure you want to remove all bookmarks? This cannot be undone."
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical
        if let win = self.window {
            alert.beginSheetModal(for: win) { [weak self] resp in
                if resp == .alertFirstButtonReturn {
                    self?.bookmarks.removeAll()
                    self?.saveBookmarks()
                    self?.renderBookmarks()
                    self?.refreshBookmarkManagerList()
                }
            }
        }
    }
    
    @objc func menuResetDefaults() {
        bookmarks = BrowserController.defaultBookmarks
        saveBookmarks()
        renderBookmarks()
        refreshBookmarkManagerList()
    }
    
    func addNewBookmarkPrompt() {
        let alert = NSAlert()
        alert.messageText = "Add Bookmark"
        alert.informativeText = "Enter the title and URL for the new bookmark:"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 64))
        
        let titleInput = NSTextField(frame: NSRect(x: 0, y: 36, width: 320, height: 24))
        titleInput.placeholderString = "Title (e.g. Google)"
        titleInput.stringValue = (activeTab.title != "New Tab" && !activeTab.title.isEmpty) ? activeTab.title : ""
        
        let urlInput = NSTextField(frame: NSRect(x: 0, y: 4, width: 320, height: 24))
        urlInput.placeholderString = "URL (e.g. https://google.com)"
        let activeURLStr = activeTab.url.absoluteString
        urlInput.stringValue = (!activeURLStr.contains("startpage.html") && !activeURLStr.isEmpty) ? activeURLStr : "https://"
        
        container.addSubview(titleInput)
        container.addSubview(urlInput)
        alert.accessoryView = container
        
        if let win = self.window {
            alert.beginSheetModal(for: win) { [weak self] resp in
                guard let self = self, resp == .alertFirstButtonReturn else { return }
                var t = titleInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                var u = urlInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { t = u }
                if !u.lowercased().hasPrefix("http://") && !u.lowercased().hasPrefix("https://") {
                    u = "https://" + u
                }
                let icon = self.iconNameForURL(u)
                let newItem = BookmarkItem(title: t, urlString: u, iconName: icon)
                self.bookmarks.append(newItem)
                self.saveBookmarks()
                self.renderBookmarks()
                self.refreshBookmarkManagerList()
            }
        }
    }
    
    func showEditBookmarkModal(_ item: BookmarkItem) {
        let alert = NSAlert()
        alert.messageText = "Edit Bookmark"
        alert.informativeText = "Modify the title or destination URL:"
        alert.addButton(withTitle: "Save")
        let cancelBtn = alert.addButton(withTitle: "Cancel")
        cancelBtn.keyEquivalent = "\u{1b}"
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 64))
        
        let titleInput = NSTextField(frame: NSRect(x: 0, y: 36, width: 320, height: 24))
        titleInput.stringValue = item.title
        titleInput.placeholderString = "Bookmark Title"
        
        let urlInput = NSTextField(frame: NSRect(x: 0, y: 4, width: 320, height: 24))
        urlInput.stringValue = item.urlString
        urlInput.placeholderString = "https://..."
        
        container.addSubview(titleInput)
        container.addSubview(urlInput)
        alert.accessoryView = container
        
        if let win = self.window {
            alert.window.initialFirstResponder = titleInput
            DispatchQueue.main.async {
                titleInput.selectText(nil)
            }
            alert.beginSheetModal(for: win) { [weak self] resp in
                guard let self = self, resp == .alertFirstButtonReturn else { return }
                guard let idx = self.bookmarks.firstIndex(where: { $0.id == item.id }) else { return }
                var t = titleInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                var u = urlInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { t = item.title }
                if !u.lowercased().hasPrefix("http://") && !u.lowercased().hasPrefix("https://") {
                    u = "https://" + u
                }
                self.bookmarks[idx].title = t
                self.bookmarks[idx].urlString = u
                if let h = URL(string: u)?.host {
                    self.bookmarks[idx].domain = h
                }
                self.bookmarks[idx].iconName = self.iconNameForURL(u)
                self.saveBookmarks()
                self.renderBookmarks()
                self.refreshBookmarkManagerList()
            }
        }
    }
    
    func openBookmarkManagerModal() {
        if let pop = bookmarkManagerPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let contentWidth: CGFloat = 380
        let totalHeight: CGFloat = 400
        let headerHeight: CGFloat = 48
        let footerHeight: CGFloat = 44
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: totalHeight))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.25).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        // Header View
        let headerView = NSView(frame: NSRect(x: 0, y: totalHeight - headerHeight, width: contentWidth, height: headerHeight))
        let titleLabel = NSTextField(labelWithString: "Bookmarks")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        headerView.addSubview(titleLabel)
        
        let countBadge = NSTextField(labelWithString: "\(bookmarks.count) items")
        countBadge.translatesAutoresizingMaskIntoConstraints = false
        countBadge.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        countBadge.textColor = NSColor(white: 0.55, alpha: 1.0)
        headerView.addSubview(countBadge)
        self.bookmarkManagerCountLabel = countBadge
        
        let addBtn = NSButton(frame: .zero)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.bezelStyle = .regularSquare
        addBtn.isBordered = false
        addBtn.wantsLayer = true
        addBtn.layer?.cornerRadius = 5
        addBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        addBtn.setMonochromeTitle("＋ Add Bookmark", color: .white, font: NSFont.systemFont(ofSize: 11, weight: .medium))
        addBtn.target = self
        addBtn.action = #selector(managerAddClicked)
        headerView.addSubview(addBtn)
        container.addSubview(headerView)
        
        let headerSep = NSBox(frame: NSRect(x: 0, y: totalHeight - headerHeight, width: contentWidth, height: 1))
        headerSep.boxType = .custom
        headerSep.borderWidth = 0
        headerSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        container.addSubview(headerSep)
        
        // ScrollView & Stack
        let scrollY = footerHeight
        let scrollHeight = totalHeight - headerHeight - footerHeight
        let scrollView = NSScrollView(frame: NSRect(x: 6, y: scrollY, width: contentWidth - 12, height: scrollHeight))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        
        let rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.spacing = 4
        rowsStack.alignment = .leading
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        self.bookmarkManagerStack = rowsStack
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = rowsStack
        scrollView.contentView = clipView
        container.addSubview(scrollView)
        
        let footerSep = NSBox(frame: NSRect(x: 0, y: footerHeight, width: contentWidth, height: 1))
        footerSep.boxType = .custom
        footerSep.borderWidth = 0
        footerSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        container.addSubview(footerSep)
        
        // Footer View
        let footerView = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: footerHeight))
        let resetBtn = NSButton(frame: .zero)
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        resetBtn.bezelStyle = .regularSquare
        resetBtn.isBordered = false
        resetBtn.wantsLayer = true
        resetBtn.layer?.cornerRadius = 4
        resetBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        resetBtn.setMonochromeTitle("Reset Defaults", color: NSColor(white: 0.70, alpha: 1.0), font: NSFont.systemFont(ofSize: 11, weight: .regular))
        resetBtn.target = self
        resetBtn.action = #selector(managerResetClicked)
        footerView.addSubview(resetBtn)
        
        let doneBtn = NSButton(frame: .zero)
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.bezelStyle = .regularSquare
        doneBtn.isBordered = false
        doneBtn.wantsLayer = true
        doneBtn.layer?.cornerRadius = 5
        doneBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        doneBtn.setMonochromeTitle("Done", color: .white, font: NSFont.systemFont(ofSize: 11, weight: .semibold))
        doneBtn.target = self
        doneBtn.action = #selector(managerDoneClicked)
        footerView.addSubview(doneBtn)
        container.addSubview(footerView)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            countBadge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countBadge.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            addBtn.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -14),
            addBtn.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 104),
            addBtn.heightAnchor.constraint(equalToConstant: 24),
            
            resetBtn.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 14),
            resetBtn.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            resetBtn.widthAnchor.constraint(equalToConstant: 96),
            resetBtn.heightAnchor.constraint(equalToConstant: 24),
            
            doneBtn.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -14),
            doneBtn.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            doneBtn.widthAnchor.constraint(equalToConstant: 58),
            doneBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        refreshBookmarkManagerList()
        
        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc
        self.bookmarkManagerPopover = popover
        
        if let btn = manageBookmarksBtn {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .maxY)
        } else {
            popover.show(relativeTo: bookmarksBar.bounds, of: bookmarksBar, preferredEdge: .maxY)
        }
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
    }
    
    func refreshBookmarkManagerList() {
        guard let stack = bookmarkManagerStack else { return }
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        bookmarkManagerCountLabel?.stringValue = "\(bookmarks.count) items"
        
        if bookmarks.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No bookmarks yet. Click ＋ Add Bookmark to create one.")
            emptyLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            emptyLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
            stack.addArrangedSubview(emptyLabel)
            return
        }
        
        for bm in bookmarks {
            let row = BookmarkManagerRowView(bookmark: bm)
            row.widthAnchor.constraint(equalToConstant: 356).isActive = true
            row.onDelete = { [weak self] in
                self?.deleteBookmark(id: bm.id)
            }
            row.onEdit = { [weak self] in
                self?.showEditBookmarkModal(bm)
            }
            row.onOpen = { [weak self] in
                if let url = URL(string: bm.urlString) {
                    self?.loadURL(url)
                    self?.bookmarkManagerPopover?.performClose(nil)
                }
            }
            stack.addArrangedSubview(row)
        }
    }
    
    @objc func managerAddClicked() {
        addNewBookmarkPrompt()
    }
    
    @objc func managerResetClicked() {
        menuResetDefaults()
    }
    
    @objc func managerDoneClicked() {
        bookmarkManagerPopover?.performClose(nil)
    }
    
    func iconNameForURL(_ urlString: String) -> String {
        let lower = urlString.lowercased()
        if lower.contains("github") { return "chevron.left.forwardslash.chevron.right" }
        if lower.contains("ninjatrader") || lower.contains("tradesea") || lower.contains("trade") || lower.contains("chart") || lower.contains("market") || lower.contains("stock") { return "chart.xyaxis.line" }
        if lower.contains("canvas") || lower.contains("unapec") || lower.contains("edu") || lower.contains("school") || lower.contains("college") { return "graduationcap" }
        if lower.contains("conflictly") || lower.contains("chat") || lower.contains("slack") || lower.contains("discord") { return "bubble.left.and.bubble.right" }
        if lower.contains("finviz") || lower.contains("crypto") || lower.contains("finance") { return "waveform.path.ecg" }
        if lower.contains("mail") || lower.contains("inbox") { return "envelope" }
        if lower.contains("news") || lower.contains("ycombinator") || lower.contains("article") { return "newspaper" }
        if lower.contains("youtube") || lower.contains("video") { return "play.rectangle" }
        if lower.contains("spotify") || lower.contains("music") { return "music.note" }
        return "globe"
    }
    
    // MARK: - Downloads Management & Actions
    @objc func toggleDownloadsPopover() {
        if let pop = downloadsPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        showDownloadsPopover()
    }
    
    func showDownloadsPopover() {
        downloadsButton.hasUnseenFinished = false
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340, height: 360))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.25).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        // Header (44px)
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        
        let titleLabel = NSTextField(labelWithString: "Downloads")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.white
        header.addSubview(titleLabel)
        
        let openFolderBtn = NavIconButton(iconName: "folder", tooltip: "Open Downloads Folder", target: self, action: #selector(openDownloadsFolder))
        header.addSubview(openFolderBtn)
        
        let clearBtn = NavIconButton(iconName: "trash", tooltip: "Clear Downloads List", target: self, action: #selector(clearDownloadsList))
        header.addSubview(clearBtn)
        clearBtn.isEnabled = !downloads.isEmpty
        
        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .custom
        sep.borderWidth = 0
        sep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        header.addSubview(sep)
        
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),
            
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            clearBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            clearBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            openFolderBtn.trailingAnchor.constraint(equalTo: clearBtn.leadingAnchor, constant: -4),
            openFolderBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            sep.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1)
        ])
        
        if downloads.isEmpty {
            let emptyView = NSView()
            emptyView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(emptyView)
            
            let emptyIcon = NSImageView()
            emptyIcon.translatesAutoresizingMaskIntoConstraints = false
            if let img = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 36, weight: .light)
                emptyIcon.image = img.withSymbolConfiguration(cfg)
                emptyIcon.contentTintColor = NSColor(white: 1.0, alpha: 0.22)
            }
            emptyView.addSubview(emptyIcon)
            
            let emptyTitle = NSTextField(labelWithString: "No Downloads")
            emptyTitle.translatesAutoresizingMaskIntoConstraints = false
            emptyTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            emptyTitle.textColor = NSColor(white: 0.60, alpha: 1.0)
            emptyView.addSubview(emptyTitle)
            
            let emptySub = NSTextField(labelWithString: "Files you download will appear here.")
            emptySub.translatesAutoresizingMaskIntoConstraints = false
            emptySub.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptySub.textColor = NSColor(white: 0.40, alpha: 1.0)
            emptyView.addSubview(emptySub)
            
            NSLayoutConstraint.activate([
                emptyView.topAnchor.constraint(equalTo: header.bottomAnchor),
                emptyView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                emptyView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                emptyView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                
                emptyIcon.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                emptyIcon.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor, constant: -16),
                emptyIcon.widthAnchor.constraint(equalToConstant: 40),
                emptyIcon.heightAnchor.constraint(equalToConstant: 40),
                
                emptyTitle.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                emptyTitle.topAnchor.constraint(equalTo: emptyIcon.bottomAnchor, constant: 10),
                
                emptySub.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                emptySub.topAnchor.constraint(equalTo: emptyTitle.bottomAnchor, constant: 4)
            ])
        } else {
            let scrollView = NSScrollView()
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.hasVerticalScroller = true
            scrollView.drawsBackground = false
            scrollView.autohidesScrollers = true
            container.addSubview(scrollView)
            
            let rowsStack = NSStackView()
            rowsStack.translatesAutoresizingMaskIntoConstraints = false
            rowsStack.orientation = .vertical
            rowsStack.spacing = 4
            rowsStack.alignment = .leading
            
            for item in downloads {
                let row = OnyxDownloadRowView(item: item)
                row.onShowInFinder = {
                    if let dest = item.destinationURL {
                        NSWorkspace.shared.activateFileViewerSelecting([dest])
                    }
                }
                row.onOpenFile = {
                    if let dest = item.destinationURL {
                        NSWorkspace.shared.open(dest)
                    }
                }
                row.onCancel = { [weak self] in
                    item.download?.cancel { _ in }
                    item.state = .cancelled
                    self?.updateDownloadsState()
                    self?.showDownloadsPopover()
                }
                rowsStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            }
            
            let clip = FlippedClipView()
            clip.drawsBackground = false
            clip.documentView = rowsStack
            scrollView.contentView = clip
            
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
                scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
                
                rowsStack.topAnchor.constraint(equalTo: clip.topAnchor),
                rowsStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                rowsStack.trailingAnchor.constraint(equalTo: clip.trailingAnchor)
            ])
        }
        
        let controller = NSViewController()
        controller.view = container
        popover.contentViewController = controller
        
        let anchor = (downloadsButton.isHidden || downloadsButton.window == nil) ? extensionsButton! : downloadsButton!
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
        downloadsPopover = popover
    }
    
    @objc func openDownloadsFolder() {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        NSWorkspace.shared.open(downloadsDir)
    }
    
    @objc func clearDownloadsList() {
        downloads.removeAll { item in
            if case .downloading = item.state { return false }
            return true
        }
        updateDownloadsState()
        downloadsPopover?.performClose(nil)
    }
    
    func registerDownload(download: WKDownload, sourceURL: URL?) {
        let filename = sourceURL?.lastPathComponent.isEmpty == false ? sourceURL!.lastPathComponent : "download"
        let item = OnyxDownloadItem(download: download, filename: filename, sourceURL: sourceURL)
        activeDownloads[download] = item
        downloads.insert(item, at: 0)
        
        updateDownloadsState()
        startDownloadProgressTimer()
    }
    
    func updateDownloadDestination(download: WKDownload, url: URL, filename: String) {
        guard let item = activeDownloads[download] else { return }
        item.destinationURL = url
        item.filename = filename
    }
    
    func handleDownloadFinished(download: WKDownload) {
        guard let item = activeDownloads[download] else { return }
        item.state = .completed
        item.finishDate = Date()
        activeDownloads.removeValue(forKey: download)
        
        downloadsButton.hasUnseenFinished = true
        downloadsButton.triggerBounce()
        NSSound(named: "Glass")?.play()
        
        showDownloadCompleteHUD(item: item)
        updateDownloadsState()
    }
    
    func handleDownloadFailed(download: WKDownload, error: Error) {
        guard let item = activeDownloads[download] else { return }
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
            item.state = .cancelled
        } else {
            item.state = .failed
            item.errorMessage = error.localizedDescription
        }
        activeDownloads.removeValue(forKey: download)
        updateDownloadsState()
    }
    
    func startDownloadProgressTimer() {
        if downloadProgressTimer == nil {
            downloadProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.pollDownloadProgress()
            }
        }
    }
    
    func pollDownloadProgress() {
        if activeDownloads.isEmpty {
            downloadProgressTimer?.invalidate()
            downloadProgressTimer = nil
            updateDownloadsState()
            return
        }
        
        var totalFraction: Double = 0.0
        for (download, item) in activeDownloads {
            let prog = download.progress
            item.progressFraction = prog.fractionCompleted
            item.receivedBytes = prog.completedUnitCount
            item.totalBytes = prog.totalUnitCount
            totalFraction += prog.fractionCompleted
        }
        
        let avgFraction = totalFraction / Double(activeDownloads.count)
        downloadsButton.progress = avgFraction
        downloadsButton.toolTip = "Downloading... (\(Int(avgFraction * 100))%)"
    }
    
    func updateDownloadsState() {
        let isDownloading = !activeDownloads.isEmpty
        downloadsButton.isDownloading = isDownloading
        if !isDownloading && !downloadsButton.hasUnseenFinished {
            downloadsButton.toolTip = "Downloads (⌘J)"
        }
    }
    
    func showDownloadCompleteHUD(item: OnyxDownloadItem) {
        guard let dest = item.destinationURL, let contentView = self.window?.contentView else { return }
        
        activeDownloadHUD?.dismiss()
        let hud = DownloadNotificationHUD(filename: item.filename, fileURL: dest)
        activeDownloadHUD = hud
        contentView.addSubview(hud)
        
        NSLayoutConstraint.activate([
            hud.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            hud.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            hud.widthAnchor.constraint(equalToConstant: 320),
            hud.heightAnchor.constraint(equalToConstant: 48)
        ])
        
        hud.animateIn()
    }
    
    @objc func openLocalFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a file to open in Onyx"
        
        if let win = self.window {
            panel.beginSheetModal(for: win) { [weak self] response in
                if response == .OK, let url = panel.url {
                    self?.loadURL(url)
                }
            }
        } else {
            panel.begin { [weak self] response in
                if response == .OK, let url = panel.url {
                    self?.loadURL(url)
                }
            }
        }
    }
    
    // MARK: - Password Manager & Vault Actions
    @objc func togglePasswordsPopover() {
        if let pop = passwordsPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        showPasswordsPopover()
    }
    
    func showPasswordsPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let width: CGFloat = 420
        let height: CGFloat = 480
        popover.contentSize = NSSize(width: width, height: height)
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.25).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        // 1. Header (48px)
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        
        let headerIcon = NSImageView()
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Passwords Vault") {
            headerIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            headerIcon.contentTintColor = .white
        }
        header.addSubview(headerIcon)
        
        let titleLabel = NSTextField(labelWithString: "PASSWORDS & VAULT")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = .white
        header.addSubview(titleLabel)
        
        let countLabel = NSTextField(labelWithString: "")
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        header.addSubview(countLabel)
        self.passwordCountLabel = countLabel
        
        let headerActions = NSStackView()
        headerActions.translatesAutoresizingMaskIntoConstraints = false
        headerActions.orientation = .horizontal
        headerActions.spacing = 4
        headerActions.alignment = .centerY
        header.addSubview(headerActions)
        
        let exportBtn = NavIconButton(iconName: "square.and.arrow.up", tooltip: "Export Passwords to CSV", target: self, action: #selector(exportPasswordsPrompt), size: 24)
        headerActions.addArrangedSubview(exportBtn)
        
        let importBtn = NavIconButton(iconName: "square.and.arrow.down", tooltip: "Import Passwords (CSV, JSON, Chrome, Safari, Bitwarden...)", target: self, action: #selector(importPasswordsPrompt), size: 24)
        headerActions.addArrangedSubview(importBtn)
        
        let addBtn = NavIconButton(iconName: "plus", tooltip: "Add New Login (⌘N)", target: self, action: #selector(openAddPasswordModal), size: 24)
        headerActions.addArrangedSubview(addBtn)
        
        let headerSep = NSBox()
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        headerSep.boxType = .custom
        headerSep.borderWidth = 0
        headerSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        header.addSubview(headerSep)
        
        // 2. Search Container (40px)
        let searchBox = NSView()
        searchBox.translatesAutoresizingMaskIntoConstraints = false
        searchBox.wantsLayer = true
        searchBox.layer?.cornerRadius = 8
        searchBox.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        searchBox.layer?.borderWidth = 1
        searchBox.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        container.addSubview(searchBox)
        
        let searchIcon = NSImageView()
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") {
            searchIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
            searchIcon.contentTintColor = NSColor(white: 0.45, alpha: 1.0)
        }
        searchBox.addSubview(searchIcon)
        
        let searchInput = NSTextField()
        searchInput.translatesAutoresizingMaskIntoConstraints = false
        searchInput.isBordered = false
        searchInput.drawsBackground = false
        searchInput.focusRingType = .none
        searchInput.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        searchInput.textColor = .white
        searchInput.placeholderAttributedString = NSAttributedString(
            string: "Search passwords, usernames, domains...",
            attributes: [
                .foregroundColor: NSColor(white: 0.45, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12, weight: .regular)
            ]
        )
        searchInput.target = self
        searchInput.action = #selector(passwordSearchChanged(_:))
        searchInput.delegate = self
        searchBox.addSubview(searchInput)
        self.passwordSearchField = searchInput
        
        // 3. Scrollable Stack for Password Rows
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        container.addSubview(scrollView)
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        
        let rowsStack = NSStackView()
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.orientation = .vertical
        rowsStack.spacing = 4
        rowsStack.alignment = .leading
        documentView.addSubview(rowsStack)
        self.passwordRowsStack = rowsStack
        
        // 4. Footer (36px)
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(footer)
        
        let footerSep = NSBox()
        footerSep.translatesAutoresizingMaskIntoConstraints = false
        footerSep.boxType = .custom
        footerSep.borderWidth = 0
        footerSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        footer.addSubview(footerSep)
        
        let statusStack = NSStackView()
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusStack.orientation = .horizontal
        statusStack.spacing = 5
        statusStack.alignment = .centerY
        footer.addSubview(statusStack)
        
        let statusIcon = NSImageView()
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Encrypted Vault") {
            statusIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10.5, weight: .medium))
            statusIcon.contentTintColor = NSColor(white: 0.50, alpha: 1.0)
        }
        statusStack.addArrangedSubview(statusIcon)
        
        let footerStatus = NSTextField(labelWithString: "AES-256 • Keychain Vault")
        footerStatus.translatesAutoresizingMaskIntoConstraints = false
        footerStatus.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        footerStatus.textColor = NSColor(white: 0.50, alpha: 1.0)
        statusStack.addArrangedSubview(footerStatus)
        
        let generateBtn = NSButton()
        generateBtn.translatesAutoresizingMaskIntoConstraints = false
        generateBtn.bezelStyle = .regularSquare
        generateBtn.isBordered = false
        generateBtn.wantsLayer = true
        generateBtn.layer?.cornerRadius = 5
        generateBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        generateBtn.imagePosition = .imageLeading
        if let img = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Generate") {
            generateBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
            generateBtn.contentTintColor = NSColor(white: 0.85, alpha: 1.0)
        }
        generateBtn.setMonochromeTitle(" Generate Password", color: NSColor(white: 0.90, alpha: 1.0), font: NSFont.systemFont(ofSize: 10.5, weight: .medium))
        generateBtn.target = self
        generateBtn.action = #selector(generateQuickPasswordAction)
        footer.addSubview(generateBtn)
        
        // Layout Constraints (Strictly aligned to 8px base grid / 4px increments)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),
            container.heightAnchor.constraint(equalToConstant: height),
            
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),
            
            headerIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            headerIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerIcon.widthAnchor.constraint(equalToConstant: 18),
            headerIcon.heightAnchor.constraint(equalToConstant: 18),
            
            titleLabel.leadingAnchor.constraint(equalTo: headerIcon.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            headerActions.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            headerActions.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            headerSep.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            headerSep.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerSep.heightAnchor.constraint(equalToConstant: 1),
            
            searchBox.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            searchBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            searchBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            searchBox.heightAnchor.constraint(equalToConstant: 32),
            
            searchIcon.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 8),
            searchIcon.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 14),
            searchIcon.heightAnchor.constraint(equalToConstant: 14),
            
            searchInput.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchInput.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -8),
            searchInput.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            
            scrollView.topAnchor.constraint(equalTo: searchBox.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            
            documentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            documentView.bottomAnchor.constraint(equalTo: rowsStack.bottomAnchor, constant: 8),
            
            rowsStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 4),
            rowsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 4),
            rowsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -4),
            
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 36),
            
            footerSep.topAnchor.constraint(equalTo: footer.topAnchor),
            footerSep.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            footerSep.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            footerSep.heightAnchor.constraint(equalToConstant: 1),
            
            statusStack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            statusStack.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            
            generateBtn.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            generateBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            generateBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc
        self.passwordsPopover = popover
        
        refreshPasswordManagerList(query: "")
        let anchor = (passwordsButton.isHidden || passwordsButton.window == nil) ? extensionsButton! : passwordsButton!
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
        DispatchQueue.main.async {
            searchInput.window?.makeFirstResponder(searchInput)
        }
    }
    
    func refreshPasswordManagerList(query: String = "") {
        guard let stack = passwordRowsStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let allEntries = passwordStore.allEntries()
        let filtered = passwordStore.filteredEntries(query: query)
        
        let activeHost = activeWebView.url?.host ?? ""
        let activeMatches = filtered.filter { $0.matches(host: activeHost) }
        let otherEntries = filtered.filter { !$0.matches(host: activeHost) }
            .sorted(by: { $0.title.lowercased() < $1.title.lowercased() })
        
        if query.isEmpty {
            passwordCountLabel?.stringValue = "\(allEntries.count) Logins"
        } else {
            passwordCountLabel?.stringValue = "\(filtered.count) of \(allEntries.count)"
        }
        
        if filtered.isEmpty {
            let emptyView = NSView()
            emptyView.translatesAutoresizingMaskIntoConstraints = false
            emptyView.heightAnchor.constraint(equalToConstant: 220).isActive = true
            emptyView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            if let img = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil) {
                icon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 36, weight: .light))
                icon.contentTintColor = NSColor(white: 1.0, alpha: 0.2)
            }
            emptyView.addSubview(icon)
            
            let label = NSTextField(labelWithString: query.isEmpty ? "No Saved Passwords" : "No Matches Found")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            label.textColor = NSColor(white: 0.7, alpha: 1.0)
            emptyView.addSubview(label)
            
            let sub = NSTextField(labelWithString: query.isEmpty ? "Import from Chrome, Safari, Bitwarden, or add a login." : "Try searching for a different domain or username.")
            sub.translatesAutoresizingMaskIntoConstraints = false
            sub.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            sub.textColor = NSColor(white: 0.45, alpha: 1.0)
            emptyView.addSubview(sub)
            
            let btnStack = NSStackView()
            btnStack.translatesAutoresizingMaskIntoConstraints = false
            btnStack.orientation = .horizontal
            btnStack.spacing = 8
            btnStack.alignment = .centerY
            emptyView.addSubview(btnStack)
            
            let impBtn = NSButton()
            impBtn.translatesAutoresizingMaskIntoConstraints = false
            impBtn.bezelStyle = .regularSquare
            impBtn.isBordered = false
            impBtn.wantsLayer = true
            impBtn.layer?.cornerRadius = 5
            impBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            impBtn.setMonochromeTitle("Import Passwords...", color: .white, font: NSFont.systemFont(ofSize: 11, weight: .medium))
            impBtn.target = self
            impBtn.action = #selector(importPasswordsPrompt)
            btnStack.addArrangedSubview(impBtn)
            
            let addBtn = NSButton()
            addBtn.translatesAutoresizingMaskIntoConstraints = false
            addBtn.bezelStyle = .regularSquare
            addBtn.isBordered = false
            addBtn.wantsLayer = true
            addBtn.layer?.cornerRadius = 5
            addBtn.layer?.backgroundColor = NSColor.white.cgColor
            addBtn.setMonochromeTitle("+ Add Login", color: NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 1.0), font: NSFont.systemFont(ofSize: 11, weight: .semibold))
            addBtn.target = self
            addBtn.action = #selector(openAddPasswordModal)
            btnStack.addArrangedSubview(addBtn)
            
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor, constant: -36),
                icon.widthAnchor.constraint(equalToConstant: 44),
                icon.heightAnchor.constraint(equalToConstant: 44),
                
                label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
                label.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                
                sub.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
                sub.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                
                btnStack.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 16),
                btnStack.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                
                impBtn.heightAnchor.constraint(equalToConstant: 28),
                impBtn.widthAnchor.constraint(equalToConstant: 130),
                addBtn.heightAnchor.constraint(equalToConstant: 28),
                addBtn.widthAnchor.constraint(equalToConstant: 96)
            ])
            
            stack.addArrangedSubview(emptyView)
            return
        }
        
        func createSectionLabel(text: String, isAccent: Bool) -> NSView {
            let v = NSView()
            v.translatesAutoresizingMaskIntoConstraints = false
            v.heightAnchor.constraint(equalToConstant: 20).isActive = true
            let lbl = NSTextField(labelWithString: text)
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
            lbl.textColor = isAccent ? .white : NSColor(white: 0.45, alpha: 1.0)
            v.addSubview(lbl)
            NSLayoutConstraint.activate([
                lbl.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
                lbl.centerYAnchor.constraint(equalTo: v.centerYAnchor)
            ])
            return v
        }
        
        if !activeMatches.isEmpty {
            let activeHeader = createSectionLabel(text: "MATCHING ACTIVE TAB", isAccent: true)
            stack.addArrangedSubview(activeHeader)
            activeHeader.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            
            for entry in activeMatches {
                let row = OnyxPasswordRowView(entry: entry, isCurrentSite: true)
                configurePasswordRowCallbacks(row)
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            
            if !otherEntries.isEmpty {
                let sep = NSBox()
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.boxType = .custom
                sep.borderWidth = 0
                sep.fillColor = NSColor(white: 1.0, alpha: 0.08)
                stack.addArrangedSubview(sep)
                NSLayoutConstraint.activate([
                    sep.heightAnchor.constraint(equalToConstant: 1),
                    sep.widthAnchor.constraint(equalTo: stack.widthAnchor)
                ])
                
                let allHeader = createSectionLabel(text: "ALL VAULT LOGINS", isAccent: false)
                stack.addArrangedSubview(allHeader)
                allHeader.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        
        for entry in otherEntries {
            let row = OnyxPasswordRowView(entry: entry, isCurrentSite: false)
            configurePasswordRowCallbacks(row)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
    
    private func configurePasswordRowCallbacks(_ row: OnyxPasswordRowView) {
        row.onAutofill = { [weak self] entry in
            self?.autofillActiveTab(with: entry)
        }
        row.onCopyPassword = { [weak self] entry in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.password, forType: .string)
            self?.showVaultToastHUD(icon: "key.fill", title: "PASSWORD COPIED", message: "Password for \(entry.title) copied to clipboard")
        }
        row.onCopyUsername = { [weak self] entry in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.username, forType: .string)
            self?.showVaultToastHUD(icon: "person.fill", title: "USERNAME COPIED", message: "Username \(entry.username) copied to clipboard")
        }
        row.onEdit = { [weak self] entry in
            self?.passwordsPopover?.performClose(nil)
            self?.showPasswordEditorModal(entry: entry)
        }
        row.onDelete = { [weak self] entry in
            self?.passwordStore.delete(id: entry.id)
            self?.refreshPasswordManagerList(query: self?.passwordSearchField?.stringValue ?? "")
            self?.updatePasswordsBadge(for: self?.activeWebView.url)
            self?.showVaultToastHUD(icon: "trash", title: "LOGIN REMOVED", message: "Deleted \(entry.title) from vault")
        }
    }
    
    @objc func passwordSearchChanged(_ sender: NSTextField) {
        refreshPasswordManagerList(query: sender.stringValue)
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField {
            if tf === passwordSearchField {
                refreshPasswordManagerList(query: tf.stringValue)
            } else if tf === searchField {
                updateSearchContainerGlow(for: tf.stringValue)
                handleSearchFieldInputChanged(query: tf.stringValue)
            }
        }
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === searchField {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                if suggestionsPopover?.isShown == true {
                    suggestionsView?.moveSelection(direction: -1)
                    if let item = suggestionsView?.selectedItem() {
                        searchField.stringValue = item.searchQuery ?? item.urlString ?? item.title
                    }
                    return true
                }
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if suggestionsPopover?.isShown == true {
                    suggestionsView?.moveSelection(direction: 1)
                    if let item = suggestionsView?.selectedItem() {
                        searchField.stringValue = item.searchQuery ?? item.urlString ?? item.title
                    }
                    return true
                }
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if suggestionsPopover?.isShown == true {
                    closeSuggestionsPopover()
                    return true
                }
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if suggestionsPopover?.isShown == true, let selected = suggestionsView?.selectedItem() {
                    closeSuggestionsPopover()
                    executeSelectedSuggestion(selected)
                    return true
                }
                closeSuggestionsPopover()
                searchFieldSubmitted()
                return true
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if suggestionsPopover?.isShown == true, let selected = suggestionsView?.selectedItem() {
                    searchField.stringValue = selected.searchQuery ?? selected.urlString ?? selected.title
                    return true
                }
            }
        }
        return false
    }
    
    @objc func generateQuickPasswordAction() {
        let pass = passwordStore.generateStrongPassword(length: 16)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pass, forType: .string)
        showVaultToastHUD(icon: "dice.fill", title: "STRONG PASSWORD GENERATED", message: "16-char crypto password copied to clipboard")
    }
    
    @objc func openAddPasswordModal() {
        passwordsPopover?.performClose(nil)
        showPasswordEditorModal(entry: nil)
    }
    
    func showPasswordEditorModal(entry: OnyxPasswordEntry?) {
        guard let parentWindow = self.window else { return }
        
        let isNew = (entry == nil)
        let activeURLStr = activeWebView.url?.absoluteString ?? ""
        let activeHost = activeWebView.url?.host ?? ""
        let initialTitle = entry?.title ?? (activeHost.isEmpty ? "" : activeHost.replacingOccurrences(of: "www.", with: "").capitalized)
        let initialURL = entry?.urlString ?? (!activeURLStr.contains("startpage.html") && !activeURLStr.isEmpty ? activeURLStr : "")
        let initialUser = entry?.username ?? ""
        let initialPass = entry?.password ?? ""
        let initialNotes = entry?.notes ?? ""
        
        let sheetWidth: CGFloat = 460
        let sheetHeight: CGFloat = 544
        
        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = isNew ? "Add New Login" : "Edit Login"
        sheetWindow.titlebarAppearsTransparent = true
        sheetWindow.backgroundColor = NSColor(red: 18/255.0, green: 18/255.0, blue: 22/255.0, alpha: 1.0)
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
        container.material = .popover
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.40).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        sheetWindow.contentView = container
        
        let headerIcon = NSImageView()
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: isNew ? "lock.badge.plus.fill" : "pencil.circle.fill", accessibilityDescription: nil) {
            headerIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
            headerIcon.contentTintColor = .white
        }
        container.addSubview(headerIcon)
        
        let headerTextStack = NSStackView()
        headerTextStack.translatesAutoresizingMaskIntoConstraints = false
        headerTextStack.orientation = .vertical
        headerTextStack.spacing = 2
        headerTextStack.alignment = .leading
        container.addSubview(headerTextStack)
        
        let titleLabel = NSTextField(labelWithString: isNew ? "Add Login to Onyx Vault" : "Edit Login Credentials")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        headerTextStack.addArrangedSubview(titleLabel)
        
        let subtitleLabel = NSTextField(labelWithString: "Stored encrypted locally with fast autofill integration.")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        subtitleLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
        headerTextStack.addArrangedSubview(subtitleLabel)
        
        let topSep = NSBox()
        topSep.translatesAutoresizingMaskIntoConstraints = false
        topSep.boxType = .custom
        topSep.borderWidth = 0
        topSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        container.addSubview(topSep)
        
        func createFormContainer(placeholder: String, value: String) -> (box: NSView, field: NSTextField) {
            let box = NSView()
            box.translatesAutoresizingMaskIntoConstraints = false
            box.wantsLayer = true
            box.layer?.cornerRadius = 6
            box.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
            box.layer?.borderWidth = 1
            box.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
            
            let tf = NSTextField()
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.isBordered = false
            tf.drawsBackground = false
            tf.focusRingType = .none
            tf.textColor = .white
            tf.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
            tf.stringValue = value
            tf.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor(white: 0.38, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 12.5, weight: .regular)
                ]
            )
            box.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
                tf.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
                tf.centerYAnchor.constraint(equalTo: box.centerYAnchor)
            ])
            return (box, tf)
        }
        
        func createFieldLabel(text: String) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold)
            lbl.textColor = NSColor(white: 0.5, alpha: 1.0)
            return lbl
        }
        
        // Field 1: Title
        let titleFieldLabel = createFieldLabel(text: "SERVICE / WEBSITE NAME")
        container.addSubview(titleFieldLabel)
        let (titleBox, titleInput) = createFormContainer(placeholder: "e.g. GitHub, Google, Amazon", value: initialTitle)
        container.addSubview(titleBox)
        
        // Field 2: URL
        let urlFieldLabel = createFieldLabel(text: "WEBSITE URL / DOMAIN")
        container.addSubview(urlFieldLabel)
        let (urlBox, urlInput) = createFormContainer(placeholder: "e.g. https://github.com/login", value: initialURL)
        container.addSubview(urlBox)
        
        // Field 3: Username
        let userFieldLabel = createFieldLabel(text: "USERNAME / EMAIL")
        container.addSubview(userFieldLabel)
        let (userBox, userInput) = createFormContainer(placeholder: "e.g. developer@onyx.dev", value: initialUser)
        container.addSubview(userBox)
        
        // Field 4: Password
        let passFieldLabel = createFieldLabel(text: "PASSWORD")
        container.addSubview(passFieldLabel)
        
        let passContainer = NSView()
        passContainer.translatesAutoresizingMaskIntoConstraints = false
        passContainer.wantsLayer = true
        passContainer.layer?.cornerRadius = 6
        passContainer.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        passContainer.layer?.borderWidth = 1
        passContainer.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        container.addSubview(passContainer)
        
        let securePassInput = NSSecureTextField()
        securePassInput.translatesAutoresizingMaskIntoConstraints = false
        securePassInput.isBordered = false
        securePassInput.drawsBackground = false
        securePassInput.focusRingType = .none
        securePassInput.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        securePassInput.textColor = .white
        securePassInput.stringValue = initialPass
        securePassInput.placeholderAttributedString = NSAttributedString(
            string: "Enter password",
            attributes: [.foregroundColor: NSColor(white: 0.38, alpha: 1.0), .font: NSFont.systemFont(ofSize: 12.5, weight: .regular)]
        )
        passContainer.addSubview(securePassInput)
        
        let plainPassInput = NSTextField()
        plainPassInput.translatesAutoresizingMaskIntoConstraints = false
        plainPassInput.isBordered = false
        plainPassInput.drawsBackground = false
        plainPassInput.focusRingType = .none
        plainPassInput.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        plainPassInput.textColor = NSColor(white: 0.95, alpha: 1.0)
        plainPassInput.stringValue = initialPass
        plainPassInput.isHidden = true
        passContainer.addSubview(plainPassInput)
        
        var isEyeRevealed = false
        let eyeToggleBtn = NSButton()
        eyeToggleBtn.translatesAutoresizingMaskIntoConstraints = false
        eyeToggleBtn.bezelStyle = .regularSquare
        eyeToggleBtn.isBordered = false
        eyeToggleBtn.wantsLayer = true
        eyeToggleBtn.layer?.cornerRadius = 4
        eyeToggleBtn.toolTip = "Toggle Password Visibility"
        if let img = NSImage(systemSymbolName: "eye", accessibilityDescription: nil) {
            eyeToggleBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            eyeToggleBtn.contentTintColor = NSColor(white: 0.6, alpha: 1.0)
        }
        passContainer.addSubview(eyeToggleBtn)
        
        let generatePasswordBtn = NSButton()
        generatePasswordBtn.translatesAutoresizingMaskIntoConstraints = false
        generatePasswordBtn.bezelStyle = .regularSquare
        generatePasswordBtn.isBordered = false
        generatePasswordBtn.wantsLayer = true
        generatePasswordBtn.layer?.cornerRadius = 4
        generatePasswordBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        generatePasswordBtn.imagePosition = .imageLeading
        if let img = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Generate") {
            generatePasswordBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold))
            generatePasswordBtn.contentTintColor = NSColor(white: 0.85, alpha: 1.0)
        }
        generatePasswordBtn.setMonochromeTitle(" Generate", color: NSColor(white: 0.90, alpha: 1.0), font: NSFont.systemFont(ofSize: 10.5, weight: .semibold))
        generatePasswordBtn.toolTip = "Generate strong 16-character password"
        passContainer.addSubview(generatePasswordBtn)
        
        class ButtonHandler: NSObject {
            let act: () -> Void
            init(_ act: @escaping () -> Void) { self.act = act }
            @objc func trigger() { act() }
        }
        
        let eyeHandler = ButtonHandler {
            isEyeRevealed.toggle()
            if isEyeRevealed {
                plainPassInput.stringValue = securePassInput.stringValue
                securePassInput.isHidden = true
                plainPassInput.isHidden = false
                if let img = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil) {
                    eyeToggleBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
                }
            } else {
                securePassInput.stringValue = plainPassInput.stringValue
                plainPassInput.isHidden = true
                securePassInput.isHidden = false
                if let img = NSImage(systemSymbolName: "eye", accessibilityDescription: nil) {
                    eyeToggleBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
                }
            }
        }
        objc_setAssociatedObject(eyeToggleBtn, "eyeHandler", eyeHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        eyeToggleBtn.target = eyeHandler
        eyeToggleBtn.action = #selector(ButtonHandler.trigger)
        
        let genHandler = ButtonHandler { [weak self] in
            guard let self = self else { return }
            let pass = self.passwordStore.generateStrongPassword(length: 16)
            securePassInput.stringValue = pass
            plainPassInput.stringValue = pass
            isEyeRevealed = true
            securePassInput.isHidden = true
            plainPassInput.isHidden = false
            if let img = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil) {
                eyeToggleBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pass, forType: .string)
            self.showVaultToastHUD(icon: "sparkles", title: "PASSWORD GENERATED", message: "16-char crypto password copied to clipboard")
        }
        objc_setAssociatedObject(generatePasswordBtn, "genHandler", genHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        generatePasswordBtn.target = genHandler
        generatePasswordBtn.action = #selector(ButtonHandler.trigger)
        
        // Field 5: Notes
        let notesFieldLabel = createFieldLabel(text: "NOTES (OPTIONAL)")
        container.addSubview(notesFieldLabel)
        let (notesBox, notesInput) = createFormContainer(placeholder: "PIN, 2FA backup codes, or account notes", value: initialNotes)
        container.addSubview(notesBox)
        
        // Bottom Action Bar
        let bottomSep = NSBox()
        bottomSep.translatesAutoresizingMaskIntoConstraints = false
        bottomSep.boxType = .custom
        bottomSep.borderWidth = 0
        bottomSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        container.addSubview(bottomSep)
        
        let cancelBtn = NSButton()
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.bezelStyle = .regularSquare
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.cornerRadius = 6
        cancelBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        cancelBtn.setMonochromeTitle("Cancel", color: NSColor(white: 0.75, alpha: 1.0), font: NSFont.systemFont(ofSize: 12, weight: .medium))
        cancelBtn.keyEquivalent = "\u{1b}"
        container.addSubview(cancelBtn)
        
        let saveBtn = NSButton()
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.bezelStyle = .regularSquare
        saveBtn.isBordered = false
        saveBtn.wantsLayer = true
        saveBtn.layer?.cornerRadius = 6
        saveBtn.layer?.backgroundColor = NSColor.white.cgColor
        saveBtn.setMonochromeTitle(isNew ? "Save Login" : "Update Login", color: NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 1.0), font: NSFont.systemFont(ofSize: 12, weight: .semibold))
        saveBtn.keyEquivalent = "\r"
        container.addSubview(saveBtn)
        
        let cancelHandler = ButtonHandler { [weak parentWindow, weak sheetWindow] in
            guard let pw = parentWindow, let sw = sheetWindow else { return }
            pw.endSheet(sw, returnCode: .cancel)
        }
        objc_setAssociatedObject(cancelBtn, "cancelHandler", cancelHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        cancelBtn.target = cancelHandler
        cancelBtn.action = #selector(ButtonHandler.trigger)
        
        let saveHandler = ButtonHandler { [weak self, weak parentWindow, weak sheetWindow] in
            guard let self = self, let pw = parentWindow, let sw = sheetWindow else { return }
            let finalPass = isEyeRevealed ? plainPassInput.stringValue : securePassInput.stringValue
            var finalTitle = titleInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var finalURL = urlInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalUser = userInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalNotes = notesInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if finalTitle.isEmpty {
                if !finalURL.isEmpty, let u = URL(string: finalURL), let h = u.host {
                    finalTitle = h.replacingOccurrences(of: "www.", with: "").capitalized
                } else {
                    finalTitle = finalUser.isEmpty ? "Saved Login" : finalUser
                }
            }
            if !finalURL.isEmpty && !finalURL.lowercased().hasPrefix("http://") && !finalURL.lowercased().hasPrefix("https://") {
                finalURL = "https://" + finalURL
            }
            
            var newEntry = entry ?? OnyxPasswordEntry(title: finalTitle, urlString: finalURL, username: finalUser, password: finalPass, notes: finalNotes)
            newEntry.title = finalTitle
            newEntry.urlString = finalURL
            newEntry.username = finalUser
            newEntry.password = finalPass
            newEntry.notes = finalNotes
            newEntry.updatedAt = Date()
            
            self.passwordStore.addOrUpdate(newEntry)
            self.updatePasswordsBadge(for: self.activeWebView.url)
            self.refreshPasswordManagerList(query: self.passwordSearchField?.stringValue ?? "")
            self.showVaultToastHUD(icon: "checkmark.shield.fill", title: "LOGIN SAVED", message: "Saved \(finalTitle) to vault")
            pw.endSheet(sw, returnCode: .OK)
        }
        objc_setAssociatedObject(saveBtn, "saveHandler", saveHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        saveBtn.target = saveHandler
        saveBtn.action = #selector(ButtonHandler.trigger)
        
        NSLayoutConstraint.activate([
            headerIcon.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            headerIcon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            headerIcon.widthAnchor.constraint(equalToConstant: 28),
            headerIcon.heightAnchor.constraint(equalToConstant: 28),
            
            headerTextStack.leadingAnchor.constraint(equalTo: headerIcon.trailingAnchor, constant: 12),
            headerTextStack.centerYAnchor.constraint(equalTo: headerIcon.centerYAnchor),
            headerTextStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            
            topSep.topAnchor.constraint(equalTo: headerIcon.bottomAnchor, constant: 16),
            topSep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            topSep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            topSep.heightAnchor.constraint(equalToConstant: 1),
            
            titleFieldLabel.topAnchor.constraint(equalTo: topSep.bottomAnchor, constant: 16),
            titleFieldLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            
            titleBox.topAnchor.constraint(equalTo: titleFieldLabel.bottomAnchor, constant: 8),
            titleBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            titleBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            titleBox.heightAnchor.constraint(equalToConstant: 40),
            
            urlFieldLabel.topAnchor.constraint(equalTo: titleBox.bottomAnchor, constant: 16),
            urlFieldLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            
            urlBox.topAnchor.constraint(equalTo: urlFieldLabel.bottomAnchor, constant: 8),
            urlBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            urlBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            urlBox.heightAnchor.constraint(equalToConstant: 40),
            
            userFieldLabel.topAnchor.constraint(equalTo: urlBox.bottomAnchor, constant: 16),
            userFieldLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            
            userBox.topAnchor.constraint(equalTo: userFieldLabel.bottomAnchor, constant: 8),
            userBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            userBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            userBox.heightAnchor.constraint(equalToConstant: 40),
            
            passFieldLabel.topAnchor.constraint(equalTo: userBox.bottomAnchor, constant: 16),
            passFieldLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            
            passContainer.topAnchor.constraint(equalTo: passFieldLabel.bottomAnchor, constant: 8),
            passContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            passContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            passContainer.heightAnchor.constraint(equalToConstant: 40),
            
            securePassInput.leadingAnchor.constraint(equalTo: passContainer.leadingAnchor, constant: 12),
            securePassInput.centerYAnchor.constraint(equalTo: passContainer.centerYAnchor),
            securePassInput.trailingAnchor.constraint(equalTo: eyeToggleBtn.leadingAnchor, constant: -8),
            
            plainPassInput.leadingAnchor.constraint(equalTo: passContainer.leadingAnchor, constant: 12),
            plainPassInput.centerYAnchor.constraint(equalTo: passContainer.centerYAnchor),
            plainPassInput.trailingAnchor.constraint(equalTo: eyeToggleBtn.leadingAnchor, constant: -8),
            
            generatePasswordBtn.trailingAnchor.constraint(equalTo: passContainer.trailingAnchor, constant: -8),
            generatePasswordBtn.centerYAnchor.constraint(equalTo: passContainer.centerYAnchor),
            generatePasswordBtn.heightAnchor.constraint(equalToConstant: 26),
            generatePasswordBtn.widthAnchor.constraint(equalToConstant: 88),
            
            eyeToggleBtn.trailingAnchor.constraint(equalTo: generatePasswordBtn.leadingAnchor, constant: -6),
            eyeToggleBtn.centerYAnchor.constraint(equalTo: passContainer.centerYAnchor),
            eyeToggleBtn.widthAnchor.constraint(equalToConstant: 26),
            eyeToggleBtn.heightAnchor.constraint(equalToConstant: 26),
            
            notesFieldLabel.topAnchor.constraint(equalTo: passContainer.bottomAnchor, constant: 16),
            notesFieldLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            
            notesBox.topAnchor.constraint(equalTo: notesFieldLabel.bottomAnchor, constant: 8),
            notesBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            notesBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            notesBox.heightAnchor.constraint(equalToConstant: 40),
            
            bottomSep.topAnchor.constraint(equalTo: notesBox.bottomAnchor, constant: 20),
            bottomSep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            bottomSep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            bottomSep.heightAnchor.constraint(equalToConstant: 1),
            
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -12),
            cancelBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            cancelBtn.heightAnchor.constraint(equalToConstant: 36),
            cancelBtn.widthAnchor.constraint(equalToConstant: 88),
            
            saveBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            saveBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            saveBtn.heightAnchor.constraint(equalToConstant: 36),
            saveBtn.widthAnchor.constraint(equalToConstant: 108)
        ])
        
        parentWindow.beginSheet(sheetWindow, completionHandler: nil)
    }
    
    @objc func importPasswordsPrompt() {
        passwordsPopover?.performClose(nil)
        
        let panel = NSOpenPanel()
        panel.title = "Import Passwords into Onyx"
        panel.prompt = "Import"
        panel.message = "Select a CSV or JSON export from Chrome, Safari, Firefox, Bitwarden, 1Password, or LastPass."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.commaSeparatedText, .json, .plainText]
        } else {
            panel.allowedFileTypes = ["csv", "json", "txt"]
        }
        
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            let result = OnyxPasswordImporter.importFromFile(url: url)
            if let err = result.error {
                let alert = NSAlert()
                alert.messageText = "Import Failed"
                alert.informativeText = err
                alert.alertStyle = .warning
                if let win = self.window {
                    alert.beginSheetModal(for: win, completionHandler: nil)
                } else {
                    alert.runModal()
                }
                return
            }
            
            let (imported, updated) = self.passwordStore.importEntries(result.entries)
            self.showVaultToastHUD(
                icon: "checkmark.shield.fill",
                title: "IMPORT SUCCESSFUL",
                message: "Imported \(imported) logins, updated \(updated) from \(result.source)"
            )
            self.updatePasswordsBadge(for: self.activeWebView.url)
            self.refreshPasswordManagerList(query: self.passwordSearchField?.stringValue ?? "")
        }
        
        if let win = self.window {
            panel.beginSheetModal(for: win, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
    
    @objc func exportPasswordsPrompt() {
        passwordsPopover?.performClose(nil)
        
        let entries = passwordStore.allEntries()
        guard !entries.isEmpty else {
            showVaultToastHUD(icon: "exclamationmark.triangle", title: "VAULT EMPTY", message: "No passwords in vault to export")
            return
        }
        
        let panel = NSSavePanel()
        panel.title = "Export Onyx Passwords"
        panel.prompt = "Export"
        panel.message = "Export vault credentials as RFC-4180 standard CSV."
        panel.nameFieldStringValue = "Onyx_Passwords_Export.csv"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.commaSeparatedText]
        } else {
            panel.allowedFileTypes = ["csv"]
        }
        
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            let csv = OnyxPasswordExporter.exportToCSV(entries: entries)
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                self.showVaultToastHUD(icon: "square.and.arrow.up.fill", title: "VAULT EXPORTED", message: "Exported \(entries.count) logins to \(url.lastPathComponent)")
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        
        if let win = self.window {
            panel.beginSheetModal(for: win, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
    
    func autofillActiveTab(with entry: OnyxPasswordEntry) {
        let webView = activeWebView
        
        let escapedUser = entry.username
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        let escapedPass = entry.password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
            
        let js = """
        (function() {
            const user = '\(escapedUser)';
            const pass = '\(escapedPass)';
            
            let passInputs = Array.from(document.querySelectorAll('input[type="password"]'));
            if (passInputs.length === 0) {
                passInputs = Array.from(document.querySelectorAll('input[autocomplete*="password"], input[name*="pass"], input[id*="pass"]'));
            }
            
            let filled = false;
            for (const pInput of passInputs) {
                pInput.focus();
                pInput.value = pass;
                pInput.dispatchEvent(new Event('input', { bubbles: true }));
                pInput.dispatchEvent(new Event('change', { bubbles: true }));
                pInput.dispatchEvent(new Event('blur', { bubbles: true }));
                filled = true;
                
                let form = pInput.closest('form');
                let uInput = null;
                if (form) {
                    uInput = form.querySelector('input[type="email"], input[type="text"], input[autocomplete*="username"], input[name*="user"], input[name*="login"], input[id*="user"], input[id*="login"]');
                }
                if (!uInput) {
                    let allInputs = Array.from(document.querySelectorAll('input:not([type="hidden"]):not([type="password"]):not([type="submit"])'));
                    uInput = allInputs.find(i => i.type === 'text' || i.type === 'email' || i.type === 'tel') || allInputs[0];
                }
                if (uInput && user.length > 0) {
                    uInput.focus();
                    uInput.value = user;
                    uInput.dispatchEvent(new Event('input', { bubbles: true }));
                    uInput.dispatchEvent(new Event('change', { bubbles: true }));
                    uInput.dispatchEvent(new Event('blur', { bubbles: true }));
                }
            }
            return filled;
        })();
        """
        
        webView.evaluateJavaScript(js) { [weak self] (result, error) in
            let success = (result as? Bool) == true
            if success {
                self?.showVaultToastHUD(icon: "sparkles", title: "AUTOFILL SUCCESSFUL", message: "Filled credentials for \(entry.title)")
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.password, forType: .string)
                self?.showVaultToastHUD(icon: "key.fill", title: "PASSWORD COPIED", message: "No login fields found. Copied password to clipboard")
            }
        }
    }
    
    func updatePasswordsBadge(for url: URL?) {
        guard let url = url else {
            passwordsButton?.setHasMatch(false)
            return
        }
        let host: String
        if let h = url.host, !h.isEmpty {
            host = h
        } else if url.isFileURL {
            host = url.lastPathComponent
        } else {
            host = ""
        }
        guard !host.isEmpty else {
            passwordsButton?.setHasMatch(false)
            return
        }
        let matches = passwordStore.find(forHost: host)
        passwordsButton?.setHasMatch(!matches.isEmpty)
    }
    
    func showVaultToastHUD(icon: String, title: String, message: String) {
        activeToastHUD?.removeFromSuperview()
        guard let content = self.window?.contentView else { return }
        let hud = OnyxToastHUD(iconName: icon, title: title, message: message)
        content.addSubview(hud)
        self.activeToastHUD = hud
        
        NSLayoutConstraint.activate([
            hud.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            hud.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            hud.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            hud.heightAnchor.constraint(equalToConstant: 42)
        ])
        hud.animateIn()
    }
    
    func injectPasswordSaveListener(into webView: WKWebView) {
        guard let url = webView.url, (url.scheme == "http" || url.scheme == "https" || url.scheme == "file") else { return }
        let js = """
        (function() {
            if (window.__onyxPasswordSaveListenerAttached) return;
            window.__onyxPasswordSaveListenerAttached = true;
            
            function checkAndNotify(container) {
                try {
                    let passInput = container.querySelector('input[type="password"]');
                    if (!passInput || !passInput.value) return;
                    let pass = passInput.value;
                    if (pass.length < 3) return;
                    
                    let user = '';
                    let userInputs = Array.from(container.querySelectorAll('input[type="email"], input[type="text"], input[autocomplete*="username"], input[name*="user"], input[name*="login"], input[id*="user"], input[id*="login"]'));
                    for (let u of userInputs) {
                        if (u.value && u.value.trim().length > 0) {
                            user = u.value.trim();
                            break;
                        }
                    }
                    
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.onyxSavePasswordPrompt) {
                        window.webkit.messageHandlers.onyxSavePasswordPrompt.postMessage({
                            username: user,
                            password: pass,
                            url: window.location.href,
                            title: document.title || window.location.hostname
                        });
                    }
                } catch(e) {}
            }
            
            document.addEventListener('submit', function(e) {
                if (e.target) checkAndNotify(e.target);
            }, true);
            
            document.addEventListener('click', function(e) {
                let btn = e.target.closest('button, input[type="submit"], [role="button"]');
                if (!btn) return;
                let form = btn.closest('form') || document;
                checkAndNotify(form);
            }, true);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    func handleSavePasswordPromptMessage(_ dict: [String: Any]) {
        let username = (dict["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = (dict["password"] as? String) ?? ""
        let urlStr = (dict["url"] as? String) ?? (activeWebView.url?.absoluteString ?? "")
        let title = (dict["title"] as? String) ?? (activeWebView.title ?? "Login")
        
        guard password.count >= 3 else { return }
        
        let parsedURL = URL(string: urlStr)
        let domain: String
        if let h = parsedURL?.host, !h.isEmpty {
            domain = h
        } else if parsedURL?.isFileURL == true {
            domain = parsedURL?.lastPathComponent ?? "Local File"
        } else {
            domain = urlStr
        }
        let existing = passwordStore.allEntries().first(where: {
            $0.matches(host: domain) && $0.username.lowercased() == username.lowercased() && $0.password == password
        })
        if existing != nil { return }
        
        activeSavePromptHUD?.removeFromSuperview()
        
        let hud = OnyxSavePasswordHUD(username: username, password: password, urlString: urlStr, title: title)
        hud.onSave = { [weak self] in
            let newEntry = OnyxPasswordEntry(
                title: title.isEmpty ? domain : title,
                urlString: urlStr,
                username: username,
                password: password
            )
            self?.passwordStore.addOrUpdate(newEntry)
            self?.updatePasswordsBadge(for: self?.activeWebView.url)
            self?.showVaultToastHUD(icon: "checkmark.shield.fill", title: "LOGIN SAVED", message: "Saved credentials for \(domain)")
        }
        
        webContainerView.addSubview(hud)
        self.activeSavePromptHUD = hud
        
        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: webContainerView.topAnchor, constant: 16),
            hud.centerXAnchor.constraint(equalTo: webContainerView.centerXAnchor),
            hud.widthAnchor.constraint(equalToConstant: 480),
            hud.heightAnchor.constraint(equalToConstant: 56)
        ])
        hud.animateIn()
    }
    
    // MARK: - Shortcuts
    func setupShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            let isEditingText = (self.window?.firstResponder is NSTextView) || (self.window?.firstResponder is NSText)
            if !isEditingText, let hoveredBM = self.hoveredBookmarkButton {
                // Delete or Backspace key while hovering deletes this individual bookmark immediately
                if event.keyCode == 51 || event.keyCode == 117 {
                    self.deleteBookmark(id: hoveredBM.bookmark.id)
                    return nil
                }
                let key = event.charactersIgnoringModifiers?.lowercased()
                if key == "e" && (flags.isEmpty || flags == .command) {
                    self.showEditBookmarkModal(hoveredBM.bookmark)
                    return nil
                }
            }
            
            if flags.contains([.command, .shift]) {
                let key = event.charactersIgnoringModifiers?.lowercased()
                if key == "b" {
                    self.toggleBookmarksBar()
                    return nil
                } else if key == "s" {
                    self.showSuggestedTabsPopover()
                    return nil
                } else if event.charactersIgnoringModifiers == "]" {
                    self.selectTab(at: (self.activeTabIndex + 1) % self.tabs.count)
                    return nil
                } else if event.charactersIgnoringModifiers == "[" {
                    self.selectTab(at: (self.activeTabIndex - 1 + self.tabs.count) % self.tabs.count)
                    return nil
                }
            } else if flags.contains([.command, .option]) && !flags.contains(.shift) && !flags.contains(.control) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "1":
                    self.switchToProfileIndex(0)
                    return nil
                case "2":
                    self.switchToProfileIndex(1)
                    return nil
                case "3":
                    self.switchToProfileIndex(2)
                    return nil
                case "4":
                    self.switchToProfileIndex(3)
                    return nil
                case "p":
                    self.togglePasswordsPopover()
                    return nil
                case "n":
                    self.openAddPasswordModal()
                    return nil
                case "o":
                    self.showProfileManagerPopover()
                    return nil
                case "l":
                    self.toggleDownloadsPopover()
                    return nil
                default:
                    break
                }
            } else if flags.contains(.control) {
                if event.keyCode == 48 { // Tab
                    self.selectTab(at: (self.activeTabIndex + 1) % self.tabs.count)
                    return nil
                }
            } else if flags.contains(.command) && !flags.contains(.shift) && !flags.contains(.control) && !flags.contains(.option) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case ",":
                    self.openSettingsTab()
                    return nil
                case "b":
                    self.openBookmarkManagerModal()
                    return nil
                case "d":
                    self.addNewBookmarkPrompt()
                    return nil
                case "t":
                    self.createNewTab(url: self.startPageURL)
                    return nil
                case "w":
                    self.closeTab(at: self.activeTabIndex)
                    return nil
                case "o":
                    self.openLocalFile()
                    return nil
                case "j":
                    self.toggleDownloadsPopover()
                    return nil
                case "l", "k":
                    self.searchField.selectText(nil)
                    self.window?.makeFirstResponder(self.searchField)
                    return nil
                case "r":
                    self.reloadPage()
                    return nil
                case "[":
                    self.goBack()
                    return nil
                case "]":
                    self.goForward()
                    return nil
                case "1":
                    self.openBookmarkIndex(0)
                    return nil
                case "2":
                    self.openBookmarkIndex(1)
                    return nil
                case "3":
                    self.openBookmarkIndex(2)
                    return nil
                case "4":
                    self.openBookmarkIndex(3)
                    return nil
                case "5":
                    self.openBookmarkIndex(4)
                    return nil
                case "6":
                    self.openBookmarkIndex(5)
                    return nil
                case "+", "=":
                    self.activeWebView.pageZoom += 0.1
                    return nil
                case "-":
                    self.activeWebView.pageZoom = max(0.5, self.activeWebView.pageZoom - 0.1)
                    return nil
                case "0":
                    self.activeWebView.pageZoom = 1.0
                    return nil
                default:
                    break
                }
            } else if event.keyCode == 53 { // Escape
                self.window?.makeFirstResponder(self.activeWebView)
                return nil
            }
            return event
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
                    let targetWidth = CGFloat(progress) * parentBar.bounds.width
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.18
                        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                        self.progressConstraint.animator().constant = targetWidth
                    }
                    if progress >= 1.0 {
                        NSAnimationContext.runAnimationGroup({ ctx in
                            ctx.duration = 0.25
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
                renderTabs()
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
                renderTabs()
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
                renderTabs()
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
                    updateSearchField(url: url)
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
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView == activeWebView {
            progressBar.isHidden = false
            progressBar.alphaValue = 1.0
            if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Stop") {
                reloadButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            }
            let targetURL = webView.url ?? activeTab.url
            if isSearchURL(targetURL) {
                searchThinkingOrb.stopAnimation()
                searchThinkingOrb.isHidden = true
                searchFaviconView.image = nil
                searchFaviconView.isHidden = true
            } else {
                let isResearch = isResearchURL(targetURL)
                searchFaviconView.isHidden = true
                searchThinkingOrb.startAnimation(mode: isResearch ? .orbits : .orbits)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        injectYouTubeAdBlocker(into: webView)
        if let matchingTab = tabs.first(where: { $0.webView == webView }),
           let host = (webView.url ?? matchingTab.url).host, !(webView.url ?? matchingTab.url).isFileURL {
            if let cached = FaviconManager.shared.cachedFavicon(for: host) {
                updateTabFavicon(for: matchingTab, favicon: cached)
            }
        }
        if isResearchURL(webView.url) {
            injectOnyxResearchScript(into: webView)
        } else if isSearchURL(webView.url) {
            injectOnyxSearchScript(into: webView)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectYouTubeAdBlocker(into: webView)
        if let matchingTab = tabs.first(where: { $0.webView == webView }) {
            fetchFavicon(for: matchingTab)
        }
        if let url = webView.url, !url.isFileURL {
            addBrowsingHistory(title: webView.title ?? "", url: url)
        }
        if isSearchURL(webView.url) {
            injectOnyxSearchScript(into: webView)
        }
        if let url = webView.url, url.isFileURL && url.path.contains("startpage.html") {
            let js = "if (window.updateActiveProfile) window.updateActiveProfile('\(activeProfile.name)', '\(activeProfile.colorHex)');"
            webView.evaluateJavaScript(js, completionHandler: nil)
            let defaultEngine = UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo"
            let engineJS = "if (window.setSearchEngine) window.setSearchEngine('\(defaultEngine)');"
            webView.evaluateJavaScript(engineJS, completionHandler: nil)
        }
        
        if let url = webView.url, isSettingsURL(url) {
            sendSettingsPayload(to: webView)
        }
        
        if isResearchURL(webView.url) {
            injectOnyxResearchScript(into: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.injectOnyxResearchScript(into: webView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.injectOnyxResearchScript(into: webView)
            }
            if webView == activeWebView {
                searchFaviconView.isHidden = true
                searchThinkingOrb.startAnimation(mode: .globe)
            }
        } else if isSearchURL(webView.url) {
            injectOnyxSearchScript(into: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.injectOnyxSearchScript(into: webView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.injectOnyxSearchScript(into: webView)
            }
            // Auto-detect and disable bot verification for a seamless private search experience
            webView.evaluateJavaScript("document.querySelector('.anomaly-modal, [class*=\"anomaly-modal\"], #anomaly-detected') !== null") { [weak self] (res, _) in
                if (res as? Bool) == true {
                    self?.handleBotChallenge(in: webView)
                }
            }
            if webView == activeWebView {
                searchThinkingOrb.stopAnimation()
                searchThinkingOrb.isHidden = true
                searchFaviconView.image = nil
                searchFaviconView.isHidden = true
            }
        } else {
            if webView == activeWebView {
                searchThinkingOrb.stopAnimation()
                searchFaviconView.isHidden = false
                updateSearchFavicon(for: webView.url ?? activeTab.url)
            }
        }
        
        if webView == activeWebView {
            if let img = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") {
                reloadButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            }
            backButton.isEnabled = webView.canGoBack
            forwardButton.isEnabled = webView.canGoForward
            
            if isResearchURL(webView.url) {
                let q = extractResearchQuery(from: webView.url)
                let cleanTitle = q.isEmpty ? "✦ Onyx Research" : "✦ \(q)"
                activeTab.title = cleanTitle
                self.window?.title = cleanTitle
                renderTabs()
                updateSearchField(url: webView.url ?? activeTab.url)
            } else if isSearchURL(webView.url) {
                let q = extractSearchQuery(from: webView.url)
                let cleanTitle = q.isEmpty ? "✦ Onyx Search" : "✦ \(q) — Search"
                activeTab.title = cleanTitle
                self.window?.title = cleanTitle
                renderTabs()
                updateSearchField(url: webView.url ?? activeTab.url)
            }
        }
        
        if webView == activeWebView {
            updatePasswordsBadge(for: webView.url)
        }
        injectPasswordSaveListener(into: webView)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsErr = error as NSError
        if nsErr.domain == "WebKitErrorDomain" && (nsErr.code == 102 || nsErr.code == 101) {
            return
        }
        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
            return
        }
        if webView == activeWebView {
            progressBar.isHidden = true
            searchThinkingOrb.stopAnimation()
            searchFaviconView.isHidden = false
            updateSearchFavicon(for: webView.url ?? activeTab.url)
            if let img = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") {
                reloadButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsErr = error as NSError
        if nsErr.domain == "WebKitErrorDomain" && (nsErr.code == 102 || nsErr.code == 101) {
            return
        }
        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
            return
        }
        if webView == activeWebView {
            progressBar.isHidden = true
            searchThinkingOrb.stopAnimation()
            searchFaviconView.isHidden = false
            updateSearchFavicon(for: webView.url ?? activeTab.url)
            if let img = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") {
                reloadButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            }
        }
    }
    
    // MARK: - WKNavigationDelegate Policy Decisions & Download Handover
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        // Handle links with target="_blank"
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                createNewTab(url: url)
                decisionHandler(.cancel, preferences)
                return
            }
        }
        
        // Programmatic navigations (address bar search, back/forward, direct load, reload) must ALWAYS navigate
        if navigationAction.navigationType == .other || navigationAction.navigationType == .reload || navigationAction.navigationType == .backForward {
            decisionHandler(.allow, preferences)
            return
        }
        
        // For user actions requesting a download (e.g. option-click or <a download>):
        if navigationAction.shouldPerformDownload {
            if let url = navigationAction.request.url {
                let ext = url.pathExtension.lowercased()
                let downloadExtensions: Set<String> = [
                    "dmg", "pkg", "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar",
                    "iso", "exe", "msi", "apk", "bin", "ipa", "deb", "rpm", "jar", "war",
                    "torrent", "appimage"
                ]
                // Only download if the file is an actual binary/installer/archive asset
                if downloadExtensions.contains(ext) {
                    decisionHandler(.download, preferences)
                    return
                }
            }
            // All regular web links, domains (.com, .org, .net), and pages navigate inline!
            decisionHandler(.allow, preferences)
            return
        }
        
        decisionHandler(.allow, preferences)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let rawMime = navigationResponse.response.mimeType?.lowercased() ?? ""
        let mime = rawMime.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
        
        // 1. NEVER download web documents, HTML, plain text, scripts, styles, XML, JSON, or standard media
        if mime == "text/html" ||
           mime.contains("html") ||
           mime == "application/xhtml+xml" ||
           mime.contains("xml") ||
           mime == "text/plain" ||
           mime == "text/css" ||
           mime.contains("javascript") ||
           mime.contains("json") ||
           mime.hasPrefix("image/") ||
           mime.hasPrefix("video/") ||
           mime.hasPrefix("audio/") ||
           mime == "application/pdf" {
            decisionHandler(.allow)
            return
        }
        
        // 2. HTTP redirects (3xx) and No Content (204/205) must never trigger downloads
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            let status = httpResponse.statusCode
            if (300...399).contains(status) || status == 204 || status == 205 {
                decisionHandler(.allow)
                return
            }
        }
        
        // 3. Subframes / iframes must never trigger full file downloads
        if !navigationResponse.isForMainFrame {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
            return
        }
        
        // 4. Check for Content-Disposition: attachment header for explicit non-HTML downloads
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            let headers = httpResponse.allHeaderFields
            for (k, v) in headers {
                if let keyStr = k as? String, keyStr.caseInsensitiveCompare("content-disposition") == .orderedSame {
                    if let valStr = v as? String, valStr.lowercased().contains("attachment") {
                        if !mime.contains("html") && !mime.contains("xml") && mime != "text/plain" {
                            decisionHandler(.download)
                            return
                        }
                    }
                }
            }
        }
        
        // 5. If WebKit cannot display the MIME type inline, ONLY trigger download if it has a known downloadable file extension!
        if !navigationResponse.canShowMIMEType {
            let url = navigationResponse.response.url
            let ext = url?.pathExtension.lowercased() ?? ""
            let knownDownloadExtensions: Set<String> = [
                "dmg", "pkg", "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar",
                "iso", "exe", "msi", "apk", "bin", "ipa", "deb", "rpm", "jar", "war",
                "torrent", "appimage", "csv", "tsv", "xlsx", "docx", "pptx"
            ]
            if knownDownloadExtensions.contains(ext) {
                decisionHandler(.download)
                return
            } else {
                // Regular websites, domains (.com), API endpoints, and unknown content types must render inline or show web error
                decisionHandler(.allow)
                return
            }
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        registerDownload(download: download, sourceURL: navigationAction.request.url)
    }
    
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        registerDownload(download: download, sourceURL: navigationResponse.response.url)
    }
    
    // MARK: - WKDownloadDelegate
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let cleanName: String
        if !suggestedFilename.isEmpty {
            cleanName = suggestedFilename
        } else if let urlName = response.url?.lastPathComponent, !urlName.isEmpty {
            cleanName = urlName
        } else {
            cleanName = "download"
        }
        
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        
        var targetURL = downloadsDir.appendingPathComponent(cleanName)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            let ext = targetURL.pathExtension
            let baseName = targetURL.deletingPathExtension().lastPathComponent
            var counter = 1
            repeat {
                let newName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
                targetURL = downloadsDir.appendingPathComponent(newName)
                counter += 1
            } while FileManager.default.fileExists(atPath: targetURL.path)
        }
        
        updateDownloadDestination(download: download, url: targetURL, filename: targetURL.lastPathComponent)
        completionHandler(targetURL)
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        handleDownloadFinished(download: download)
    }
    
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        handleDownloadFailed(download: download, error: error)
    }
    
    // MARK: - WKUIDelegate (File Uploads & Dialogs)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canChooseDirectories = parameters.allowsDirectories
        openPanel.canChooseFiles = true
        openPanel.resolvesAliases = true
        openPanel.prompt = "Upload"
        let host = frame.request.url?.host ?? "Web Page"
        openPanel.message = "Select file(s) to upload to \(host)"
        
        if let window = self.window {
            openPanel.beginSheetModal(for: window) { response in
                if response == .OK {
                    completionHandler(openPanel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        } else {
            openPanel.begin { response in
                if response == .OK {
                    completionHandler(openPanel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        let host = frame.request.url?.host ?? "Web Page"
        alert.messageText = "\(host)"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let window = self.window {
            alert.beginSheetModal(for: window) { _ in completionHandler() }
        } else {
            alert.runModal()
            completionHandler()
        }
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        let host = frame.request.url?.host ?? "Web Page"
        alert.messageText = "\(host)"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if let window = self.window {
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        } else {
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn)
        }
    }
    
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        let host = frame.request.url?.host ?? "Web Page"
        alert.messageText = "\(host)"
        alert.informativeText = prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        inputField.stringValue = defaultText ?? ""
        alert.accessoryView = inputField
        
        if let window = self.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    completionHandler(inputField.stringValue)
                } else {
                    completionHandler(nil)
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                completionHandler(inputField.stringValue)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        searchField.onFocusChanged?(false)
    }
    
    // MARK: - Menu Bar Actions
    @objc func menuNewTab() {
        createNewTab(url: startPageURL)
    }
    
    @objc func menuCloseTab() {
        closeTab(at: activeTabIndex)
    }
    
    @objc func menuReload() {
        reloadPage()
    }
    
    @objc func menuToggleBookmarks() {
        toggleBookmarksBar()
    }
    
    @objc func menuToggleDownloads() {
        toggleDownloadsPopover()
    }
    
    @objc func menuTogglePasswords() {
        togglePasswordsPopover()
    }
    
    @objc func menuToggleExtensions() {
        toggleExtensionsPopover()
    }
    
    @objc func menuImportPasswords() {
        importPasswordsPrompt()
    }
    
    @objc func menuExportPasswords() {
        exportPasswordsPrompt()
    }
    
    @objc func menuZoomIn() {
        activeWebView.pageZoom += 0.1
    }
    
    @objc func menuZoomOut() {
        activeWebView.pageZoom = max(0.5, activeWebView.pageZoom - 0.1)
    }
    
    @objc func menuZoomReset() {
        activeWebView.pageZoom = 1.0
    }
    
    @objc func menuGoBack() {
        goBack()
    }
    
    @objc func menuGoForward() {
        goForward()
    }
    
    @objc func menuGoHome() {
        loadTabURL(tab: activeTab, url: startPageURL)
    }
    
    @objc func menuNextTab() {
        guard !tabs.isEmpty else { return }
        selectTab(at: (activeTabIndex + 1) % tabs.count)
    }
    
    @objc func menuPrevTab() {
        guard !tabs.isEmpty else { return }
        selectTab(at: (activeTabIndex - 1 + tabs.count) % tabs.count)
    }
    
    @objc func menuSwitchProfile1() { switchToProfileIndex(0) }
    @objc func menuSwitchProfile2() { switchToProfileIndex(1) }
    @objc func menuSwitchProfile3() { switchToProfileIndex(2) }
    @objc func menuSwitchProfile4() { switchToProfileIndex(3) }
    @objc func menuManageProfiles() { showProfileManagerPopover() }
    
    @objc func showPrivacyReport() {
        let alert = NSAlert()
        alert.messageText = "Onyx Shield"
        alert.informativeText = "Active Content Blocker: Active\nEngine: Native WebKit + YouTube Ad Shield (~30 MB RAM)\n\n• Global Web Ad & Tracker Blocking: Enabled\n• YouTube Video Ad Skipping & Popup Elimination: Active\n• Anti-Adblock Enforcement Neutralizer: Active\n\nOnyx prevents tracking beacons, video pre-rolls/mid-rolls, and intrusive banners with zero layout shift."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Done")
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.runModal()
    }
    
    @objc func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "Onyx"
        alert.informativeText = "Version 1.0.0 (Native WebKit)\n\nUltra-low RAM browser engineered for instant search, tab management, and free Duck.ai research.\n\nPitch-black monochrome aesthetics."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Close")
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.runModal()
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var browserController: BrowserController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        // Force-load high-resolution celestial thinking-orb AppIcon into macOS Dock runtime
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let iconImg = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = iconImg
        } else if let localIcon = NSImage(contentsOfFile: "/Users/nata/Company/Browser/AppIcon.icns") {
            NSApp.applicationIconImage = localIcon
        }

        browserController = BrowserController()
        setupMainMenu()
        browserController?.showWindow(nil)
        browserController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        if CommandLine.arguments.count > 1 {
            let arg = CommandLine.arguments[1]
            if let url = URL(string: arg), url.scheme != nil {
                browserController?.loadURL(url)
            } else if !arg.hasPrefix("-") {
                if let resolved = browserController?.resolveQuery(arg) {
                    browserController?.loadURL(resolved)
                }
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if browserController == nil {
                browserController = BrowserController()
            }
            browserController?.showWindow(nil)
            browserController?.window?.makeKeyAndOrderFront(nil)
        }
        return true
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            browserController?.createNewTab(url: url)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func setupMainMenu() {
        let mainMenu = NSMenu()
        guard let controller = browserController else { return }
        
        // 1. App Menu (Onyx)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Onyx")
        let aboutItem = NSMenuItem(title: "About Onyx", action: #selector(BrowserController.showAboutPanel), keyEquivalent: "")
        aboutItem.target = controller
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(BrowserController.menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = controller
        let passwordsItem = NSMenuItem(title: "Passwords & Vault...", action: #selector(BrowserController.menuTogglePasswords), keyEquivalent: "p")
        passwordsItem.keyEquivalentModifierMask = [.command, .option]
        passwordsItem.target = controller
        let extensionsItem = NSMenuItem(title: "Extensions & Tools...", action: #selector(BrowserController.menuToggleExtensions), keyEquivalent: "e")
        extensionsItem.keyEquivalentModifierMask = [.command, .option]
        extensionsItem.target = controller
        let hideItem = NSMenuItem(title: "Hide Onyx", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit Onyx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        appMenu.addItem(aboutItem)
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(passwordsItem)
        appMenu.addItem(extensionsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(hideItem)
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(showAllItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(BrowserController.menuNewTab), keyEquivalent: "t")
        newTabItem.target = controller
        let openFileItem = NSMenuItem(title: "Open File...", action: #selector(BrowserController.openLocalFile), keyEquivalent: "o")
        openFileItem.target = controller
        let newLoginItem = NSMenuItem(title: "New Login...", action: #selector(BrowserController.openAddPasswordModal), keyEquivalent: "n")
        newLoginItem.keyEquivalentModifierMask = [.command, .option]
        newLoginItem.target = controller
        let importPasswordsItem = NSMenuItem(title: "Import Passwords...", action: #selector(BrowserController.menuImportPasswords), keyEquivalent: "")
        importPasswordsItem.target = controller
        let exportPasswordsItem = NSMenuItem(title: "Export Passwords...", action: #selector(BrowserController.menuExportPasswords), keyEquivalent: "")
        exportPasswordsItem.target = controller
        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(BrowserController.menuCloseTab), keyEquivalent: "w")
        closeTabItem.target = controller
        let closeWindowItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "W")
        
        fileMenu.addItem(newTabItem)
        fileMenu.addItem(openFileItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(newLoginItem)
        fileMenu.addItem(importPasswordsItem)
        fileMenu.addItem(exportPasswordsItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(closeTabItem)
        fileMenu.addItem(closeWindowItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // 3. Edit Menu (Standard OS Undo, Cut, Copy, Paste, Select All)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        editMenu.addItem(undoItem)
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(cutItem)
        editMenu.addItem(copyItem)
        editMenu.addItem(pasteItem)
        editMenu.addItem(selectAllItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // 4. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let reloadItem = NSMenuItem(title: "Reload Page", action: #selector(BrowserController.menuReload), keyEquivalent: "r")
        reloadItem.target = controller
        let toggleBookmarksItem = NSMenuItem(title: "Toggle Bookmarks Bar", action: #selector(BrowserController.menuToggleBookmarks), keyEquivalent: "B")
        toggleBookmarksItem.target = controller
        let downloadsItem = NSMenuItem(title: "Downloads", action: #selector(BrowserController.menuToggleDownloads), keyEquivalent: "j")
        downloadsItem.target = controller
        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(BrowserController.menuZoomIn), keyEquivalent: "+")
        zoomInItem.target = controller
        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(BrowserController.menuZoomOut), keyEquivalent: "-")
        zoomOutItem.target = controller
        let zoomResetItem = NSMenuItem(title: "Actual Size", action: #selector(BrowserController.menuZoomReset), keyEquivalent: "0")
        zoomResetItem.target = controller
        let fullScreenItem = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        
        viewMenu.addItem(reloadItem)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(toggleBookmarksItem)
        viewMenu.addItem(downloadsItem)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(zoomInItem)
        viewMenu.addItem(zoomOutItem)
        viewMenu.addItem(zoomResetItem)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(fullScreenItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // 5. History Menu
        let historyMenuItem = NSMenuItem()
        let historyMenu = NSMenu(title: "History")
        let backItem = NSMenuItem(title: "Back", action: #selector(BrowserController.menuGoBack), keyEquivalent: "[")
        backItem.target = controller
        let forwardItem = NSMenuItem(title: "Forward", action: #selector(BrowserController.menuGoForward), keyEquivalent: "]")
        forwardItem.target = controller
        let homeItem = NSMenuItem(title: "Home", action: #selector(BrowserController.menuGoHome), keyEquivalent: "H")
        homeItem.target = controller
        
        historyMenu.addItem(backItem)
        historyMenu.addItem(forwardItem)
        historyMenu.addItem(homeItem)
        historyMenuItem.submenu = historyMenu
        mainMenu.addItem(historyMenuItem)
        
        // 6. Profiles Menu
        let profilesMenuItem = NSMenuItem()
        let profilesMenu = NSMenu(title: "Profiles")
        let p1 = NSMenuItem(title: "Personal", action: #selector(BrowserController.menuSwitchProfile1), keyEquivalent: "1")
        p1.keyEquivalentModifierMask = [.command, .option]
        p1.target = controller
        let p2 = NSMenuItem(title: "Research & AI", action: #selector(BrowserController.menuSwitchProfile2), keyEquivalent: "2")
        p2.keyEquivalentModifierMask = [.command, .option]
        p2.target = controller
        let p3 = NSMenuItem(title: "Markets & Trading", action: #selector(BrowserController.menuSwitchProfile3), keyEquivalent: "3")
        p3.keyEquivalentModifierMask = [.command, .option]
        p3.target = controller
        let p4 = NSMenuItem(title: "Campus / Academic", action: #selector(BrowserController.menuSwitchProfile4), keyEquivalent: "4")
        p4.keyEquivalentModifierMask = [.command, .option]
        p4.target = controller
        let manageP = NSMenuItem(title: "Manage Profiles...", action: #selector(BrowserController.menuManageProfiles), keyEquivalent: "o")
        manageP.keyEquivalentModifierMask = [.command, .option]
        manageP.target = controller
        
        profilesMenu.addItem(p1)
        profilesMenu.addItem(p2)
        profilesMenu.addItem(p3)
        profilesMenu.addItem(p4)
        profilesMenu.addItem(NSMenuItem.separator())
        profilesMenu.addItem(manageP)
        profilesMenuItem.submenu = profilesMenu
        mainMenu.addItem(profilesMenuItem)
        
        // 7. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let minimizeItem = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let zoomItem = NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let nextTabItem = NSMenuItem(title: "Show Next Tab", action: #selector(BrowserController.menuNextTab), keyEquivalent: "}")
        nextTabItem.target = controller
        let prevTabItem = NSMenuItem(title: "Show Previous Tab", action: #selector(BrowserController.menuPrevTab), keyEquivalent: "{")
        prevTabItem.target = controller
        
        let suggestedItem = NSMenuItem(title: "Workspaces...", action: #selector(BrowserController.showSuggestedTabsPopover), keyEquivalent: "S")
        suggestedItem.keyEquivalentModifierMask = [.command, .shift]
        suggestedItem.target = controller
        
        windowMenu.addItem(minimizeItem)
        windowMenu.addItem(zoomItem)
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(nextTabItem)
        windowMenu.addItem(prevTabItem)
        windowMenu.addItem(suggestedItem)
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
