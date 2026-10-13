import Cocoa
import WebKit
import UniformTypeIdentifiers

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
            Motion.prepare(ctx)
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
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
            Motion.prepare(ctx)
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
            self.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
