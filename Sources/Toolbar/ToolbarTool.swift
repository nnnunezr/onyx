import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Toolbar Extensions & Pinning System
enum OnyxToolbarTool: String, CaseIterable {
    case aiResearch = "ai_research"
    case downloads = "downloads"
    case passwords = "passwords"
    case shield = "shield"
    
    var title: String {
        switch self {
        case .aiResearch: return "AI Research Canvas"
        case .downloads: return "Downloads Shelf"
        case .passwords: return "Passwords & Vault"
        case .shield: return "Onyx Shield"
        }
    }
    
    var subtitle: String {
        switch self {
        case .aiResearch: return "Synthetic research & workspaces (⌘⇧S)"
        case .downloads: return "Files & active downloads (⌘J)"
        case .passwords: return "Keychain & autofill (⌘⌥P)"
        case .shield: return "Tracker blocker & memory monitor"
        }
    }
    
    var iconName: String {
        switch self {
        case .aiResearch: return "sparkles"
        case .downloads: return "arrow.down.circle.fill"
        case .passwords: return "lock.shield.fill"
        case .shield: return "shield.checkerboard"
        }
    }
    
    var prefKey: String {
        return "OnyxToolbarPin_" + self.rawValue
    }
    
    var isPinned: Bool {
        if UserDefaults.standard.object(forKey: prefKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: prefKey)
    }
    
    func setPinned(_ pinned: Bool) {
        UserDefaults.standard.set(pinned, forKey: prefKey)
    }
}
