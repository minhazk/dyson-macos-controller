import Foundation

/// Moves a sweep without changing its width or crossing the device's angle limits.
public struct OscillationRange: Equatable, Sendable {
    public let low: Double
    public let high: Double

    public init(low: Double, high: Double) {
        self.low = low
        self.high = high
    }

    public func shifted(by degrees: Double) -> Self {
        let snappedShift = (degrees / 5).rounded() * 5
        let shift = min(355 - high, max(5 - low, snappedShift))
        return Self(low: low + shift, high: high + shift)
    }
}
