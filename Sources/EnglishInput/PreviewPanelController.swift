import Cocoa
import EnglishInputCore

/// The in-progress composition, for clients that clip their marked text.
struct TypedText {
    let raw: String
    /// Caret position in characters.
    let cursor: Int
}

/// Floating, non-activating panel showing the streamed improvement near the
/// caret. One shared instance — only one composition is active at a time.
final class PreviewPanelController {
    static let shared = PreviewPanelController()

    private let panel: NSPanel
    private let background = PanelBackgroundView()
    private let modePill = NSView()
    private let modeLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let typedLabel = NSTextField(wrappingLabelWithString: "")
    private let separator = NSBox()
    private let textLabel = NSTextField(wrappingLabelWithString: "")

    private static let maxTextWidth: CGFloat = 480
    /// Wider when the typed text is shown too, so a full sentence fits in a
    /// couple of rows rather than a tall column.
    private static let maxTextWidthWithTyped: CGFloat = 640
    private static let padding: CGFloat = 10
    private var maxTextWidth: CGFloat = PreviewPanelController.maxTextWidth

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

        // Squirrel's "native" style: semantic colors that adapt to light/dark.
        // Background = windowBackgroundColor, highlight = selectedTextBackground,
        // text = label/secondaryLabel. The panel's appearance is set to the
        // system's (see applyAppearance), matching Squirrel's approach.
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.borderWidth = 1
        background.layer?.masksToBounds = true
        background.onAppearanceChange = { [weak self] in self?.refreshLayerColors() }

        // Mode badge as a highlighted pill, using the system selection color
        // like Squirrel's highlighted candidate. labelColor reads on it in
        // both light and dark.
        modeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        modeLabel.textColor = .labelColor
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
        typedLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        typedLabel.textColor = .labelColor
        typedLabel.preferredMaxLayoutWidth = Self.maxTextWidth
        typedLabel.isHidden = true
        separator.boxType = .separator
        separator.isHidden = true

        let header = NSStackView(views: [modePill, NSView(), statusLabel])
        header.orientation = .horizontal
        header.distribution = .fill
        header.alignment = .centerY

        let stack = NSStackView(views: [header, typedLabel, separator, textLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: Self.padding, left: Self.padding,
                                        bottom: Self.padding, right: Self.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(stack)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.padding),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
    }

    /// `typed` is shown (with a caret marker) for clients that clip marked
    /// text, e.g. terminals; pass nil where the client renders it fully.
    func show(mode: Mode, typed: TypedText?, text: String, status: String,
              appearance: String, near caretRect: NSRect) {
        flashToken += 1  // cancel any pending flash auto-hide
        applyAppearance(appearance)
        modePill.isHidden = false
        modeLabel.stringValue = mode.badge.uppercased()
        statusLabel.stringValue = status
        setMaxTextWidth(typed == nil ? Self.maxTextWidth : Self.maxTextWidthWithTyped)
        textLabel.stringValue = text.isEmpty ? "…" : text
        if let typed {
            typedLabel.attributedStringValue = Self.render(typed)
        }
        typedLabel.isHidden = typed == nil
        separator.isHidden = typed == nil
        present(near: caretRect)
    }

    private func setMaxTextWidth(_ width: CGFloat) {
        maxTextWidth = width
        textLabel.preferredMaxLayoutWidth = width
        typedLabel.preferredMaxLayoutWidth = width
    }

    /// Typed text with a caret bar at the cursor, in the accent color.
    private static func render(_ typed: TypedText) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let cursor = max(0, min(typed.cursor, typed.raw.count))
        let idx = typed.raw.index(typed.raw.startIndex, offsetBy: cursor)
        let result = NSMutableAttributedString(string: String(typed.raw[..<idx]), attributes: base)
        var caretAttrs = base
        caretAttrs[.foregroundColor] = NSColor.controlAccentColor
        caretAttrs[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        result.append(NSAttributedString(string: "|", attributes: caretAttrs))
        result.append(NSAttributedString(string: String(typed.raw[idx...]), attributes: base))
        return result
    }

    /// Show a transient notice (e.g. the ⇧⇧ on/off toggle) that hides itself.
    func flash(message: String, appearance: String, near caretRect: NSRect) {
        flashToken += 1
        let token = flashToken
        applyAppearance(appearance)
        modePill.isHidden = true
        statusLabel.stringValue = ""
        typedLabel.isHidden = true
        separator.isHidden = true
        setMaxTextWidth(Self.maxTextWidth)
        textLabel.stringValue = message
        present(near: caretRect)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.flashToken == token else { return }
            self.hide()
        }
    }

    private func present(near caretRect: NSRect) {
        refreshLayerColors()
        guard let contentView = panel.contentView else { return }
        let fitting = contentView.fittingSize
        let size = NSSize(width: min(max(fitting.width, 160), maxTextWidth + 2 * Self.padding),
                          height: fitting.height)
        panel.setFrame(NSRect(origin: origin(for: size, caretRect: caretRect), size: size),
                       display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private var flashToken = 0

    /// Semantic colors used as CGColors on layers are snapshots, so re-resolve
    /// them against the panel's current appearance (background + border are
    /// handled by the background view; the pill is refreshed here too).
    private func refreshLayerColors() {
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            modePill.layer?.backgroundColor = NSColor.selectedTextBackgroundColor.cgColor
        }
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

/// Solid rounded background using Squirrel's native semantic palette
/// (windowBackgroundColor + a separatorColor hairline). These become CGColor
/// snapshots on the layer, so they are re-resolved whenever the effective
/// (system) appearance flips between light and dark. `onAppearanceChange` lets
/// the controller refresh its own layer colors (the mode pill) at the same time.
private final class PanelBackgroundView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
        onAppearanceChange?()
    }
}
