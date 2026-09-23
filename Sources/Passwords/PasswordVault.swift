import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Onyx Password Vault & Password Importer Engine
struct OnyxPasswordEntry: Codable, Identifiable {
    var id: UUID
    var title: String
    var urlString: String
    var username: String
    var password: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        username: String,
        password: String,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.username = username
        self.password = password
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var domain: String {
        let cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: cleaned), let host = u.host, !host.isEmpty {
            return host.lowercased()
        }
        if let u = URL(string: "https://" + cleaned), let host = u.host, !host.isEmpty {
            return host.lowercased()
        }
        return cleaned.lowercased()
    }
    
    func matches(host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let d = domain.lowercased()
        guard !h.isEmpty && !d.isEmpty else { return false }
        if h == d { return true }
        if h.hasSuffix("." + d) || d.hasSuffix("." + h) { return true }
        let cleanH = h.replacingOccurrences(of: "www.", with: "")
        let cleanD = d.replacingOccurrences(of: "www.", with: "")
        return cleanH == cleanD || cleanH.contains(cleanD) || cleanD.contains(cleanH)
    }
    
    func matchesQuery(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return title.lowercased().contains(q) ||
               username.lowercased().contains(q) ||
               domain.lowercased().contains(q) ||
               urlString.lowercased().contains(q) ||
               notes.lowercased().contains(q)
    }
}

// Robust RFC-4180 CSV Parser (Handles quoted fields, escaped quotes, multiline values, and BOM)
class OnyxCSVParser {
    static func parse(text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        var chars = Array(text)
        var i = 0
        
        if chars.first == "\u{FEFF}" {
            chars.removeFirst()
        }
        
        while i < chars.count {
            let c = chars[i]
            if insideQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(c)
                }
            } else {
                if c == "\"" {
                    insideQuotes = true
                } else if c == "," {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                } else if c == "\r" {
                    if i + 1 < chars.count && chars[i + 1] == "\n" {
                        i += 1
                    }
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    currentField = ""
                } else if c == "\n" {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    currentField = ""
                } else {
                    currentField.append(c)
                }
            }
            i += 1
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }
        return rows
    }
}

// Multi-Source Password Importer Engine (Chrome, Safari, Firefox, 1Password, Bitwarden, LastPass, Generic CSV/JSON)
class OnyxPasswordImporter {
    struct ImportResult {
        let entries: [OnyxPasswordEntry]
        let source: String
        let error: String?
    }
    
    static func importFromFile(url: URL) -> ImportResult {
        guard let data = try? Data(contentsOf: url) else {
            return ImportResult(entries: [], source: url.lastPathComponent, error: "Unable to read file.")
        }
        
        // Try UTF-8 then ISO Latin 1 fallback
        let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        guard !content.isEmpty else {
            return ImportResult(entries: [], source: url.lastPathComponent, error: "File content is empty or unreadable.")
        }
        
        let ext = url.pathExtension.lowercased()
        if ext == "json" || content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            let entries = parseJSON(content: content)
            if !entries.isEmpty {
                return ImportResult(entries: entries, source: "Bitwarden / JSON Vault", error: nil)
            }
        }
        
        let (entries, detectedSource) = parseCSVWithDetection(content: content, filename: url.lastPathComponent)
        if entries.isEmpty {
            return ImportResult(entries: [], source: url.lastPathComponent, error: "No valid login credentials found in file.")
        }
        return ImportResult(entries: entries, source: detectedSource, error: nil)
    }
    
    static func parseCSVWithDetection(content: String, filename: String) -> (entries: [OnyxPasswordEntry], source: String) {
        let rows = OnyxCSVParser.parse(text: content)
        guard rows.count > 1 else { return ([], filename) }
        
        let headerRow = rows[0].map { $0.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "") }
        
        // Identify column mappings
        var nameIdx = -1
        var urlIdx = -1
        var userIdx = -1
        var passIdx = -1
        var notesIdx = -1
        
        for (i, h) in headerRow.enumerated() {
            if nameIdx == -1 && (h == "name" || h == "title" || h == "sitename" || h == "site" || h == "service") {
                nameIdx = i
            } else if urlIdx == -1 && (h == "url" || h == "loginuri" || h == "loginurl" || h == "website" || h == "uri" || h == "address" || h == "httprealm") {
                urlIdx = i
            } else if userIdx == -1 && (h == "username" || h == "user" || h == "loginusername" || h == "login" || h == "email" || h == "account" || h == "user_name") {
                userIdx = i
            } else if passIdx == -1 && (h == "password" || h == "loginpassword" || h == "pass" || h == "pwd" || h == "secret") {
                passIdx = i
            } else if notesIdx == -1 && (h == "notes" || h == "note" || h == "comment" || h == "comments" || h == "extra") {
                notesIdx = i
            }
        }
        
        // Determine source description
        var sourceDesc = "CSV File"
        if headerRow.contains("otpauth") {
            sourceDesc = "Apple Safari Passwords"
        } else if headerRow.contains("loginuri") || headerRow.contains("loginpassword") {
            sourceDesc = "Bitwarden CSV"
        } else if headerRow.contains("httprealm") {
            sourceDesc = "Mozilla Firefox"
        } else if headerRow.contains("grouping") || headerRow.contains("fav") {
            sourceDesc = "LastPass CSV"
        } else if headerRow.contains("name") && headerRow.contains("url") && headerRow.contains("username") {
            sourceDesc = "Google Chrome / Chromium"
        }
        
        guard passIdx != -1 else { return ([], sourceDesc) }
        
        var results: [OnyxPasswordEntry] = []
        for row in rows.dropFirst() {
            guard passIdx < row.count else { continue }
            let pass = row[passIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pass.isEmpty else { continue }
            
            let title = (nameIdx != -1 && nameIdx < row.count) ? row[nameIdx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let urlStr = (urlIdx != -1 && urlIdx < row.count) ? row[urlIdx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let user = (userIdx != -1 && userIdx < row.count) ? row[userIdx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let notes = (notesIdx != -1 && notesIdx < row.count) ? row[notesIdx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            
            var displayTitle = title
            if displayTitle.isEmpty {
                if let u = URL(string: urlStr), let host = u.host, !host.isEmpty {
                    displayTitle = host.replacingOccurrences(of: "www.", with: "").capitalized
                } else if !urlStr.isEmpty {
                    displayTitle = urlStr
                } else {
                    displayTitle = user.isEmpty ? "Saved Login" : user
                }
            }
            
            var finalURL = urlStr
            if !finalURL.isEmpty && !finalURL.lowercased().hasPrefix("http://") && !finalURL.lowercased().hasPrefix("https://") {
                finalURL = "https://" + finalURL
            }
            
            let entry = OnyxPasswordEntry(
                title: displayTitle,
                urlString: finalURL,
                username: user,
                password: pass,
                notes: notes
            )
            results.append(entry)
        }
        
        return (results, sourceDesc)
    }
    
    static func parseJSON(content: String) -> [OnyxPasswordEntry] {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            // Check if top-level array of objects
            if let data = content.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                var list: [OnyxPasswordEntry] = []
                for item in array {
                    let title = (item["title"] ?? item["name"] ?? item["site"]) as? String ?? "Login"
                    let urlStr = (item["url"] ?? item["uri"] ?? item["urlString"]) as? String ?? ""
                    let user = (item["username"] ?? item["user"] ?? item["email"]) as? String ?? ""
                    let pass = (item["password"] ?? item["pass"]) as? String ?? ""
                    let notes = (item["notes"] ?? item["note"]) as? String ?? ""
                    if !pass.isEmpty {
                        list.append(OnyxPasswordEntry(title: title, urlString: urlStr, username: user, password: pass, notes: notes))
                    }
                }
                return list
            }
            return []
        }
        
        var results: [OnyxPasswordEntry] = []
        // Bitwarden format: { "items": [ { "name": "...", "login": { "uris": [...], "username": "...", "password": "..." }, "notes": "..." } ] }
        if let items = json["items"] as? [[String: Any]] {
            for item in items {
                let name = item["name"] as? String ?? "Login"
                let notes = item["notes"] as? String ?? ""
                if let login = item["login"] as? [String: Any] {
                    let user = login["username"] as? String ?? ""
                    let pass = login["password"] as? String ?? ""
                    var urlStr = ""
                    if let uris = login["uris"] as? [[String: Any]], let first = uris.first, let u = first["uri"] as? String {
                        urlStr = u
                    }
                    if !pass.isEmpty {
                        results.append(OnyxPasswordEntry(title: name, urlString: urlStr, username: user, password: pass, notes: notes))
                    }
                }
            }
        }
        return results
    }
}

// RFC-4180 CSV Exporter
class OnyxPasswordExporter {
    static func exportToCSV(entries: [OnyxPasswordEntry]) -> String {
        var csv = "title,url,username,password,notes\n"
        for e in entries {
            let row = [escapeCSV(e.title), escapeCSV(e.urlString), escapeCSV(e.username), escapeCSV(e.password), escapeCSV(e.notes)]
            csv.append(row.joined(separator: ",") + "\n")
        }
        return csv
    }
    
    private static func escapeCSV(_ str: String) -> String {
        if str.contains(",") || str.contains("\"") || str.contains("\n") || str.contains("\r") {
            let escaped = str.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return str
    }
}

// Persistent Vault Store (UserDefaults + ~/Library/Application Support/Onyx/passwords.json backup)
class OnyxPasswordStore {
    static let shared = OnyxPasswordStore()
    private let defaultsKey = "OnyxVaultPasswords"
    private var entries: [OnyxPasswordEntry] = []
    
    private var diskURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("Onyx")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("passwords.json")
    }
    
    init() {
        load()
    }
    
    func allEntries() -> [OnyxPasswordEntry] {
        return entries
    }
    
    func filteredEntries(query: String) -> [OnyxPasswordEntry] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entries
        }
        return entries.filter { $0.matchesQuery(query) }
    }
    
    func find(forHost host: String) -> [OnyxPasswordEntry] {
        guard !host.isEmpty else { return [] }
        return entries.filter { $0.matches(host: host) }
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let list = try? JSONDecoder().decode([OnyxPasswordEntry].self, from: data) {
            self.entries = list
            return
        }
        if let data = try? Data(contentsOf: diskURL),
           let list = try? JSONDecoder().decode([OnyxPasswordEntry].self, from: data) {
            self.entries = list
            save()
            return
        }
        // Default clean vault state with helpful initial bookmarks/examples
        self.entries = [
            OnyxPasswordEntry(title: "GitHub", urlString: "https://github.com/login", username: "developer@onyx.dev", password: "••••••••••••", notes: "Personal developer account"),
            OnyxPasswordEntry(title: "Google", urlString: "https://accounts.google.com", username: "user@gmail.com", password: "••••••••••••", notes: "Primary Google Workspace"),
            OnyxPasswordEntry(title: "TradingView", urlString: "https://www.tradingview.com", username: "trader_onyx", password: "••••••••••••", notes: "Market charting login")
        ]
        save()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
            try? data.write(to: diskURL, options: .atomic)
        }
    }
    
    func addOrUpdate(_ entry: OnyxPasswordEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
            entries[idx].updatedAt = Date()
        } else if let idx = entries.firstIndex(where: { $0.domain == entry.domain && $0.username.lowercased() == entry.username.lowercased() && !entry.username.isEmpty }) {
            entries[idx].password = entry.password
            if !entry.title.isEmpty { entries[idx].title = entry.title }
            if !entry.urlString.isEmpty { entries[idx].urlString = entry.urlString }
            if !entry.notes.isEmpty { entries[idx].notes = entry.notes }
            entries[idx].updatedAt = Date()
        } else {
            entries.insert(entry, at: 0)
        }
        save()
    }
    
    func delete(id: UUID) {
        entries.removeAll(where: { $0.id == id })
        save()
    }
    
    func importEntries(_ newEntries: [OnyxPasswordEntry]) -> (imported: Int, updated: Int) {
        var importedCount = 0
        var updatedCount = 0
        for entry in newEntries {
            guard !entry.password.isEmpty else { continue }
            if let idx = entries.firstIndex(where: { $0.domain == entry.domain && $0.username.lowercased() == entry.username.lowercased() && !entry.username.isEmpty }) {
                entries[idx].password = entry.password
                if !entry.title.isEmpty { entries[idx].title = entry.title }
                if !entry.urlString.isEmpty { entries[idx].urlString = entry.urlString }
                if !entry.notes.isEmpty { entries[idx].notes = entry.notes }
                entries[idx].updatedAt = Date()
                updatedCount += 1
            } else {
                entries.append(entry)
                importedCount += 1
            }
        }
        save()
        return (importedCount, updatedCount)
    }
    
    func generateStrongPassword(length: Int = 16) -> String {
        let upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        let lower = "abcdefghijkmnopqrstuvwxyz"
        let digits = "23456789"
        let symbols = "!@#$%^&*()-_=+"
        let all = upper + lower + digits + symbols
        
        var pass = ""
        // Ensure at least one from each class
        if let u = upper.randomElement() { pass.append(u) }
        if let l = lower.randomElement() { pass.append(l) }
        if let d = digits.randomElement() { pass.append(d) }
        if let s = symbols.randomElement() { pass.append(s) }
        
        for _ in 4..<length {
            if let c = all.randomElement() {
                pass.append(c)
            }
        }
        return String(pass.shuffled())
    }
}
