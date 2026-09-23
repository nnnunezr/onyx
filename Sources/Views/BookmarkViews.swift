import Cocoa
import WebKit
import UniformTypeIdentifiers

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
