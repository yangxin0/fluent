import Cocoa
import EnglishInputCore

/// Floating, non-activating panel showing the streamed improvement near the
/// caret. One shared instance — only one composition is active at a time.
final class PreviewPanelController {
    static let shared = PreviewPanelController()

    private let panel: NSPanel
    private let modePill = NSView()
    private let modeLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(wrappingLabelWithString: "")

    private static let maxTextWidth: CGFloat = 480
    private static let padding: CGFloat = 10

    private init() {
        panel = NSPanel(
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

        // `.popover` adapts to the system light/dark appearance (unlike the
        // always-dark `.hudWindow`); the panel inherits NSApp's effective
        // appearance, which follows the system setting and updates live.
        let effect = PanelBackgroundView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true

        // Mode badge as a system-accent pill, matching the selected-candidate
        // pill in the built-in IMEs. White text reads on the accent in both
        // light and dark.
        modeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        modeLabel.textColor = .white
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modePill.wantsLayer = true
        modePill.layer?.cornerRadius = 4
        modePill.addSubview(modeLabel)
        NSLayoutConstraint.activate([
            modeLabel.leadingAnchor.constraint(equalTo: modePill.leadingAnchor, constant: 6),
            modeLabel.trailingAnchor.constraint(equalTo: modePill.trailingAnchor, constant: -6),
            modeLabel.topAnchor.constraint(equalTo: modePill.topAnchor, constant: 2),
            modeLabel.bottomAnchor.constraint(equalTo: modePill.bottomAnchor, constant: -2),
        ])
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.textColor = .labelColor
        textLabel.preferredMaxLayoutWidth = Self.maxTextWidth

        let header = NSStackView(views: [modePill, NSView(), statusLabel])
        header.orientation = .horizontal
        header.distribution = .fill
        header.alignment = .centerY

        let stack = NSStackView(views: [header, textLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: Self.padding, left: Self.padding,
                                        bottom: Self.padding, right: Self.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
    }

    func show(mode: Mode, text: String, status: String, appearance: String, near caretRect: NSRect) {
        applyAppearance(appearance)
        modeLabel.stringValue = mode.badge.uppercased()
        statusLabel.stringValue = status
        textLabel.stringValue = text.isEmpty ? "…" : text

        // Accent pill, resolved against whatever appearance is now in effect.
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            modePill.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }

        guard let contentView = panel.contentView else { return }
        let fitting = contentView.fittingSize
        let size = NSSize(width: min(max(fitting.width, 160), Self.maxTextWidth + 2 * Self.padding),
                          height: fitting.height)
        panel.setFrame(NSRect(origin: origin(for: size, caretRect: caretRect), size: size),
                       display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// "light"/"dark" force that scheme; anything else follows the system
    /// (nil appearance = inherit NSApp's effective, system-tracking appearance).
    private func applyAppearance(_ preference: String) {
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
    private func origin(for size: NSSize, caretRect: NSRect) -> NSPoint {
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

    private func screenContaining(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) || $0.frame.contains(rect.origin) }
    }
}

/// Rounded translucent background with a hairline border. The border color is
/// a `CGColor` snapshot, so it must be re-resolved whenever the effective
/// (system) appearance flips between light and dark.
private final class PanelBackgroundView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.borderWidth = 1
        updateBorderColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        // Resolve the dynamic separator color against this view's current
        // appearance so it matches whichever theme is active.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}
