import Cocoa

extension BrowserController {
    /// The mouse was released on a tab: a click selects it, a drag commits the new order first.
    ///
    /// Selecting rebuilds every tab view, including the one that is handling this very mouse-up,
    /// so it waits for the next turn of the run loop.
    func finishTabPress(_ tab: BrowserTab, reordered: Bool) {
        if reordered, let arranged = TabReorder.arranged(tabs, by: TabStripDrag.order(in: tabStack), id: { $0.id }) {
            let activeID = activeTab.id
            tabs = arranged
            activeTabIndex = tabs.firstIndex { $0.id == activeID } ?? activeTabIndex
            scheduleSessionSave()
        }
        DispatchQueue.main.async { [weak self] in
            // Also the fallback when the on-screen order and the model disagree: selectTab
            // rebuilds the strip from the model.
            guard let self = self, let index = self.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
            self.selectTab(at: index)
        }
    }
}
