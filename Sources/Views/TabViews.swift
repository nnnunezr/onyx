import Cocoa
import WebKit
import UniformTypeIdentifiers

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
            Motion.prepare(ctx)
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
            self.contentTintColor = NSColor.white
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            Motion.prepare(ctx)
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
            // Width is set by BrowserController.layoutTabStrip(). A required minimum here (it was
            // 110 pt) made every extra tab push the window wider than the screen.
            
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
    
    var titleText: String { titleLabel.stringValue }
    
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
            Motion.prepare(ctx)
            self.updateAppearance()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
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
            Motion.prepare(ctx)
            self.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.985, y: 0.985))
        }
        onSelect?(tab)
    }
    
    override func mouseUp(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
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

// MARK: - Tab strip scroll view
/// Horizontal-only scroller for the tab row. A mouse wheel (vertical) scrolls it sideways, as
/// in Safari and Chrome; trackpad swipes work natively.
final class TabStripScrollView: NSScrollView {
    /// In the transparent titlebar, a click on a view that can move the window becomes a window
    /// drag. The scroll view answered hit tests for the whole tab row, so clicks on tabs and their
    /// close buttons dragged the window instead (tabs could not be closed). Route hits to the tabs;
    /// the empty bar around the row still drags the window.
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let doc = documentView, !isHidden else { return super.hitTest(point) }
        let inClip = contentView.convert(point, from: superview)
        if contentView.bounds.contains(inClip), let hit = doc.hitTest(contentView.convert(inClip, to: doc.superview)) {
            return hit
        }
        return super.hitTest(point)
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              let doc = documentView else {
            return super.scrollWheel(with: event)
        }
        let clip = contentView
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        var origin = clip.bounds.origin
        origin.x = max(0, min(origin.x - step, doc.frame.width - clip.bounds.width))
        clip.setBoundsOrigin(origin)
        reflectScrolledClipView(clip)
    }
}
