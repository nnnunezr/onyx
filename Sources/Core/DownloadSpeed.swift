import Foundation

// MARK: - Download speed
/// Smoothed transfer rate from periodic byte counts. Foundation-only so it can be unit-tested
/// outside the app (tests/run.sh).
struct DownloadSpeed {
    private(set) var bytesPerSecond: Double = 0
    private var previous: (bytes: Int64, time: TimeInterval)?

    /// Feed the total bytes received so far, at `time` seconds on any steady clock.
    mutating func add(bytes: Int64, at time: TimeInterval) {
        defer { previous = (bytes, time) }
        guard let prev = previous, time > prev.time else { return }
        // A count that went backwards (a restarted download) counts as no progress, not a negative rate.
        let instant = Double(max(bytes - prev.bytes, 0)) / (time - prev.time)
        bytesPerSecond = bytesPerSecond == 0 ? instant : bytesPerSecond * 0.7 + instant * 0.3
    }
}
