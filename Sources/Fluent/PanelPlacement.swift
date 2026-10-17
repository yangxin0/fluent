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

/// The backdrop both panels share, so they read as one UI: the popover
/// material clipped to a rounded rect (a capsule when the radius is half the
/// height), with a hairline edge on top of the content.
final class PanelChromeView: NSVisualEffectView {
    /// Called when light/dark flips, for colors snapshotted into layers.
    var onAppearanceChange: (() -> Void)?

    var cornerRadius: CGFloat = 12 {
        didSet {
            guard cornerRadius != oldValue else { return }
            maskImage = Self.mask(radius: cornerRadius)
            edge.radius = cornerRadius
            edge.needsDisplay = true
        }
    }

    private let edge = HairlineView()

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active  // stay vibrant: the IME is never the active app
        maskImage = Self.mask(radius: cornerRadius)
        edge.radius = cornerRadius
        edge.frame = bounds
        edge.autoresizingMask = [.width, .height]
        addSubview(edge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Keeps the edge above whatever content is added later.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview !== edge { addSubview(edge, positioned: .above, relativeTo: nil) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    /// A rounded rect that stretches to any size, for `maskImage`.
    private static func mask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The hairline edge, so the panel reads on any background; ignores the mouse.
private final class HairlineView: NSView {
    var radius: CGFloat = 12

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        path.lineWidth = 0.5
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
