import Cocoa
import WebKit
import UniformTypeIdentifiers

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
            Motion.prepare(ctx)
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            self.contentTintColor = NSColor.white
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.contentTintColor = self.isEnabled ? NSColor(white: 0.82, alpha: 1.0) : NSColor(white: 0.35, alpha: 1.0)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        // Press feedback: a quick centered dip that springs back.
        if isEnabled {
            Motion.centerScale(layer, scales: [1.0, 0.94, 1.02, 1.0], keyTimes: [0, 0.35, 0.75, 1.0], duration: 0.22,
                               timing: CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.5, 1.0), key: "press")
        }
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
