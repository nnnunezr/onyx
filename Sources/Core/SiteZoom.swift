import Foundation

// MARK: - Per-site zoom
/// Foundation-only so it can be unit-tested outside the app (tests/run.sh).
enum SiteZoom {
    static let range: ClosedRange<Double> = 0.5...3.0

    /// Zoom clamped to the allowed range and rounded to 2 decimals (repeated +0.1 steps drift otherwise).
    static func clamped(_ zoom: Double) -> Double {
        (min(max(zoom, range.lowerBound), range.upperBound) * 100).rounded() / 100
    }

    /// `saved` with `host` set to `zoom`. 100% removes the entry; an empty host changes nothing.
    static func updated(_ saved: [String: Double], host: String, zoom: Double) -> [String: Double] {
        guard !host.isEmpty else { return saved }
        var result = saved
        let z = clamped(zoom)
        if z == 1.0 { result.removeValue(forKey: host) } else { result[host] = z }
        return result
    }
}
