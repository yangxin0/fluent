import Foundation

/// Detects a double tap of the Shift key (press+release twice, quickly, with
/// nothing else pressed in between) from a stream of timestamped events.
/// Pure timestamp logic so it stays unit-testable without AppKit.
public struct ShiftTapDetector {
    /// Longest press→release that still counts as a "tap" (not a hold).
    public var maxTapDuration: TimeInterval
    /// Longest gap between the first release and the second press.
    public var maxTapInterval: TimeInterval
    /// After a double tap fires, a tap that follows almost immediately is
    /// ignored, so a stray third tap does not start a new pair. Kept short:
    /// people legitimately double-tap again about half a second later to
    /// toggle back, and that must still work.
    public var cooldown: TimeInterval

    private var downTime: TimeInterval?
    private var lastTapEnd: TimeInterval?
    private var lastFired: TimeInterval?

    public init(maxTapDuration: TimeInterval = 0.3, maxTapInterval: TimeInterval = 0.4,
                cooldown: TimeInterval = 0.25) {
        self.maxTapDuration = maxTapDuration
        self.maxTapInterval = maxTapInterval
        self.cooldown = cooldown
    }

    private func inCooldown(at time: TimeInterval) -> Bool {
        if let fired = lastFired, time - fired < cooldown { return true }
        return false
    }

    /// Shift went down with no other modifiers held.
    public mutating func shiftDown(at time: TimeInterval) {
        guard !inCooldown(at: time) else { return }
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
            lastFired = time
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
