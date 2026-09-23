import Cocoa
import WebKit

// MARK: - Session Save & Restore ("Restore previous session tabs" startup mode)
extension BrowserController {
    private static let sessionDefaultsKey = "OnyxSessionTabs"

    private struct SavedWorkspace: Codable {
        var urls: [String]
        var activeIndex: Int
    }

    /// Onyx's bundled pages are saved as onyx:// aliases so a rebuilt/moved bundle still resolves.
    private func sessionString(for tab: BrowserTab) -> String? {
        let url = tab.webView.url ?? tab.url
        if isStartPageURL(url) { return "onyx://home" }
        if isSettingsURL(url) { return "onyx://settings" }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url.absoluteString
    }

    private func snapshot(_ tabList: [BrowserTab], activeIndex: Int) -> SavedWorkspace {
        var urls: [String] = []
        var mappedActive = 0
        for (i, tab) in tabList.enumerated() {
            guard let str = sessionString(for: tab) else { continue }
            if i == activeIndex { mappedActive = urls.count }
            urls.append(str)
        }
        return SavedWorkspace(urls: urls, activeIndex: mappedActive)
    }

    /// Persists every workspace's tabs. Cheap enough to call after navigations and tab changes.
    func saveSession() {
        guard UserDefaults.standard.string(forKey: "OnyxStartupBehavior") == "restore" else { return }
        var all: [String: SavedWorkspace] = [:]
        for (profileId, tabList) in profileTabs where profileId != activeProfile.id {
            all[profileId] = snapshot(tabList, activeIndex: profileActiveIndices[profileId] ?? 0)
        }
        all[activeProfile.id] = snapshot(tabs, activeIndex: activeTabIndex)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: BrowserController.sessionDefaultsKey)
        }
    }

    /// Reopens the saved tabs for `profile` into the (empty) current tab list.
    /// Returns false when there was nothing to restore, so the caller can open a start page.
    @discardableResult
    func restoreSessionTabs(for profile: BrowserProfile) -> Bool {
        guard UserDefaults.standard.string(forKey: "OnyxStartupBehavior") == "restore",
              let data = UserDefaults.standard.data(forKey: BrowserController.sessionDefaultsKey),
              let all = try? JSONDecoder().decode([String: SavedWorkspace].self, from: data),
              let saved = all[profile.id], !saved.urls.isEmpty else { return false }

        for str in saved.urls {
            createNewTab(url: resolveQuery(str), switchTo: false)
        }
        selectTab(at: min(max(saved.activeIndex, 0), tabs.count - 1))
        return true
    }
}
