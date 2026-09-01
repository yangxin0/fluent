import Foundation

/// Detects a double tap of the Shift key (press+release twice, quickly, with
/// nothing else pressed in between) from a stream of timestamped events.
/// Pure timestamp logic so it stays unit-testable without AppKit.
public struct ShiftTapDetector {
    /// Longest press→release that still counts as a "tap" (not a hold).
    public var maxTapDuration: TimeInterval
    /// Longest gap between the first release and the second press.
    public var maxTapInterval: TimeInterval

    private var downTime: TimeInterval?
    private var lastTapEnd: TimeInterval?

    public init(maxTapDuration: TimeInterval = 0.3, maxTapInterval: TimeInterval = 0.4) {
        self.maxTapDuration = maxTapDuration
        self.maxTapInterval = maxTapInterval
    }

    /// Shift went down with no other modifiers held.
    public mutating func shiftDown(at time: TimeInterval) {
        if let end = lastTapEnd, time - end > maxTapInterval {
            lastTapEnd = nil
        }
        downTime = time
    }

    /// Shift released. Returns true when this completes a double tap.
    public mutating func shiftUp(at time: TimeInterval) -> Bool {
        guard let down = downTime else {
            lastTapEnd = nil
            return false
        }
        downTime = nil
        guard time - down <= maxTapDuration else {
            lastTapEnd = nil
            return false
        }
        if lastTapEnd != nil {
            // shiftDown already validated the gap since the previous tap.
            lastTapEnd = nil
            return true
        }
        lastTapEnd = time
        return false
    }

    /// Any other key or modifier activity cancels a pending tap sequence
    /// (e.g. Shift held to type a capital letter).
    public mutating func interrupt() {
        downTime = nil
        lastTapEnd = nil
    }
}
