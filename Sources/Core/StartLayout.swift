import Foundation

// MARK: - Start page layout
/// What the start page sends to be saved: the order of its Workspaces / News tabs and the
/// editable workspace cards. Foundation-only so it can be unit-tested outside the app (tests/run.sh).
/// The page validates too; this is the second check, because the message is a bridge call.
enum StartLayout {
    static let deckTabs = ["workspaces", "news"]
    static let maxCards = 12

    /// Clean JSON bytes ready to store, or nil when `raw` is not a layout dictionary.
    /// Cards with a missing name or a non-http(s) address are dropped, not repaired.
    static func sanitizedJSON(_ raw: Any?) -> Data? {
        guard let dict = raw as? [String: Any] else { return nil }

        var order: [String] = []
        for case let key as String in dict["order"] as? [Any] ?? [] where deckTabs.contains(key) && !order.contains(key) {
            order.append(key)
        }

        var cards: [[String: String]] = []
        for case let card as [String: Any] in (dict["workspaces"] as? [Any] ?? []).prefix(maxCards) {
            guard let id = card["id"] as? String, !id.isEmpty, id.count <= 24,
                  let title = (card["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let url = (card["url"] as? String).flatMap({ URL(string: $0) }),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { continue }
            let desc = ((card["desc"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            cards.append(["id": id, "title": String(title.prefix(40)), "desc": String(desc.prefix(60)), "url": url.absoluteString])
        }
        return try? JSONSerialization.data(withJSONObject: ["order": order, "workspaces": cards])
    }
}
