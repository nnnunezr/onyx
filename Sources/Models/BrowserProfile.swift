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

extension BrowserProfile {
    private enum CodingKeys: String, CodingKey { case id, name, iconName, colorHex, isDefault }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Workspace"
        iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "person.crop.circle"
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#FFFFFF"
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}
