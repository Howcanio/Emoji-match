import Foundation

/// Turns absolute frame timestamps into safe deltas. The first frame after a reset yields 0,
/// and long gaps are capped, so a pause or missed notification can never eat round time.
public struct RoundClock: Sendable {
    public let maxStep: TimeInterval
    private var last: TimeInterval?

    public init(maxStep: TimeInterval = 0.25) { self.maxStep = maxStep }

    public mutating func reset() { last = nil }

    public mutating func delta(now: TimeInterval) -> TimeInterval {
        defer { last = now }
        guard let last else { return 0 }
        return min(max(0, now - last), maxStep)
    }
}
