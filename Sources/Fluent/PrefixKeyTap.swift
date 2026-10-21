import Cocoa
import os.log

private let tapLog = Logger(subsystem: "com.yangxin.inputmethod.Fluent", category: "prefix-keys")

/// Sees every key press, listen-only, so a prefix key works in apps that
/// keep it from input methods: WezTerm hands an input method only plain and
/// Shift keys, so its Ctrl-X never reaches `handle(_:client:)` and the N
/// after it would start a composition.
///
/// Key presses bound for other apps need Input Monitoring, which macOS asks
/// for the first time a Fluent session starts with prefix keys set. The tap
/// runs only then, while a Fluent session is active, and keeps no keys:
/// only when the last few presses came and whether each was a prefix key.
/// Whether it may watch is written for Settings to show (docs/config.md).
final class PrefixKeyTap {
    static let shared = PrefixKeyTap()

    private struct Press {
        let time: TimeInterval
        let isPrefix: Bool
    }

    /// The last few key presses, oldest first.
    private var presses: [Press] = []
    private var keys: [String] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private weak var activeController: InputController?
    private var asked = false
    private var lastCheck: TimeInterval = -.infinity
    private var reported: Bool?
    private var clockLogged = false

    private init() {}

    func sessionActivated(_ controller: InputController, keys: [String]) {
        activeController = controller
        update(keys: keys, recheck: true)
    }

    func sessionDeactivated(_ controller: InputController) {
        guard activeController === controller else { return }
        activeController = nil
        update(keys: keys)
    }

    /// Watches while the config has prefix `keys` and a session is active.
    /// Without a tap, permission is checked at most every 2 seconds;
    /// `recheck` checks it now, for a grant taken back.
    func update(keys: [String], recheck: Bool = false) {
        self.keys = keys
        guard !keys.isEmpty, activeController != nil else {
            pause()
            return
        }
        if tap == nil || recheck {
            let now = ProcessInfo.processInfo.systemUptime
            guard recheck || now - lastCheck > 2 else { return }
            lastCheck = now
            guard allowed() else {
                remove()
                return
            }
            if tap == nil {
                install()
            }
        }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Whether the key press before `event` was a prefix key, at most
    /// `window` seconds before it; nil while not watching, when only the
    /// keys IMK hands over can tell.
    func followsPrefix(_ event: NSEvent, within window: TimeInterval) -> Bool? {
        guard let tap, CGEvent.tapIsEnabled(tap: tap) else { return nil }
        if !clockLogged, let last = presses.last {
            clockLogged = true
            tapLog.notice("clocks: key \(event.timestamp, privacy: .public) last press \(last.time, privacy: .public)")
        }
        // `event` itself may not have reached the tap yet: look only at
        // what came before it.
        guard let before = presses.last(where: { $0.time < event.timestamp - 0.002 }) else { return false }
        return before.isPrefix && event.timestamp - before.time < window
    }

    private func allowed() -> Bool {
        let allowed = CGPreflightListenEventAccess()
        if !allowed && !asked {
            asked = true
            tapLog.notice("asking for Input Monitoring")
            CGRequestListenEventAccess()
        }
        report(allowed)
        return allowed
    }

    private func install() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                if let info {
                    Unmanaged<PrefixKeyTap>.fromOpaque(info).takeUnretainedValue().saw(type, event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            tapLog.error("couldn't watch key presses")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        tap = port
        self.source = source
        tapLog.notice("watching key presses for prefix keys")
    }

    private func pause() {
        if let tap, CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        presses.removeAll()
    }

    private func remove() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        presses.removeAll()
        tapLog.notice("stopped watching key presses")
    }

    private func saw(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if activeController != nil, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .keyDown:
            guard let key = NSEvent(cgEvent: event) else { return }
            let isPrefix = InputController.comboName(of: key).map(keys.contains) ?? false
            presses.append(Press(time: key.timestamp, isPrefix: isPrefix))
            if presses.count > 8 {
                presses.removeFirst(presses.count - 8)
            }
        default:
            break
        }
    }

    /// Where the input method says whether it may watch key presses
    /// (docs/config.md); Settings reads it.
    static let statusFileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Fluent/status.json")

    private func report(_ allowed: Bool) {
        guard reported != allowed else { return }
        reported = allowed
        tapLog.notice("Input Monitoring allowed=\(allowed, privacy: .public)")
        let url = Self.statusFileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try "{\"inputMonitoring\": \(allowed)}\n".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            tapLog.error("saving status failed: \(String(describing: error), privacy: .public)")
        }
    }
}
