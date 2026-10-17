import Cocoa

/// What the preview panel and the candidate bar share, so both land in the
/// same spot and follow the same color scheme.
enum PanelPlacement {
    /// A borderless, non-activating floating panel: it never takes focus from
    /// the client app.
    static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    /// "light"/"dark" force that scheme; anything else follows the system
    /// (nil appearance = inherit NSApp's effective, system-tracking appearance).
    static func applyAppearance(_ preference: String, to panel: NSPanel) {
        let desired: NSAppearance?
        switch preference {
        case "light": desired = NSAppearance(named: .aqua)
        case "dark": desired = NSAppearance(named: .darkAqua)
        default: desired = nil
        }
        if panel.appearance?.name != desired?.name {
            panel.appearance = desired
        }
    }

    /// Below the composed line by default; flipped above it near the bottom
    /// edge; clamped horizontally; fallback position for clients that report
    /// a zero caret rect (some Electron apps).
    static func origin(for size: NSSize, caretRect: NSRect) -> NSPoint {
        let screen = screenContaining(caretRect) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            return NSPoint(x: 100, y: 100)
        }
        if caretRect == .zero {
            return NSPoint(x: visible.midX - size.width / 2,
                           y: visible.minY + visible.height * 0.2)
        }
        var x = caretRect.minX
        var y = caretRect.minY - size.height - 6
        if y < visible.minY {
            y = caretRect.maxY + 6
        }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        y = min(max(y, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

    private static func screenContaining(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) || $0.frame.contains(rect.origin) }
    }
}
