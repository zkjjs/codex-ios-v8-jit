import Foundation

/// Uses monotonic timestamps and byte deltas; historical resumed bytes are not network traffic.
struct TransferRateMeter {
    private struct Sample { let bytes: Int64; let time: TimeInterval }
    private var samples: [Sample] = []
    private let window: TimeInterval = 3

    mutating func reset(completedBytes: Int64, at time: TimeInterval) {
        samples = [Sample(bytes: max(0, completedBytes), time: time)]
    }
    mutating func record(completedBytes: Int64, at time: TimeInterval) {
        let bytes = max(0, completedBytes)
        guard let previous = samples.last else { reset(completedBytes: bytes, at: time); return }
        guard time >= previous.time else { return }
        if bytes < previous.bytes || time - previous.time > window * 2 {
            reset(completedBytes: bytes, at: time)
            return
        }
        guard time - previous.time >= 0.1 else { return }
        samples.append(Sample(bytes: bytes, time: time))
        while samples.count > 2 && time - samples[1].time >= window { samples.removeFirst() }
    }
    func bytesPerSecond(at time: TimeInterval) -> Double {
        guard let first = samples.first, let last = samples.last,
              time >= last.time, time - last.time <= window,
              last.time - first.time >= 0.1 else { return 0 }
        return max(0, Double(last.bytes - first.bytes) / (last.time - first.time))
    }
    func remainingSeconds(totalBytes: Int64, completedBytes: Int64, at time: TimeInterval) -> TimeInterval? {
        let speed = bytesPerSecond(at: time)
        guard speed > 0, totalBytes > 0, totalBytes > completedBytes else { return nil }
        return Double(totalBytes - completedBytes) / speed
    }
    static func speedLabel(_ bytesPerSecond: Double) -> String {
        let bounded = min(Double(Int64.max / 2), max(0, bytesPerSecond.isFinite ? bytesPerSecond : 0))
        return ByteCountFormatter.string(fromByteCount: Int64(bounded), countStyle: .file) + "/s"
    }
}
