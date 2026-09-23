import Cocoa
import WebKit
import UniformTypeIdentifiers

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
