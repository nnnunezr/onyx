import Foundation

// MARK: - Guarded private WebKit KVC
/// Onyx is personal and unsandboxed, so a few private WebKit knobs are acceptable. Each one is
/// applied only if the object still implements it, so a macOS update degrades the feature
/// instead of crashing at launch. `defaults write com.company.onyx OnyxDisablePrivateAPIs -bool YES`
/// turns them all off.
enum PrivateWebKit {
    static var isDisabled: Bool {
        return UserDefaults.standard.bool(forKey: "OnyxDisablePrivateAPIs")
    }

    static func set(_ object: NSObject, key: String, setter: String, value: Any) {
        guard !isDisabled else { return }
        let publicSetter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
        guard object.responds(to: NSSelectorFromString(setter)) ||
              object.responds(to: NSSelectorFromString(publicSetter)) else {
            OnyxLog.webkit.notice("private WebKit key \(key, privacy: .public) unavailable on this macOS; skipped")
            return
        }
        object.setValue(value, forKey: key)
    }
}
