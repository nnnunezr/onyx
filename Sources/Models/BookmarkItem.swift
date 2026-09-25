import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Bookmark Model
struct BookmarkItem: Codable, Equatable {
    var id: String
    var title: String
    var shortcut: String
    var urlString: String
    var domain: String
    var iconName: String
    
    init(id: String = UUID().uuidString, title: String, shortcut: String = "", urlString: String, domain: String = "", iconName: String = "globe") {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.urlString = urlString
        if domain.isEmpty, let host = URL(string: urlString)?.host {
            self.domain = host
        } else {
            self.domain = domain
        }
        self.iconName = iconName
    }
}

extension BookmarkItem {
    private enum CodingKeys: String, CodingKey { case id, title, shortcut, urlString, domain, iconName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let url = try c.decode(String.self, forKey: .urlString)
        self.init(
            id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? url,
            shortcut: try c.decodeIfPresent(String.self, forKey: .shortcut) ?? "",
            urlString: url,
            domain: try c.decodeIfPresent(String.self, forKey: .domain) ?? "",
            iconName: try c.decodeIfPresent(String.self, forKey: .iconName) ?? "globe"
        )
    }
}
