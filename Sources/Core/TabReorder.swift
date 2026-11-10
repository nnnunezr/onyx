import Foundation

// MARK: - Tab reordering
/// Foundation-only so it can be unit-tested outside the app (tests/run.sh).
enum TabReorder {
    /// The slot under the pointer: the first tab whose right edge reaches `x`, else the last one.
    static func slot(forX x: CGFloat, rightEdges: [CGFloat]) -> Int {
        rightEdges.firstIndex { $0 >= x } ?? max(rightEdges.count - 1, 0)
    }

    /// How far to scroll the strip sideways: the distance the pointer is past the visible ends,
    /// capped so a far-away pointer scrolls at a steady pace. Zero while it is inside.
    static func edgeScroll(pointerX x: CGFloat, visibleMinX: CGFloat, visibleMaxX: CGFloat, maxStep: CGFloat = 24) -> CGFloat {
        if x < visibleMinX { return max(x - visibleMinX, -maxStep) }
        if x > visibleMaxX { return min(x - visibleMaxX, maxStep) }
        return 0
    }

    /// `items` arranged to match `order`. Nil unless `order` names every item exactly once, so a
    /// reorder built from the on-screen strip can never drop or duplicate a tab in the model.
    static func arranged<T, ID: Hashable>(_ items: [T], by order: [ID], id: (T) -> ID) -> [T]? {
        let byID = Dictionary(items.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        guard byID.count == items.count, order.count == items.count,
              Set(order).count == order.count, order.allSatisfy({ byID[$0] != nil }) else { return nil }
        return order.compactMap { byID[$0] }
    }
}
