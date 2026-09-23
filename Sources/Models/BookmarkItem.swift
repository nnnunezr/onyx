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
