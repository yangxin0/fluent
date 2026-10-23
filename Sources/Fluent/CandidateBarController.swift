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

    /// Mode letter (`F`/`P`/`T`), or `双` / `拼` for shuangpin / full pinyin,
    /// before the cells.
    var badge: String?
    /// An SF Symbol in the badge instead of letters (`mic.fill` while voice
    /// input listens).
    var badgeSymbol: String?
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
    /// Dimmed after the English line (`↵`): Enter inserts that line.
    var enterHint: String?
}

/// The bar's sizes (Settings ▸ Appearance): the bar size scales the
/// chrome around the candidates, their padding, number labels and badge,
/// and the text size sets the candidates themselves; the pill grows to fit
/// them. Medium and 18 pt are the sizes the bar always had.
struct BarMetrics: Equatable {
    let scale: CGFloat
    let pillHeight: CGFloat
    let edgeInset: CGFloat
    let cellPadding: CGFloat
    let cellSpacing: CGFloat
    let chevronWidth: CGFloat
    /// A lone long line (an English sentence) wraps beyond this width.
    let maxLineWidth: CGFloat
    let cardRadius: CGFloat
    let numberFont: NSFont
    let textFont: NSFont
    let commentFont: NSFont
    let badgeFont: NSFont
    let typedFont: NSFont
    let typedCaretFont: NSFont
    let hintFont: NSFont

    static let standard = BarMetrics(barSize: "medium", textSize: 18)

    init(barSize: String, textSize: Double) {
        let s: CGFloat = barSize == "small" ? 0.85 : barSize == "large" ? 1.2 : 1
        scale = s
        textFont = NSFont.systemFont(ofSize: CGFloat(textSize))
        let line = ceil(textFont.ascender - textFont.descender + textFont.leading)
        pillHeight = max(30 * s, line + 8 * s)
        edgeInset = 4 * s
        cellPadding = 9 * s
        cellSpacing = 2 * s
        chevronWidth = 30 * s
        maxLineWidth = 520 * CGFloat(textSize) / 18
        cardRadius = 12 * s
        numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11 * s, weight: .regular)
        commentFont = NSFont.systemFont(ofSize: 12 * s)
        badgeFont = NSFont.systemFont(ofSize: 12 * s, weight: .bold)
        typedFont = NSFont.monospacedSystemFont(ofSize: 14 * s, weight: .regular)
        typedCaretFont = NSFont.monospacedSystemFont(ofSize: 14 * s, weight: .bold)
        hintFont = NSFont.systemFont(ofSize: 13 * s)
    }

    init(_ config: AppConfig?) {
        self.init(barSize: config?.candidateBarSizePreference ?? "medium",
                  textSize: config?.candidateTextSizeValue ?? AppConfig.defaultCandidateTextSize)
    }
}

/// The one panel Fluent shows, for English and 小鹤双拼 alike, styled after
/// the system shuangpin input method: a capsule with a mode badge, then
/// candidates with the highlighted one on an accent-color pill, a divider
/// and a chevron that expands it into a grid. It becomes a rounded card when
/// it needs more than one line. System colors throughout, so it follows
/// light and dark. The ⇧⇧ toggle's notice has a panel of its own; one
/// shows at a time. One shared instance; the active controller sets the
/// callbacks when it shows the bar.
final class CandidateBarController {
    static let shared = CandidateBarController()

    private let panel: NSPanel
    private let background = PanelChromeView()
    private let bar = CandidateBarView()
    private let notice = ToggleNoticePanel()
    private var flashToken = 0
    private let offBadge = OffBadgePanel()
    /// Where the off badge goes once no ⇧⇧ notice is on screen; nil while
    /// Fluent is on.
    private var offBadgeRequest: (height: CGFloat, appearance: String, caretRect: NSRect)?
    private var flashing = false

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

    func show(_ content: BarContent, appearance: String, metrics: BarMetrics = .standard, near caretRect: NSRect) {
        flashToken += 1  // cancel any pending flash auto-hide
        notice.hide()
        flashing = false
        present(content, appearance: appearance, metrics: metrics, near: caretRect)
    }

    /// The ⇧⇧ toggle's notice at the caret, which hides itself.
    func flash(enabled: Bool, style: ToggleNoticeStyle, badgeHeight: CGFloat, appearance: String,
               near caretRect: NSRect) {
        flashToken += 1
        let token = flashToken
        panel.orderOut(nil)
        offBadge.hide()
        flashing = true
        notice.show(enabled: enabled, style: style, badgeHeight: badgeHeight, appearance: appearance,
                    near: caretRect)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.flashToken == token else { return }
            self.hide()
            self.flashing = false
            if let request = self.offBadgeRequest {
                self.offBadge.show(height: request.height, appearance: request.appearance, near: request.caretRect)
            }
        }
    }

    func hide() {
        panel.orderOut(nil)
        notice.hide()
    }

    /// The grey badge by the caret while Fluent is off; a ⇧⇧ notice still
    /// on screen goes first.
    func showOffBadge(height: CGFloat, appearance: String, near caretRect: NSRect) {
        offBadgeRequest = (height, appearance, caretRect)
        if !flashing {
            offBadge.show(height: height, appearance: appearance, near: caretRect)
        }
    }

    func hideOffBadge() {
        offBadgeRequest = nil
        offBadge.hide()
    }

    private func present(_ content: BarContent, appearance: String, metrics: BarMetrics, near caretRect: NSRect) {
        PanelPlacement.applyAppearance(appearance, to: panel)
        bar.update(content, metrics: metrics)
        let size = bar.fittingSize
        background.cornerRadius = bar.isCapsule ? size.height / 2 : metrics.cardRadius
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

    private var m = BarMetrics.standard

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
    private var hintFrame: NSRect?
    private var chevronFrame: NSRect?
    private var size = NSSize.zero
    private var hovered: Int?
    private var pressed: Int?
    private var scrollAccumulator: CGFloat = 0
    /// A trackpad gesture turns at most one page.
    private var scrollGesturePaged = false

    /// Pressing the chevron is this index in `pressed`.
    private static let chevronIndex = -1

    /// One line of standard height: drawn as a capsule.
    private(set) var isCapsule = true

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var fittingSize: NSSize { size }

    func update(_ content: BarContent, metrics: BarMetrics) {
        self.content = content
        m = metrics
        hovered = nil
        layoutContent()
        needsDisplay = true
    }

    // MARK: - Layout

    private func layoutContent() {
        let inset = m.edgeInset
        let s = m.scale
        var top = inset
        // Right edge of the badge-and-cells line; the hint and chevron follow
        // it even when the typed line above is wider.
        var maxX: CGFloat = inset
        var typedMaxX: CGFloat = inset

        typedFrame = nil
        if let typed = content.typed {
            let text = typedString(typed)
            let height = ceil(text.boundingRect(with: NSSize(width: m.maxLineWidth, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin]).height)
            let width = min(ceil(text.size().width), m.maxLineWidth)
            let frame = NSRect(x: inset + m.cellPadding, y: top + 4 * s, width: width, height: height)
            typedFrame = frame
            top = frame.maxY + 4 * s
            typedMaxX = frame.maxX + m.cellPadding
        }

        var x = inset
        badgeFrame = nil
        if content.badge != nil || content.badgeSymbol != nil {
            let letters = content.badge.map { ceil(Self.measure($0, m.badgeFont)) + 10 * s } ?? 0
            let width = max(22 * s, letters)
            let frame = NSRect(x: x + 3 * s, y: top + (m.pillHeight - 20 * s) / 2, width: width, height: 20 * s)
            badgeFrame = frame
            x = frame.maxX + 4 * s
        }

        cells = []
        var bottom = top + m.pillHeight
        let widths = content.cells.map(cellWidth)
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
                let left = x + columnWidths[..<column].reduce(0, +) + CGFloat(column) * m.cellSpacing
                frame = NSRect(x: left, y: top + CGFloat(row) * (m.pillHeight + m.cellSpacing),
                               width: columnWidths[column], height: m.pillHeight)
            } else if content.cells.count == 1,
                      widths[offset] > m.maxLineWidth || item.text.contains(where: \.isNewline) {
                // A long English line (or one the model broke into
                // lines) wraps into a taller cell.
                wraps = true
                let width = min(widths[offset], m.maxLineWidth)
                let text = cellString(item, highlighted: false)
                let height = ceil(text.boundingRect(with: NSSize(width: width - 2 * m.cellPadding,
                                                                 height: .greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin]).height)
                frame = NSRect(x: cellX, y: top, width: width, height: max(m.pillHeight, height + 10 * s))
            } else {
                frame = NSRect(x: cellX, y: top, width: widths[offset], height: m.pillHeight)
            }
            cellX = frame.maxX + m.cellSpacing
            cells.append(Cell(content: item, row: row, frame: frame, wraps: wraps))
            bottom = max(bottom, frame.maxY)
            maxX = max(maxX, frame.maxX)
        }
        if cells.isEmpty { maxX = max(maxX, x) }
        maxX = max(maxX, badgeFrame.map { $0.maxX + 4 * s } ?? inset)

        hintFrame = nil
        if let hint = content.enterHint {
            let frame = NSRect(x: maxX + 4 * s, y: top, width: ceil(Self.measure(hint, m.hintFont)) + 4 * s,
                               height: m.pillHeight)
            hintFrame = frame
            maxX = frame.maxX + 4 * s
        }

        chevronFrame = nil
        var width: CGFloat
        if case .none = content.chevron {
            width = maxX + inset + 4 * s
        } else {
            chevronFrame = NSRect(x: maxX + 1, y: top - inset, width: m.chevronWidth, height: m.pillHeight + 2 * inset)
            width = maxX + 1 + m.chevronWidth + inset
        }
        width = max(width, typedMaxX + inset + 4 * s)
        size = NSSize(width: width, height: bottom + inset)
        isCapsule = typedFrame == nil && size.height <= m.pillHeight + 2 * inset + 0.5
    }

    private func cellWidth(_ cell: BarContent.Cell) -> CGFloat {
        var width = m.cellPadding * 2 + Self.measure(cell.text, m.textFont)
        if cell.number != nil { width += Self.measure("8", m.numberFont) + 5 * m.scale }
        if let comment = cell.comment { width += 4 * m.scale + Self.measure(comment, m.commentFont) }
        return ceil(width)
    }

    private static func measure(_ string: String, _ font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    /// Text plus comment, for cells that wrap.
    private func cellString(_ cell: BarContent.Cell, highlighted: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(string: cell.text, attributes: [
            .font: m.textFont, .foregroundColor: highlighted ? NSColor.white : NSColor.labelColor,
        ])
        if let comment = cell.comment {
            result.append(NSAttributedString(string: "  " + comment, attributes: [
                .font: m.commentFont,
                .foregroundColor: highlighted ? NSColor.white.withAlphaComponent(0.75) : NSColor.secondaryLabelColor,
            ]))
        }
        return result
    }

    /// The typed text with a caret bar at the cursor. It is read as much as
    /// the line below it, so it takes the full label color: the secondary
    /// one washed out on the panel's material over a dark terminal (#20).
    private func typedString(_ typed: TypedText) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: m.typedFont, .foregroundColor: NSColor.labelColor]
        let cursor = max(0, min(typed.cursor, typed.raw.count))
        let index = typed.raw.index(typed.raw.startIndex, offsetBy: cursor)
        let result = NSMutableAttributedString(string: String(typed.raw[..<index]), attributes: base)
        result.append(NSAttributedString(string: "|", attributes: [
            .font: m.typedCaretFont, .foregroundColor: NSColor.controlAccentColor,
        ]))
        result.append(NSAttributedString(string: String(typed.raw[index...]), attributes: base))
        return result
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if let typedFrame, let typed = content.typed {
            typedString(typed).draw(with: typedFrame, options: [.usesLineFragmentOrigin])
        }

        if let badgeFrame, let symbol = content.badgeSymbol {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: badgeFrame, xRadius: 6 * m.scale, yRadius: 6 * m.scale).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 11 * m.scale, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let size = image.size
                image.draw(in: NSRect(x: badgeFrame.midX - size.width / 2, y: badgeFrame.midY - size.height / 2,
                                      width: size.width, height: size.height))
            }
        } else if let badgeFrame, let badge = content.badge {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: badgeFrame, xRadius: 6 * m.scale, yRadius: 6 * m.scale).fill()
            let text = NSAttributedString(string: badge, attributes: [
                .font: m.badgeFont, .foregroundColor: NSColor.secondaryLabelColor,
            ])
            let textSize = text.size()
            text.draw(at: NSPoint(x: badgeFrame.midX - textSize.width / 2, y: badgeFrame.midY - textSize.height / 2))
        }

        let highlightedRow = content.highlighted.flatMap { cells.indices.contains($0) ? cells[$0].row : nil }
        for (offset, cell) in cells.enumerated() {
            let isHighlighted = offset == content.highlighted
            if isHighlighted || offset == hovered {
                (isHighlighted ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor).setFill()
                let radius = min(cell.frame.height / 2, cell.wraps ? 8 * m.scale : .greatestFiniteMagnitude)
                NSBezierPath(roundedRect: cell.frame, xRadius: radius, yRadius: radius).fill()
            }
            if cell.wraps {
                let text = cellString(cell.content, highlighted: isHighlighted)
                text.draw(with: cell.frame.insetBy(dx: m.cellPadding, dy: 5 * m.scale), options: [.usesLineFragmentOrigin])
                continue
            }
            let primary: NSColor = isHighlighted ? .white : .labelColor
            let secondary: NSColor = isHighlighted ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
            var x = cell.frame.minX + m.cellPadding
            if let number = cell.content.number {
                // In the grid only the highlighted row is numbered: the
                // number keys pick in it.
                if !content.expanded || cell.row == highlightedRow {
                    _ = drawText("\(number)", m.numberFont, secondary, x: x, in: cell.frame)
                }
                x += Self.measure("8", m.numberFont) + 5 * m.scale
            }
            x += drawText(cell.content.text, m.textFont, primary, x: x, in: cell.frame)
            if let comment = cell.content.comment {
                _ = drawText(comment, m.commentFont, secondary, x: x + 4 * m.scale, in: cell.frame)
            }
        }

        if let hintFrame, let hint = content.enterHint {
            _ = drawText(hint, m.hintFont, .tertiaryLabelColor, x: hintFrame.minX, in: hintFrame)
        }

        // Divider, then the chevron: down to expand (dimmed when there is
        // nothing more), up to collapse the grid.
        if let chevron = chevronFrame {
            NSColor.separatorColor.setFill()
            NSRect(x: chevron.minX, y: chevron.minY + 10 * m.scale, width: 1, height: chevron.height - 20 * m.scale).fill()
            let expanded: Bool
            let enabled: Bool
            switch content.chevron {
            case .none: return
            case .more(let isEnabled): (expanded, enabled) = (false, isEnabled)
            case .less: (expanded, enabled) = (true, true)
            }
            let config = NSImage.SymbolConfiguration(pointSize: 12 * m.scale, weight: .semibold)
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

    /// A mouse wheel turns a page per notch (its deltas are lines); a
    /// trackpad turns one page per swipe (its deltas are points), ignoring
    /// momentum, so a flick doesn't skip pages.
    override func scrollWheel(with event: NSEvent) {
        let delta: Int
        if event.hasPreciseScrollingDeltas {
            if event.phase == .began {
                scrollAccumulator = 0
                scrollGesturePaged = false
            }
            guard event.momentumPhase.isEmpty, !scrollGesturePaged else { return }
            scrollAccumulator += event.scrollingDeltaY
            guard abs(scrollAccumulator) > 20 else { return }
            scrollGesturePaged = true
            delta = scrollAccumulator < 0 ? 1 : -1
        } else {
            guard event.scrollingDeltaY != 0 else { return }
            delta = event.scrollingDeltaY < 0 ? 1 : -1
        }
        if (delta > 0 && content.canPageForward) || (delta < 0 && content.canPageBack) { onPage?(delta) }
    }
}
