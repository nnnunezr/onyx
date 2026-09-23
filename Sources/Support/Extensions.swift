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
