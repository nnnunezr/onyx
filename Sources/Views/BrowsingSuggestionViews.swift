import Cocoa
import WebKit
import UniformTypeIdentifiers

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
