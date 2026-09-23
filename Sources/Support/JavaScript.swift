import Foundation

// MARK: - Safe Swift → JavaScript value encoding
/// Every value interpolated into `evaluateJavaScript` source must go through here.
/// Raw string interpolation lets a crafted value break out of its quotes and run
/// arbitrary script in the target page.
enum JS {
    /// Encodes a string as a quoted, fully escaped JavaScript string literal.
    static func string(_ value: String) -> String {
        return literal(value) ?? "\"\""
    }

    /// Encodes any JSON-compatible value (dictionary, array, string, number, bool) as a JavaScript literal.
    static func literal(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              var json = String(data: data, encoding: .utf8) else { return nil }
        // Unwrap the single-element array used to satisfy JSONSerialization's top-level rule.
        json.removeFirst()
        json.removeLast()
        // U+2028/U+2029 are legal in JSON but historically terminate JS string literals.
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}

// MARK: - Search Engines
enum SearchEngines {
    static let supported: Set<String> = ["duckduckgo", "google", "brave", "perplexity", "kagi", "bing"]

    /// Returns the normalized engine key, or nil when it is not one Onyx supports.
    static func normalize(_ raw: String) -> String? {
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return supported.contains(key) ? key : nil
    }

    static var current: String {
        let stored = UserDefaults.standard.string(forKey: "OnyxSearchEngine") ?? "duckduckgo"
        return normalize(stored) ?? "duckduckgo"
    }
}
