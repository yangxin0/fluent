import Cocoa
import EnglishInputCore

/// Floating, non-activating panel showing the streamed improvement near the
/// caret. One shared instance — only one composition is active at a time.
final class PreviewPanelController {
    static let shared = PreviewPanelController()

    private let panel: NSPanel
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

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true

        modeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        modeLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.textColor = .labelColor
        textLabel.preferredMaxLayoutWidth = Self.maxTextWidth

        let header = NSStackView(views: [modeLabel, NSView(), statusLabel])
        header.orientation = .horizontal
        header.distribution = .fill

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

    func show(mode: Mode, text: String, status: String, near caretRect: NSRect) {
        modeLabel.stringValue = mode.badge.uppercased()
        statusLabel.stringValue = status
        textLabel.stringValue = text.isEmpty ? "…" : text

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
