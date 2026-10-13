import Cocoa

// MARK: - Find in Page bar
/// Floating bar over the top-right of the page (⌘F). Return = next, Shift-Return = previous,
/// Escape closes. The controller does the searching; this view only reports input.
final class OnyxFindBar: NSView, NSSearchFieldDelegate {
    let field = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    var onSearch: ((_ text: String, _ backwards: Bool, _ isNewQuery: Bool) -> Void)?
    var onClose: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let blur = NSVisualEffectView()
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.material = .popover
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        addSubview(blur)

        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = "Find in page"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = self
        field.target = self
        field.action = #selector(fieldChanged)
        field.focusRingType = .default

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = NSColor(white: 0.62, alpha: 1)
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        let prev = NavIconButton(iconName: "chevron.up", tooltip: "Previous Match (⇧⌘G)", target: self, action: #selector(prevClicked))
        let next = NavIconButton(iconName: "chevron.down", tooltip: "Next Match (⌘G)", target: self, action: #selector(nextClicked))
        let close = NavIconButton(iconName: "xmark", tooltip: "Close (Esc)", target: self, action: #selector(closeClicked))

        let row = NSStackView(views: [field, countLabel, prev, next, close])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 4
        row.setCustomSpacing(8, after: field)
        row.setCustomSpacing(8, after: countLabel)
        blur.addSubview(row)

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 44),
            widthAnchor.constraint(equalToConstant: 360),
            row.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setStatus(_ text: String, notFound: Bool) {
        countLabel.stringValue = text
        countLabel.textColor = notFound ? NSColor.systemRed.withAlphaComponent(0.9) : NSColor(white: 0.62, alpha: 1)
    }

    @objc private func fieldChanged() { onSearch?(field.stringValue, false, true) }
    @objc private func prevClicked() { onSearch?(field.stringValue, true, false) }
    @objc private func nextClicked() { onSearch?(field.stringValue, false, false) }
    @objc private func closeClicked() { onClose?() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            onSearch?(field.stringValue, backwards, false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }
}
