import Cocoa
import FluentCore

/// The in-progress composition, for clients that clip their marked text.
struct TypedText {
    let raw: String
    /// Caret position in characters.
    let cursor: Int
}

/// What the bar shows; InputController builds one for each state.
struct BarContent {
    struct Cell {
        var text: String
        /// Dimmed text after the candidate: a rare character's pinyin, or
        /// the English line's status (`…`, `⚠ timeout`).
        var comment: String?
        /// Label for the number keys; nil for an unnumbered cell.
        var number: Int?
        /// Passed to `onSelect` when the cell is clicked.
        var index: Int
    }

    enum Chevron { case none, more(enabled: Bool), less }

    /// Mode letter (`F`/`P`/`T`) or `双` for shuangpin, before the cells.
    var badge: String?
    /// For terminals: the typed text with a caret, on its own line.
    var typed: TypedText?
    var cells: [Cell] = []
    /// Index into `cells` of the highlighted (accent pill) cell.
    var highlighted: Int?
    /// Cells per row when `expanded`.
    var columns = 6
    var expanded = false
    var chevron = Chevron.none
    var canPageBack = false
    var canPageForward = false
    /// A notice (the ⇧⇧ toggle) shown instead of cells.
    var message: NSAttributedString?
}

/// The one panel Fluent shows, for English and 小鹤双拼 alike, styled after
/// the system shuangpin input method: a capsule with a mode badge, then
/// candidates with the highlighted one on an accent-color pill, a divider
/// and a chevron that expands it into a grid. It becomes a rounded card when
/// it needs more than one line. System colors throughout, so it follows
/// light and dark. One shared instance; the active controller sets the
/// callbacks when it shows the bar.
final class CandidateBarController {
    static let shared = CandidateBarController()

    private let panel: NSPanel
    private let background = PanelChromeView()
    private let bar = CandidateBarView()
    private var flashToken = 0

    /// Called with the `index` of a clicked cell.
    var onSelect: ((Int) -> Void)?
    /// Called with +1 / -1 to turn the page (scrolling).
    var onPage: ((Int) -> Void)?
    /// Called when the chevron is clicked.
    var onToggleExpanded: (() -> Void)?

    private init() {
        panel = PanelPlacement.makePanel()
        bar.frame = background.bounds
        bar.autoresizingMask = [.width, .height]
        background.addSubview(bar)
        panel.contentView = background
        bar.onSelect = { [weak self] index in self?.onSelect?(index) }
        bar.onPage = { [weak self] delta in self?.onPage?(delta) }
        bar.onToggleExpanded = { [weak self] in self?.onToggleExpanded?() }
    }

    func show(_ content: BarContent, appearance: String, near caretRect: NSRect) {
        flashToken += 1  // cancel any pending flash auto-hide
        present(content, appearance: appearance, near: caretRect)
    }

    /// A transient notice (the ⇧⇧ on/off toggle) that hides itself.
    func flash(message: NSAttributedString, appearance: String, near caretRect: NSRect) {
        flashToken += 1
        let token = flashToken
        present(BarContent(message: message), appearance: appearance, near: caretRect)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.flashToken == token else { return }
            self.hide()
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func present(_ content: BarContent, appearance: String, near caretRect: NSRect) {
        PanelPlacement.applyAppearance(appearance, to: panel)
        bar.update(content)
        let size = bar.fittingSize
        background.cornerRadius = bar.isCapsule ? size.height / 2 : CandidateBarView.cardRadius
        panel.setFrame(NSRect(origin: PanelPlacement.origin(for: size, caretRect: caretRect), size: size),
                       display: true)
        panel.orderFrontRegardless()
    }
}

/// Draws everything itself: frames are simple sums and double as hit-test
/// rects.
private final class CandidateBarView: NSView {
    var onSelect: ((Int) -> Void)?
    var onPage: ((Int) -> Void)?
    var onToggleExpanded: (() -> Void)?

    private static let pillHeight: CGFloat = 30
    private static let edgeInset: CGFloat = 4
    private static let cellPadding: CGFloat = 9
    private static let cellSpacing: CGFloat = 2
    private static let chevronWidth: CGFloat = 30
    /// A lone long line (an English sentence) wraps beyond this width.
    private static let maxLineWidth: CGFloat = 520
    static let cardRadius: CGFloat = 12
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let textFont = NSFont.systemFont(ofSize: 18)
    private static let commentFont = NSFont.systemFont(ofSize: 12)
    private static let badgeFont = NSFont.systemFont(ofSize: 12, weight: .bold)
    private static let typedFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private struct Cell {
        var content: BarContent.Cell
        var row: Int
        var frame: NSRect
        /// Text wraps inside the cell (a long English line).
        var wraps: Bool
    }

    private var content = BarContent()
    private var cells: [Cell] = []
    private var badgeFrame: NSRect?
    private var typedFrame: NSRect?
    private var messageFrame: NSRect?
    private var chevronFrame: NSRect?
    private var size = NSSize.zero
    private var hovered: Int?
    private var pressed: Int?
    private var scrollAccumulator: CGFloat = 0

    /// Pressing the chevron is this index in `pressed`.
    private static let chevronIndex = -1

    /// One line of standard height: drawn as a capsule.
    private(set) var isCapsule = true

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var fittingSize: NSSize { size }

    func update(_ content: BarContent) {
        self.content = content
        hovered = nil
        layoutContent()
        needsDisplay = true
    }

    // MARK: - Layout

    private func layoutContent() {
        let inset = Self.edgeInset
        var top = inset
        var maxX: CGFloat = inset

        typedFrame = nil
        if let typed = content.typed {
            let text = Self.typedString(typed)
            let height = ceil(text.boundingRect(with: NSSize(width: Self.maxLineWidth, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin]).height)
            let width = min(ceil(text.size().width), Self.maxLineWidth)
            let frame = NSRect(x: inset + Self.cellPadding, y: top + 4, width: width, height: height)
            typedFrame = frame
            top = frame.maxY + 4
            maxX = max(maxX, frame.maxX + Self.cellPadding)
        }

        var x = inset
        badgeFrame = nil
        if let badge = content.badge {
            let width = max(22, ceil(Self.measure(badge, Self.badgeFont)) + 10)
            let frame = NSRect(x: x + 3, y: top + (Self.pillHeight - 20) / 2, width: width, height: 20)
            badgeFrame = frame
            x = frame.maxX + 4
        }

        messageFrame = nil
        cells = []
        var bottom = top + Self.pillHeight
        if let message = content.message.map(Self.styledMessage) {
            let bounds = message.boundingRect(with: NSSize(width: Self.maxLineWidth, height: .greatestFiniteMagnitude),
                                              options: [.usesLineFragmentOrigin])
            let height = max(Self.pillHeight, ceil(bounds.height) + 10)
            let frame = NSRect(x: x + Self.cellPadding, y: top, width: ceil(bounds.width), height: height)
            messageFrame = frame
            bottom = frame.maxY
            maxX = max(maxX, frame.maxX + Self.cellPadding)
        } else {
            let widths = content.cells.map(Self.cellWidth)
            let columns = max(content.columns, 1)
            var columnWidths = [CGFloat](repeating: 0, count: columns)
            for (offset, width) in widths.enumerated() {
                columnWidths[offset % columns] = max(columnWidths[offset % columns], width)
            }
            var cellX = x
            for (offset, item) in content.cells.enumerated() {
                let row = content.expanded ? offset / columns : 0
                let column = offset % columns
                var frame: NSRect
                var wraps = false
                if content.expanded {
                    let left = x + columnWidths[..<column].reduce(0, +) + CGFloat(column) * Self.cellSpacing
                    frame = NSRect(x: left, y: top + CGFloat(row) * (Self.pillHeight + Self.cellSpacing),
                                   width: columnWidths[column], height: Self.pillHeight)
                } else if content.cells.count == 1, widths[offset] > Self.maxLineWidth {
                    // A long English line wraps into a taller cell.
                    wraps = true
                    let text = Self.cellString(item, highlighted: false)
                    let height = ceil(text.boundingRect(with: NSSize(width: Self.maxLineWidth - 2 * Self.cellPadding,
                                                                     height: .greatestFiniteMagnitude),
                                                        options: [.usesLineFragmentOrigin]).height)
                    frame = NSRect(x: cellX, y: top, width: Self.maxLineWidth, height: max(Self.pillHeight, height + 10))
                } else {
                    frame = NSRect(x: cellX, y: top, width: widths[offset], height: Self.pillHeight)
                }
                cellX = frame.maxX + Self.cellSpacing
                cells.append(Cell(content: item, row: row, frame: frame, wraps: wraps))
                bottom = max(bottom, frame.maxY)
                maxX = max(maxX, frame.maxX)
            }
            if cells.isEmpty { maxX = max(maxX, x) }
        }
        maxX = max(maxX, badgeFrame.map { $0.maxX + 4 } ?? inset)

        chevronFrame = nil
        if case .none = content.chevron {
            size = NSSize(width: maxX + inset + 4, height: bottom + inset)
        } else {
            chevronFrame = NSRect(x: maxX + 1, y: top - inset, width: Self.chevronWidth, height: Self.pillHeight + 2 * inset)
            size = NSSize(width: maxX + 1 + Self.chevronWidth + inset, height: bottom + inset)
        }
        isCapsule = typedFrame == nil && size.height <= Self.pillHeight + 2 * inset + 0.5
    }

    private static func cellWidth(_ cell: BarContent.Cell) -> CGFloat {
        var width = cellPadding * 2 + measure(cell.text, textFont)
        if cell.number != nil { width += measure("8", numberFont) + 5 }
        if let comment = cell.comment { width += 4 + measure(comment, commentFont) }
        return ceil(width)
    }

    private static func measure(_ string: String, _ font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    /// The notice in the bar's text style wherever it sets none, so the
    /// caller can color a word.
    private static func styledMessage(_ message: NSAttributedString) -> NSAttributedString {
        let styled = NSMutableAttributedString(attributedString: message)
        let all = NSRange(location: 0, length: styled.length)
        styled.addAttributes([.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor], range: all)
        message.enumerateAttributes(in: all) { attributes, range, _ in styled.addAttributes(attributes, range: range) }
        return styled
    }

    /// Text plus comment, for cells that wrap.
    private static func cellString(_ cell: BarContent.Cell, highlighted: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(string: cell.text, attributes: [
            .font: textFont, .foregroundColor: highlighted ? NSColor.white : NSColor.labelColor,
        ])
        if let comment = cell.comment {
            result.append(NSAttributedString(string: "  " + comment, attributes: [
                .font: commentFont,
                .foregroundColor: highlighted ? NSColor.white.withAlphaComponent(0.75) : NSColor.secondaryLabelColor,
            ]))
        }
        return result
    }

    /// The typed text in the preedit color, with a caret bar at the cursor.
    private static func typedString(_ typed: TypedText) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: typedFont, .foregroundColor: NSColor.secondaryLabelColor]
        let cursor = max(0, min(typed.cursor, typed.raw.count))
        let index = typed.raw.index(typed.raw.startIndex, offsetBy: cursor)
        let result = NSMutableAttributedString(string: String(typed.raw[..<index]), attributes: base)
        result.append(NSAttributedString(string: "|", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.labelColor,
        ]))
        result.append(NSAttributedString(string: String(typed.raw[index...]), attributes: base))
        return result
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if let typedFrame, let typed = content.typed {
            Self.typedString(typed).draw(with: typedFrame, options: [.usesLineFragmentOrigin])
        }

        if let badgeFrame, let badge = content.badge {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: badgeFrame, xRadius: 6, yRadius: 6).fill()
            let text = NSAttributedString(string: badge, attributes: [
                .font: Self.badgeFont, .foregroundColor: NSColor.secondaryLabelColor,
            ])
            let textSize = text.size()
            text.draw(at: NSPoint(x: badgeFrame.midX - textSize.width / 2, y: badgeFrame.midY - textSize.height / 2))
        }

        if let messageFrame, let message = content.message {
            let styled = Self.styledMessage(message)
            let height = styled.boundingRect(with: NSSize(width: messageFrame.width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin]).height
            styled.draw(with: NSRect(x: messageFrame.minX, y: messageFrame.midY - height / 2,
                                     width: messageFrame.width + 1, height: height + 1),
                        options: [.usesLineFragmentOrigin])
        }

        let highlightedRow = content.highlighted.map { cells[$0].row }
        for (offset, cell) in cells.enumerated() {
            let isHighlighted = offset == content.highlighted
            if isHighlighted || offset == hovered {
                (isHighlighted ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor).setFill()
                let radius = min(cell.frame.height / 2, cell.wraps ? 8 : .greatestFiniteMagnitude)
                NSBezierPath(roundedRect: cell.frame, xRadius: radius, yRadius: radius).fill()
            }
            if cell.wraps {
                let text = Self.cellString(cell.content, highlighted: isHighlighted)
                text.draw(with: cell.frame.insetBy(dx: Self.cellPadding, dy: 5), options: [.usesLineFragmentOrigin])
                continue
            }
            let primary: NSColor = isHighlighted ? .white : .labelColor
            let secondary: NSColor = isHighlighted ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
            var x = cell.frame.minX + Self.cellPadding
            if let number = cell.content.number {
                // In the grid only the highlighted row is numbered: the
                // number keys pick in it.
                if !content.expanded || cell.row == highlightedRow {
                    _ = drawText("\(number)", Self.numberFont, secondary, x: x, in: cell.frame)
                }
                x += Self.measure("8", Self.numberFont) + 5
            }
            x += drawText(cell.content.text, Self.textFont, primary, x: x, in: cell.frame)
            if let comment = cell.content.comment {
                _ = drawText(comment, Self.commentFont, secondary, x: x + 4, in: cell.frame)
            }
        }

        // Divider, then the chevron: down to expand (dimmed when there is
        // nothing more), up to collapse the grid.
        if let chevron = chevronFrame {
            NSColor.separatorColor.setFill()
            NSRect(x: chevron.minX, y: chevron.minY + 10, width: 1, height: chevron.height - 20).fill()
            let expanded: Bool
            let enabled: Bool
            switch content.chevron {
            case .none: return
            case .more(let isEnabled): (expanded, enabled) = (false, isEnabled)
            case .less: (expanded, enabled) = (true, true)
            }
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            if let symbol = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                    accessibilityDescription: expanded ? "Fewer candidates" : "More candidates")?
                .withSymbolConfiguration(config) {
                let tint: NSColor = enabled ? .secondaryLabelColor : .tertiaryLabelColor
                let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                    symbol.draw(in: rect)
                    tint.set()
                    rect.fill(using: .sourceIn)
                    return true
                }
                let origin = NSPoint(x: chevron.midX - symbol.size.width / 2, y: chevron.midY - symbol.size.height / 2)
                tinted.draw(in: NSRect(origin: origin, size: symbol.size))
            }
        }
    }

    /// Draws `string` vertically centered in `frame` at `x`; returns its width.
    private func drawText(_ string: String, _ font: NSFont, _ color: NSColor, x: CGFloat, in frame: NSRect) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: x, y: frame.midY - size.height / 2))
        return size.width
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: the IME process is never the active app.
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }

    /// The cell offset under the pointer, or `chevronIndex`.
    private func target(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        if let chevronFrame, chevronFrame.contains(point) { return Self.chevronIndex }
        return cells.firstIndex { $0.frame.contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        let target = target(at: event).flatMap { $0 == Self.chevronIndex ? nil : $0 }
        if target != hovered {
            hovered = target
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = target(at: event)
    }

    /// Acts only if released over what was pressed, like a button.
    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let pressed, pressed == target(at: event) else { return }
        if pressed == Self.chevronIndex {
            switch content.chevron {
            case .more(enabled: true), .less: onToggleExpanded?()
            default: break
            }
        } else {
            onSelect?(cells[pressed].content.index)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY
        guard abs(scrollAccumulator) > 10 else { return }
        let delta = scrollAccumulator < 0 ? 1 : -1
        scrollAccumulator = 0
        if (delta > 0 && content.canPageForward) || (delta < 0 && content.canPageBack) { onPage?(delta) }
    }
}
