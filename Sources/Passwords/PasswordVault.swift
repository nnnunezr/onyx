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
    
    /// Strict: the page host must be the saved domain or a subdomain of it (a leading `www.` is
    /// ignored on both sides). No substring or reverse matching, so `tradesea.ai-secure.net`
    /// never matches a saved `tradesea.ai` login and `x.com` never matches `netflix.com`.
    func matches(host: String) -> Bool {
        func stripWWW(_ s: String) -> String {
            let t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return t.hasPrefix("www.") ? String(t.dropFirst(4)) : t
        }
        return URLClassifier.host(stripWWW(host), isOrIsSubdomainOf: stripWWW(domain))
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
    
    // Legacy plaintext locations (pre-Keychain). Migrated once, then erased.
    private let legacyDefaultsKey = "OnyxVaultPasswords"
    private var legacyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Onyx/passwords.json")
    }
    
    // The whole vault is one Keychain generic-password item holding the JSON-encoded entries.
    // ONYX_VAULT_SERVICE lets throwaway test builds use their own item instead of prompting
    // for access to the real vault.
    private let keychainService = ProcessInfo.processInfo.environment["ONYX_VAULT_SERVICE"] ?? "com.company.onyx.vault"
    private let keychainAccount = "passwords"
    
    private var entries: [OnyxPasswordEntry] = []
    /// False when the Keychain could not be read (e.g. access denied). Saving is then refused so
    /// an empty in-memory vault can never overwrite the real one.
    private(set) var isLoaded = false
    
    /// Placeholder rows older builds seeded into every new vault.
    private static let legacySeedUsernames: Set<String> = ["developer@onyx.dev", "user@gmail.com", "trader_onyx"]
    
    static let didLoadNotification = Notification.Name("OnyxPasswordStoreDidLoad")
    
    /// Loads asynchronously: reading the Keychain can raise a system permission prompt, and
    /// that must never block the main thread (it previously froze launch before the window appeared).
    init() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = readKeychain()
            let legacy = loadLegacyPlaintext()
            DispatchQueue.main.async {
                self.finishLoad(result, legacy: legacy)
                NotificationCenter.default.post(name: OnyxPasswordStore.didLoadNotification, object: self)
            }
        }
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
    
    private func finishLoad(_ result: Result<Data?, KeychainError>, legacy: [OnyxPasswordEntry]) {
        // Anything the user saved while the load was still in flight.
        let pendingLocal = entries
        
        let stored: [OnyxPasswordEntry]
        switch result {
        case .failure(let error):
            NSLog("Onyx: password vault unavailable (Keychain status %d)", error.status)
            isLoaded = false
            return
        case .success(nil):
            stored = []
        case .success(let data?):
            guard let decoded = try? JSONDecoder().decode([OnyxPasswordEntry].self, from: data) else {
                // Never overwrite a vault we could not read.
                NSLog("Onyx: password vault in Keychain is unreadable; leaving it untouched")
                isLoaded = false
                return
            }
            stored = decoded
        }
        
        // Legacy plaintext (pre-Keychain) is merged in once, minus the fake rows old builds seeded.
        let cleanLegacy = legacy.filter {
            !($0.password == "••••••••••••" && OnyxPasswordStore.legacySeedUsernames.contains($0.username))
        }
        entries = OnyxPasswordStore.merge(stored, with: cleanLegacy + pendingLocal)
        isLoaded = true
        
        if !legacy.isEmpty || !pendingLocal.isEmpty {
            if save() { eraseLegacyPlaintext() }
        }
    }
    
    /// Union by id; when both sides have an entry, the most recently updated one wins.
    private static func merge(_ base: [OnyxPasswordEntry], with incoming: [OnyxPasswordEntry]) -> [OnyxPasswordEntry] {
        var result = base
        for entry in incoming {
            if let idx = result.firstIndex(where: { $0.id == entry.id }) {
                if entry.updatedAt > result[idx].updatedAt { result[idx] = entry }
            } else {
                result.append(entry)
            }
        }
        return result
    }
    
    @discardableResult
    func save() -> Bool {
        guard isLoaded else {
            NSLog("Onyx: refusing to save password vault that failed to load")
            return false
        }
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        let status = writeKeychain(data)
        if status != errSecSuccess {
            NSLog("Onyx: failed to save password vault (Keychain status %d)", status)
        }
        return status == errSecSuccess
    }
    
    // MARK: Keychain I/O
    private var baseQuery: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }
    
    private func readKeychain() -> Result<Data?, KeychainError> {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return .success(result as? Data)
        case errSecItemNotFound: return .success(nil)
        default: return .failure(KeychainError(status: status))
        }
    }
    
    private func writeKeychain(_ data: Data) -> OSStatus {
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Onyx Password Vault"
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status
    }
    
    struct KeychainError: Error {
        let status: OSStatus
    }
    
    // MARK: Legacy plaintext migration
    private func loadLegacyPlaintext() -> [OnyxPasswordEntry] {
        if let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let list = try? JSONDecoder().decode([OnyxPasswordEntry].self, from: data) {
            return list
        }
        if let data = try? Data(contentsOf: legacyFileURL),
           let list = try? JSONDecoder().decode([OnyxPasswordEntry].self, from: data) {
            return list
        }
        return []
    }
    
    private func eraseLegacyPlaintext() {
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        try? FileManager.default.removeItem(at: legacyFileURL)
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
