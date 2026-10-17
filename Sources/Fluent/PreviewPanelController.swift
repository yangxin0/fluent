import Cocoa
import FluentCore

/// The in-progress composition, for clients that clip their marked text.
struct TypedText {
    let raw: String
    /// Caret position in characters.
    let cursor: Int
}

/// Floating, non-activating panel showing the streamed improvement near the
/// caret, on the same backdrop as the candidate bar so the two read as one
/// UI. One shared instance — only one composition is active at a time.
final class PreviewPanelController {
    static let shared = PreviewPanelController()

    private let panel: NSPanel
    private let background = PanelChromeView()
    private let header = NSStackView()
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
    private static let padding: CGFloat = 12
    private var maxTextWidth: CGFloat = PreviewPanelController.maxTextWidth

    private init() {
        panel = PanelPlacement.makePanel()

        // Semantic colors that adapt to light/dark, as in the candidate bar:
        // text = label, preedit and hints = secondaryLabel. The panel's
        // appearance follows the system unless forced (see applyAppearance).
        background.cornerRadius = 12
        background.onAppearanceChange = { [weak self] in self?.refreshLayerColors() }

        // Mode badge as a quiet pill, like a candidate under the pointer in
        // the bar; labelColor reads on it in both light and dark.
        modeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        modeLabel.textColor = .labelColor
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modePill.wantsLayer = true
        modePill.layer?.cornerRadius = 8
        modePill.addSubview(modeLabel)
        NSLayoutConstraint.activate([
            modeLabel.leadingAnchor.constraint(equalTo: modePill.leadingAnchor, constant: 6),
            modeLabel.trailingAnchor.constraint(equalTo: modePill.trailingAnchor, constant: -6),
            modeLabel.topAnchor.constraint(equalTo: modePill.topAnchor, constant: 2),
            modeLabel.bottomAnchor.constraint(equalTo: modePill.bottomAnchor, constant: -2),
        ])
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .labelColor
        textLabel.preferredMaxLayoutWidth = Self.maxTextWidth
        typedLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        typedLabel.textColor = .secondaryLabelColor  // Squirrel's preedit text color
        typedLabel.preferredMaxLayoutWidth = Self.maxTextWidth
        typedLabel.isHidden = true
        separator.boxType = .separator
        separator.isHidden = true

        for view in [modePill, NSView(), statusLabel] { header.addArrangedSubview(view) }
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
        header.isHidden = false
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

    /// Typed text in Squirrel's preedit color with a caret bar at the cursor
    /// in its highlighted-preedit color.
    private static func render(_ typed: TypedText) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let cursor = max(0, min(typed.cursor, typed.raw.count))
        let idx = typed.raw.index(typed.raw.startIndex, offsetBy: cursor)
        let result = NSMutableAttributedString(string: String(typed.raw[..<idx]), attributes: base)
        var caretAttrs = base
        caretAttrs[.foregroundColor] = NSColor.labelColor
        caretAttrs[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        result.append(NSAttributedString(string: "|", attributes: caretAttrs))
        result.append(NSAttributedString(string: String(typed.raw[idx...]), attributes: base))
        return result
    }

    /// Show a transient notice (e.g. the ⇧⇧ on/off toggle) that hides itself.
    /// `message` is rendered as given, so callers can color a word; the body
    /// font and label color are applied wherever it sets none.
    func flash(message: NSAttributedString, appearance: String, near caretRect: NSRect) {
        flashToken += 1
        let token = flashToken
        applyAppearance(appearance)
        // The whole header row, not just the pill: an empty row still takes
        // its height and leaves a blank band above the message.
        header.isHidden = true
        typedLabel.isHidden = true
        separator.isHidden = true
        setMaxTextWidth(Self.maxTextWidth)
        let styled = NSMutableAttributedString(attributedString: message)
        let all = NSRange(location: 0, length: styled.length)
        styled.addAttributes([.font: textLabel.font!, .foregroundColor: textLabel.textColor!], range: all)
        message.enumerateAttributes(in: all) { attrs, range, _ in styled.addAttributes(attrs, range: range) }
        textLabel.attributedStringValue = styled
        present(near: caretRect, minWidth: 0)  // hug the notice; no "…" placeholder to pad
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.flashToken == token else { return }
            self.hide()
        }
    }

    /// `minWidth` keeps the preview from collapsing around its "…" placeholder.
    private func present(near caretRect: NSRect, minWidth: CGFloat = 160) {
        refreshLayerColors()
        guard let contentView = panel.contentView else { return }
        let fitting = contentView.fittingSize
        let size = NSSize(width: min(max(fitting.width, minWidth), maxTextWidth + 2 * Self.padding),
                          height: fitting.height)
        panel.setFrame(NSRect(origin: PanelPlacement.origin(for: size, caretRect: caretRect), size: size),
                       display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private var flashToken = 0

    /// Semantic colors used as CGColors on layers are snapshots, so re-resolve
    /// the pill's against the panel's current appearance.
    private func refreshLayerColors() {
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            modePill.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }

    private func applyAppearance(_ preference: String) {
        PanelPlacement.applyAppearance(preference, to: panel)
    }
}
