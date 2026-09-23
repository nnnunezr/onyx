import Cocoa
import WebKit
import UniformTypeIdentifiers

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
