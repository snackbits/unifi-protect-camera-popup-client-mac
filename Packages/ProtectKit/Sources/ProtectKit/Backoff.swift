import Foundation

public struct Backoff {
    private let base: TimeInterval
    private let max: TimeInterval
    private var attempt = 0

    public init(base: TimeInterval = 2, max: TimeInterval = 60) {
        self.base = base
        self.max = max
    }

    public mutating func next() -> TimeInterval {
        let value = Swift.min(max, base * pow(2, Double(attempt)))
        attempt += 1
        return value
    }

    public mutating func reset() { attempt = 0 }
}
