import Cocoa
import Carbon.HIToolbox
import os.log
import FluentCore

private let monLog = Logger(subsystem: "com.yangxin.inputmethod.Fluent", category: "shift-tap")

/// Watches for the ⇧⇧ toggle from a process-wide event monitor instead of
/// the events IMK forwards.
///
/// Modifier-only (flagsChanged) events reach an input method only when the
/// client app hands them to its NSTextInputContext, or when AppKit routes
/// them to a context it activated itself through window focus or input
/// source selection. wezterm does neither for flagsChanged, and a session
/// that was revived lazily by the first keystroke after an app switch (for
/// example after Input Source Pro re-selected this input source while the
/// window was becoming key) delivers keyDown but never a Shift press. A
/// global monitor sees every flagsChanged regardless, and needs no
/// accessibility or input-monitoring permission — key-down events would,
/// which is why keystrokes still come through the IMK path.
final class ShiftTapMonitor {
    static let shared = ShiftTapMonitor()

    private var detector = ShiftTapDetector()
    private var globalMonitor: Any?
    /// The controller whose client currently has focus; a double tap
    /// toggles through it so the flash appears next to that caret.
    private weak var activeController: InputController?

    private init() {}

    /// Whether the global monitor is installed. When it is, flagsChanged
    /// events arriving through IMK are ignored to avoid double counting.
    var usesGlobalMonitor: Bool { globalMonitor != nil }

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event, source: "global")
        }
        monLog.notice("global flagsChanged monitor installed: \(self.usesGlobalMonitor, privacy: .public)")
    }

    /// The session whose client has focus, if any.
    var currentController: InputController? { activeController }

    func sessionActivated(_ controller: InputController) {
        activeController = controller
        detector.interrupt()
    }

    func sessionDeactivated(_ controller: InputController) {
        if activeController === controller {
            activeController = nil
        }
        detector.interrupt()
    }

    /// A keystroke (seen through IMK) between two Shift taps means the user
    /// was typing a capital, not toggling.
    func interrupt() {
        detector.interrupt()
    }

    /// flagsChanged forwarded by IMK. Only used when the global monitor
    /// could not be installed.
    func handleIMKEvent(_ event: NSEvent) {
        guard !usesGlobalMonitor else { return }
        handle(event, source: "imk")
    }

    private func handle(_ event: NSEvent, source: StaticString) {
        VoiceHoldKey.shared.flagsChanged(event)
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift, .function])
        let isShiftKey = event.keyCode == UInt16(kVK_Shift) || event.keyCode == UInt16(kVK_RightShift)
        monLog.debug("\(source, privacy: .public) flagsChanged keyCode=\(event.keyCode, privacy: .public) mods=\(mods.rawValue, privacy: .public)")
        if isShiftKey && mods == [.shift] {
            detector.shiftDown(at: event.timestamp)
        } else if isShiftKey && mods.isEmpty {
            if detector.shiftUp(at: event.timestamp) {
                fire()
            }
        } else {
            detector.interrupt()
        }
    }

    private func fire() {
        // The monitor sees Shift taps under every input source; only act
        // while this one is selected and a client session is active.
        guard let controller = activeController else {
            monLog.notice("double-tap Shift ignored: no active session")
            return
        }
        guard Self.isCurrentInputSource() else {
            monLog.notice("double-tap Shift ignored: another input source is selected")
            return
        }
        monLog.notice("double-tap Shift → toggling")
        controller.toggleEnabled()
    }

    static func isCurrentInputSource() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return false }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        return id == (Bundle.main.bundleIdentifier ?? "com.yangxin.inputmethod.Fluent")
    }
}
