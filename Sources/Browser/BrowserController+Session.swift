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

    private static let lastSessionDefaultsKey = "OnyxLastSession"

    private func loadSavedSession(forKey key: String = BrowserController.sessionDefaultsKey) -> [String: SavedWorkspace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([String: SavedWorkspace].self, from: data) else { return [:] }
        return all
    }

    /// Called once at launch, before anything can save: keeps a copy of the previous run's
    /// session so a bad first save can never destroy it.
    func snapshotLastSessionAtLaunch() {
        if let data = UserDefaults.standard.data(forKey: BrowserController.sessionDefaultsKey) {
            UserDefaults.standard.set(data, forKey: BrowserController.lastSessionDefaultsKey)
        }
    }

    /// Coalesces the many save triggers (every didFinish, every tab close) into one write.
    func scheduleSessionSave() {
        sessionSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveSession() }
        sessionSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    /// Persists every workspace's tabs, always (the startup mode only decides whether to restore).
    /// Workspaces not opened during this run keep their previously saved tabs.
    func saveSession() {
        sessionSaveWorkItem?.cancel()
        sessionSaveWorkItem = nil
        var all = loadSavedSession()
        for (profileId, tabList) in profileTabs where profileId != activeProfile.id {
            all[profileId] = snapshot(tabList, activeIndex: profileActiveIndices[profileId] ?? 0)
        }
        all[activeProfile.id] = snapshot(tabs, activeIndex: activeTabIndex)
        // Drop entries for workspaces that no longer exist.
        let liveIds = Set(profiles.map { $0.id })
        all = all.filter { liveIds.contains($0.key) }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: BrowserController.sessionDefaultsKey)
        }
    }

    /// Reopens the saved tabs for `profile` into the (empty) current tab list.
    /// Returns false when there was nothing to restore, so the caller can open a start page.
    @discardableResult
    func restoreSessionTabs(for profile: BrowserProfile) -> Bool {
        let fromLastSession = reopenLastSessionRequested
        guard fromLastSession || UserDefaults.standard.string(forKey: "OnyxStartupBehavior") == "restore" else { return false }
        let source = fromLastSession
            ? loadSavedSession(forKey: BrowserController.lastSessionDefaultsKey)
            : loadSavedSession()
        guard let saved = source[profile.id], !saved.urls.isEmpty else { return false }

        for str in saved.urls {
            createNewTab(url: resolveQuery(str), switchTo: false)
        }
        selectTab(at: min(max(saved.activeIndex, 0), tabs.count - 1))
        return true
    }

    /// File > Reopen Last Session: on-demand restore of the previous run's tabs, for when the
    /// startup mode is not Restore (or after an accidental quit). The current workspace gets its
    /// tabs now; other workspaces get theirs the first time they are opened this run.
    @objc func menuReopenLastSession() {
        guard !isShowingSheet else { return }
        let last = loadSavedSession(forKey: BrowserController.lastSessionDefaultsKey)
        guard last.values.contains(where: { !$0.urls.isEmpty }) else {
            showVaultToastHUD(icon: "clock.arrow.circlepath", title: "NOTHING TO REOPEN", message: "No tabs were saved from the previous session")
            return
        }
        reopenLastSessionRequested = true
        if let saved = last[activeProfile.id], !saved.urls.isEmpty {
            let replaceStartPage = tabs.count == 1 && isStartPageURL(tabs[0].url) && !tabs[0].webView.canGoBack
            let firstNew = tabs.count
            for str in saved.urls {
                createNewTab(url: resolveQuery(str), switchTo: false)
            }
            selectTab(at: firstNew + min(max(saved.activeIndex, 0), saved.urls.count - 1))
            if replaceStartPage {
                closeTab(at: 0)
            }
        }
        showVaultToastHUD(icon: "clock.arrow.circlepath", title: "SESSION REOPENED", message: "Previous tabs restored; other workspaces restore when opened")
    }
}
