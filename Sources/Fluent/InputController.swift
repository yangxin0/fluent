import Cocoa
import InputMethodKit
import Carbon.HIToolbox
import os.log
import FluentCore

private let ctlLog = Logger(subsystem: "com.yangxin.inputmethod.Fluent", category: "controller")

/// Shared across all controller instances (one per client app) so the mode
/// and config stay consistent everywhere.
private enum Shared {
    static let configStore = ConfigStore()
    static var mode: Mode = {
        // Fall back to the mode saved under the app's former name.
        let raw = UserDefaults.standard.string(forKey: "mode")
            ?? UserDefaults(suiteName: "com.yangxin.inputmethod.EnglishInput")?.string(forKey: "mode")
        return raw.flatMap(Mode.init(rawValue:)) ?? .fix
    }() {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    /// Double-tap Shift toggles this; when off every key passes through
    /// untouched (for terminals, passwords, code…). Not persisted — a fresh
    /// launch always starts enabled.
    static var enabled = true
    /// 小鹤双拼 Chinese mixed into English typing (IME menu toggle).
    static var shuangpinEnabled = UserDefaults.standard.object(forKey: "shuangpin") as? Bool ?? true {
        didSet { UserDefaults.standard.set(shuangpinEnabled, forKey: "shuangpin") }
    }
}

private enum Key {
    static let enter: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let backspace: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
}

private let maxCompositionLength = 500
private let maxChineseKeys = 60
private let chinesePageSize = 6
/// Rows of `chinesePageSize` candidates in the expanded bar.
private let chineseGridRows = 5
/// Chinese readings shown after an English word that is also shuangpin; the
/// word itself is candidate 1 of the bar.
private let maxAlternatives = 5

@objc(InputController)
class InputController: IMKInputController {
    private var state = CompositionState()
    /// Monotonic across compositions; guards against stale stream updates.
    private var generation = 0
    private let engine = RewriteEngine()
    /// The last text this IME committed in this client was Chinese: then
    /// punctuation is Chinese too, and shuangpin goes first more readily.
    private var lastCommitWasChinese = false
    private var punctuation = ChinesePunctuation()

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        Shared.configStore.writeTemplateIfMissing()
        engine.onUpdate = { [weak self] update in
            self?.handleEngineUpdate(update)
        }
    }

    // MARK: - IMK lifecycle

    override func recognizedEvents(_ sender: Any!) -> Int {
        // flagsChanged is only a fallback for the ⇧⇧ toggle (see
        // ShiftTapMonitor); many clients never forward it.
        ctlLog.debug("recognizedEvents queried by \(self.client()?.bundleIdentifier() ?? "?", privacy: .public)")
        return Int(NSEvent.EventTypeMask.keyDown.union(.flagsChanged).rawValue)
    }

    override func activateServer(_ sender: Any!) {
        ctlLog.notice("activateServer: \(self.client()?.bundleIdentifier() ?? "?", privacy: .public) enabled=\(Shared.enabled, privacy: .public)")
        ShiftTapMonitor.shared.sessionActivated(self)
        state.reset()
        lastCommitWasChinese = false
        PreviewPanelController.shared.hide()
        CandidateBarController.shared.hide()
    }

    override func deactivateServer(_ sender: Any!) {
        ctlLog.notice("deactivateServer: \(self.client()?.bundleIdentifier() ?? "?", privacy: .public)")
        ShiftTapMonitor.shared.sessionDeactivated(self)
        // Focus is leaving — never silently drop what the user typed.
        commitRaw()
    }

    override func commitComposition(_ sender: Any!) {
        commitRaw()
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let enabledItem = NSMenuItem(title: "Enabled (⇧⇧ to toggle)",
                                     action: #selector(toggleEnabledFromMenu(_:)),
                                     keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = Shared.enabled ? .on : .off
        menu.addItem(enabledItem)
        let shuangpinItem = NSMenuItem(title: "小鹤双拼 Chinese",
                                       action: #selector(toggleShuangpin(_:)), keyEquivalent: "")
        shuangpinItem.target = self
        shuangpinItem.state = Shared.shuangpinEnabled ? .on : .off
        menu.addItem(shuangpinItem)
        menu.addItem(.separator())
        for mode in Mode.allCases {
            let item = NSMenuItem(title: mode.displayName,
                                  action: #selector(selectMode(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == Shared.mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Config File",
                              action: #selector(openConfig(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let reload = NSMenuItem(title: "Reload Config",
                                action: #selector(reloadConfig(_:)), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)
        return menu
    }

    // MARK: - Key handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        if event.type == .flagsChanged {
            ShiftTapMonitor.shared.handleIMKEvent(event)
            return false
        }
        guard event.type == .keyDown else { return false }
        // A real keypress between two Shift taps means it wasn't a toggle.
        ShiftTapMonitor.shared.interrupt()

        guard Shared.enabled else { return false }

        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift, .function])

        // Never intercept command shortcuts; end composition first so the
        // shortcut acts on committed text.
        if flags.contains(.command) {
            commitRaw()
            return false
        }

        // Ctrl+Tab cycles the mode, but only while composing (outside
        // composition it belongs to the app, e.g. browser tab switching).
        if event.keyCode == Key.tab && flags == [.control] && state.isComposing && state.chinese == nil {
            Shared.mode = Shared.mode.next
            requestRewrite()
            refreshPanel()
            return true
        }

        if state.chinese != nil {
            return handleChinese(event, flags: flags)
        }

        // Editing keys only get their plain meaning here (plus Shift for
        // Enter/Backspace, which has no distinct system meaning). Any other
        // modifier combo — ⌥← word motion, ⌥⌫ word delete, ⇧← selection… —
        // is committed and passed through so the app applies its own
        // semantics instead of us collapsing it to a single-character action.
        // Arrow keys always carry `.function`, so it is not a user modifier.
        let mods = flags.subtracting(.function)
        let editingKeys: Set<UInt16> = [Key.enter, Key.keypadEnter, Key.escape,
                                        Key.backspace, Key.left, Key.right]
        let shiftOK: Set<UInt16> = [Key.enter, Key.keypadEnter, Key.backspace]
        if editingKeys.contains(event.keyCode),
           !mods.isEmpty,
           !(mods == [.shift] && shiftOK.contains(event.keyCode))
        {
            commitRaw()
            return false
        }

        switch event.keyCode {
        case Key.enter, Key.keypadEnter:
            guard state.isComposing else { return false }
            // The bar for a word that is also shuangpin shows it as typed,
            // so Enter inserts that rather than an unseen rewrite.
            if flags.contains(.shift) || !state.alternatives.isEmpty {
                commitRaw()
            } else {
                commit(state.committableImproved ?? state.raw)
            }
            return true

        case Key.escape:
            guard state.isComposing else { return false }
            cancelCurrentComposition()
            return true

        case Key.backspace:
            guard state.isComposing else { return false }
            state.backspace()
            if state.isComposing {
                afterEdit()
            } else {
                cancelCurrentComposition()
            }
            return true

        case Key.left:
            guard state.isComposing else { return false }
            clearAlternatives()
            state.moveLeft()
            updateMarkedText()
            refreshPanel()  // the typed-text line tracks the caret
            return true

        case Key.right:
            guard state.isComposing else { return false }
            clearAlternatives()
            state.moveRight()
            updateMarkedText()
            refreshPanel()
            return true

        case Key.up, Key.down, Key.tab, Key.forwardDelete:
            commitRaw()
            return false

        default:
            break
        }

        // Printable input (plain or shifted). Function/arrow keys arrive in
        // the Unicode private-use area — treat those as non-printable.
        if flags.isSubset(of: [.shift]),
           let chars = event.characters, !chars.isEmpty,
           let scalar = chars.unicodeScalars.first,
           !(0xF700...0xF8FF).contains(scalar.value),
           scalar.value >= 0x20, scalar.value != 0x7F
        {
            // Number keys pick from the bar shown for a word that is also
            // shuangpin: 1 is the English word as typed, 2… its readings.
            if !state.alternatives.isEmpty, chars.count == 1, let key = chars.first, key.isASCII,
               let digit = key.wholeNumberValue, digit >= 1, digit - 1 <= state.alternatives.count {
                pickEnglishOrAlternative(digit - 1)
                return true
            }
            // Punctuation right after Chinese text is Chinese too.
            if !state.isComposing, lastCommitWasChinese, Shared.shuangpinEnabled, chars.count == 1,
               let key = chars.first, let converted = punctuation.convert(key) {
                client()?.insertText(converted, replacementRange: NSRange(location: NSNotFound, length: 0))
                return true
            }
            if state.raw.count + chars.count <= maxCompositionLength {
                state.insert(chars)
            }
            afterEdit()
            return true
        }

        // Anything else (Ctrl/Option combos, dead keys…): end composition
        // safely and let the client handle the event.
        commitRaw()
        return false
    }

    /// Also called by ShiftTapMonitor when a double tap fires.
    func toggleEnabled() {
        Shared.enabled.toggle()
        ctlLog.notice("enabled is now \(Shared.enabled, privacy: .public)")
        if !Shared.enabled {
            // Don't strand an in-progress composition as marked text.
            commitRaw()
        }
        let appearance = Shared.configStore.current()?.appearancePreference ?? "auto"
        // The state word sits on a colored highlight so it reads at a glance:
        // green for ON, red for OFF (system colors adapt to light and dark),
        // in bold black for contrast on both. Thin spaces pad the highlight.
        let message = NSMutableAttributedString(
            string: "\u{2009}\(Shared.enabled ? "ON" : "OFF")\u{2009}",
            attributes: [
                .backgroundColor: Shared.enabled ? NSColor.systemGreen : NSColor.systemRed,
                .foregroundColor: NSColor.black,
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            ])
        message.append(NSAttributedString(string: " Fluent"))
        if !Shared.enabled {
            message.append(NSAttributedString(string: "\n⇧⇧ to re-enable"))
        }
        PreviewPanelController.shared.flash(message: message, appearance: appearance, near: caretRect())
    }

    // MARK: - 小鹤双拼

    /// Keys while composing Chinese, like the system shuangpin input method:
    /// Space or 1–6 picks, ←/→ move the highlight, ↑/↓ and -/= turn pages
    /// (↑/↓ move by row in the grid), Tab expands the bar into a grid, Enter
    /// inserts the keys as typed, Esc cancels (or collapses the grid),
    /// punctuation commits the highlighted candidate followed by Chinese
    /// punctuation.
    private func handleChinese(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard var composer = state.chinese else { return false }
        // Only plain and shifted keys compose; any other combo ends the
        // composition safely and goes to the app.
        guard flags.subtracting(.function).isSubset(of: [.shift]) else {
            commitRaw()
            return false
        }
        switch event.keyCode {
        case Key.enter, Key.keypadEnter:
            commit(state.chinesePrefix + composer.keys)
            return true
        case Key.escape:
            if state.chineseExpanded {
                toggleChineseGrid()
            } else {
                cancelCurrentComposition()
            }
            return true
        case Key.backspace:
            state.chineseExpanded = false
            if composer.backspace() {
                state.chinese = composer
                updateMarkedText()
                refreshPanel()
            } else if state.chinesePrefix.isEmpty {
                cancelCurrentComposition()
            } else {
                // Every key is gone: back to what was typed before them.
                switchToEnglish(state.chinesePrefix)
            }
            return true
        case Key.left, Key.right:
            composer.moveHighlight(by: event.keyCode == Key.left ? -1 : 1)
            state.chinese = composer
            refreshPanel()
            return true
        case Key.up, Key.down:
            let delta = event.keyCode == Key.up ? -1 : 1
            if state.chineseExpanded {
                composer.moveHighlight(by: delta * composer.pageSize)
                state.chinese = composer
                refreshPanel()
            } else {
                turnChinesePage(by: delta)
            }
            return true
        case Key.tab:
            toggleChineseGrid()
            return true
        case Key.forwardDelete:
            commitRaw()
            return false
        default:
            break
        }
        guard let chars = event.characters, chars.count == 1, let key = chars.first,
              let scalar = key.unicodeScalars.first,
              !(0xF700...0xF8FF).contains(scalar.value), scalar.value >= 0x20, scalar.value != 0x7F
        else {
            commitRaw()
            return false
        }
        switch key {
        case " ":
            pickChinese(composer.highlighted)
        case "1"..."9" where key.isASCII:
            pickChinese(onPage: key.wholeNumberValue! - 1)  // past the page: ignored
        case "0":
            break
        case "-", "=":
            turnChinesePage(by: key == "-" ? -1 : 1)
        case "a"..."z" where key.isASCII:
            guard composer.keys.count < maxChineseKeys else { break }
            composer.append(key)
            state.chinese = composer
            state.chineseExpanded = false
            // Until a word is picked, the keys can still turn out to be
            // English: a whole word after Chinese text, or no longer shuangpin.
            if composer.segments.isEmpty,
               chineseRank(for: Substring(composer.keys), prefix: state.chinesePrefix) != .primary {
                switchToEnglish(state.chinesePrefix + composer.keys)
            } else {
                updateMarkedText()
                refreshPanel()
            }
        case "A"..."Z" where key.isASCII:
            // A capital starts English: picked words stay, the rest is English.
            var english = state.chinesePrefix + composer.keys
            if !composer.segments.isEmpty {
                commitChinese(state.chinesePrefix + composer.confirmedText)
                english = String(composer.remainingKeys)
            }
            switchToEnglish(english + String(key))
        default:
            let symbol = punctuation.convert(key) ?? String(key)
            commitChinese(state.chinesePrefix + composer.highlightedText + symbol)
        }
        return true
    }

    /// Picks `candidates[index]`, committing (and learning the picks) once
    /// every key is converted.
    private func pickChinese(_ index: Int) {
        guard var composer = state.chinese else { return }
        if let text = composer.select(index) {
            Shuangpin.shared?.learn(composer.pickedWords)
            commitChinese(state.chinesePrefix + text)
        } else {
            state.chinese = composer
            state.chineseExpanded = false
            updateMarkedText()
            refreshPanel()
        }
    }

    private func toggleChineseGrid() {
        guard state.chinese != nil else { return }
        state.chineseExpanded.toggle()
        refreshPanel()
    }

    private func pickChinese(onPage index: Int) {
        guard let composer = state.chinese, index >= 0, index < composer.pageCandidates.count else { return }
        pickChinese(composer.page * composer.pageSize + index)
    }

    private func turnChinesePage(by delta: Int) {
        guard var composer = state.chinese else { return }
        composer.turnPage(by: delta)
        state.chinese = composer
        refreshPanel()
    }

    /// Leaves Chinese composing with `text` as the English composition.
    private func switchToEnglish(_ text: String) {
        state.chinese = nil
        state.chinesePrefix = ""
        state.raw = ""
        state.cursor = 0
        state.insert(text)
        afterEdit()
    }

    /// `prefix` is what the composition holds before the run. English words
    /// in it make an English sentence, unless they follow Chinese text.
    private func chineseRank<P: StringProtocol>(for run: Substring, prefix: P) -> ChineseRank {
        guard Shared.shuangpinEnabled, let shuangpin = Shuangpin.shared else { return .none }
        let context: RunContext = lastCommitWasChinese ? .afterChinese
            : prefix.contains { !$0.isWhitespace } ? .afterEnglish : .fresh
        return ShuangpinPolicy.rank(run: run, context: context, english: shuangpin.english)
    }

    /// After an English edit, looks at the letters at the caret: switches to
    /// Chinese when they are shuangpin that cannot be English (returns true),
    /// else prepares their Chinese readings as alternatives.
    private func updateShuangpin() -> Bool {
        clearAlternatives()
        guard let shuangpin = Shuangpin.shared, state.cursor == state.raw.count else { return false }
        let run = ShuangpinPolicy.run(in: state.raw, cursor: state.cursor)
        guard !run.isEmpty else { return false }
        let prefix = state.raw.dropLast(run.count)
        switch chineseRank(for: run, prefix: prefix) {
        case .none:
            return false
        case .alternatives:
            state.alternatives = Array(shuangpin.translator.candidates(for: run).prefix(maxAlternatives))
            return false
        case .primary:
            engine.cancel()
            generation += 1  // drop any rewrite still streaming for the English text
            state.chinesePrefix = String(prefix)
            state.chinese = ShuangpinComposer(keys: String(run), translator: shuangpin.translator,
                                              pageSize: chinesePageSize)
            state.raw = ""
            state.cursor = 0
            updateMarkedText()
            refreshPanel()
            return true
        }
    }

    private func clearAlternatives() {
        state.alternatives = []
    }

    /// Index 0 of the bar for an ambiguous word is the word itself.
    private func pickEnglishOrAlternative(_ index: Int) {
        if index == 0 {
            commitRaw()
        } else if index - 1 < state.alternatives.count {
            pickAlternative(state.alternatives[index - 1])
        }
    }

    /// Commits the English typed before the letters at the caret as is, then
    /// the picked Chinese; keys it leaves unconverted start a new composition.
    private func pickAlternative(_ candidate: ChineseCandidate) {
        let run = ShuangpinPolicy.run(in: state.raw, cursor: state.cursor)
        let prefix = String(state.raw.dropLast(run.count))
        let rest = String(run.dropFirst(candidate.keyCount))
        Shuangpin.shared?.learn([(candidate.text, candidate.code)])
        commitChinese(prefix + candidate.text)
        if !rest.isEmpty {
            state.insert(rest)
            afterEdit()
        }
    }

    // MARK: - Composition plumbing

    private func afterEdit() {
        if updateShuangpin() { return }
        updateMarkedText()
        requestRewrite()
        refreshPanel()
    }

    private func requestRewrite() {
        generation += 1
        state.improved = ""
        state.status = .idle
        if state.raw.count >= maxCompositionLength {
            // Stop re-querying huge buffers; Enter still works with the raw
            // text. Also drop the request for the previous buffer — its
            // updates would be discarded by the generation guard anyway.
            engine.cancel()
            return
        }
        engine.textChanged(raw: state.raw,
                           instructions: Shared.mode.instructions,
                           generation: generation,
                           config: Shared.configStore.current())
    }

    private func handleEngineUpdate(_ update: RewriteEngine.Update) {
        switch update {
        case .began(let gen):
            guard gen == generation, state.isComposing else { return }
            state.status = .improving
        case .delta(let gen, let accumulated):
            guard gen == generation, state.isComposing else { return }
            state.status = .improving
            state.improved = accumulated
        case .done(let gen, let text):
            guard gen == generation, state.isComposing else { return }
            state.improved = text
            state.status = text.isEmpty ? .failed("empty response") : .done
        case .failed(let gen, let message):
            guard gen == generation, state.isComposing else { return }
            state.status = .failed(message)
            ctlLog.error("rewrite failed: \(message, privacy: .public)")
        }
        refreshPanel()
    }

    private func updateMarkedText() {
        guard let client = client() else { return }
        if let composer = state.chinese {
            // Converted words, then the remaining keys grouped per syllable
            // (`这是 ge`), caret at the end.
            let text = NSMutableAttributedString(string: state.chinesePrefix + composer.confirmedText,
                                                 attributes: markAttributes(kTSMHiliteConvertedText))
            text.append(NSAttributedString(string: Xiaohe.grouped(composer.remainingKeys),
                                           attributes: markAttributes(kTSMHiliteSelectedRawText)))
            client.setMarkedText(text, selectionRange: NSRange(location: text.length, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            return
        }
        client.setMarkedText(
            NSAttributedString(string: state.raw, attributes: markAttributes(kTSMHiliteConvertedText)),
            selectionRange: NSRange(location: state.cursorUTF16Offset, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func markAttributes(_ style: Int) -> [NSAttributedString.Key: Any] {
        mark(forStyle: style, at: NSRange(location: NSNotFound, length: 0))
            as? [NSAttributedString.Key: Any] ?? [:]
    }

    private func refreshPanel() {
        guard state.isComposing else {
            PreviewPanelController.shared.hide()
            CandidateBarController.shared.hide()
            return
        }
        if let composer = state.chinese {
            PreviewPanelController.shared.hide()
            let bar = CandidateBarController.shared
            bar.onSelect = { [weak self] index in self?.pickChinese(index) }
            bar.onPage = { [weak self] delta in self?.turnChinesePage(by: delta) }
            bar.onToggleExpanded = { [weak self] in self?.toggleChineseGrid() }
            let shown = composer.gridRange(rows: state.chineseExpanded ? chineseGridRows : 1)
            bar.show(candidates: composer.candidates[shown], highlighted: composer.highlighted,
                     columns: composer.pageSize, expanded: state.chineseExpanded,
                     canPageBack: shown.lowerBound > 0, canPageForward: shown.upperBound < composer.candidates.count,
                     appearance: Shared.configStore.current()?.appearancePreference ?? "auto",
                     near: caretRect())
            return
        }
        if !state.alternatives.isEmpty {
            // A word that is both English and shuangpin: the same bar, with
            // the word as typed first (`1 make  2 马克 …`).
            PreviewPanelController.shared.hide()
            let run = ShuangpinPolicy.run(in: state.raw, cursor: state.cursor)
            let shown = [ChineseCandidate(text: String(run), keyCount: run.count, code: [], weight: 0)]
                + state.alternatives
            let bar = CandidateBarController.shared
            bar.onSelect = { [weak self] index in self?.pickEnglishOrAlternative(index) }
            bar.onPage = nil
            bar.onToggleExpanded = nil
            bar.show(candidates: shown[...], highlighted: 0, columns: chinesePageSize, expanded: false,
                     canPageBack: false, canPageForward: false,
                     appearance: Shared.configStore.current()?.appearancePreference ?? "auto",
                     near: caretRect())
            return
        }
        CandidateBarController.shared.hide()
        // Short hints, like the bar's: what Enter inserts right now (the
        // improvement once it is ready, else the text as typed).
        let status: String
        switch state.status {
        case .idle:
            status = state.raw.count >= maxCompositionLength ? "too long · ↵ as typed" : "↵ as typed"
        case .improving:
            status = "improving… · ↵ as typed"
        case .done:
            status = "↵"
        case .failed(let message):
            status = "⚠ \(message) · ↵ as typed"
        }
        let config = Shared.configStore.current()
        let appearance = config?.appearancePreference ?? "auto"
        let (caret, attrs) = caretRectAndAttributes()
        if isTerminalClient(preference: config?.terminalModePreference ?? "auto",
                            extra: config?.terminalApps ?? []) {
            updateTypedInPanel(caret: caret, attributes: attrs,
                               configuredCellWidth: config?.terminalCellWidth)
        }
        PreviewPanelController.shared.show(
            mode: Shared.mode,
            typed: state.showTypedInPanel ? TypedText(raw: state.raw, cursor: state.cursor) : nil,
            text: state.improved,
            status: status,
            appearance: appearance,
            near: caret
        )
    }

    // MARK: - Terminal edge detection

    private func isTerminalClient(preference: String, extra: [String]) -> Bool {
        switch preference {
        case "always": return true
        case "never": return false
        default: return TerminalClients.isTerminal(bundleID: client()?.bundleIdentifier(), extra: extra)
        }
    }

    /// Terminals clip marked text at the window edge. Predict when the
    /// composition is about to reach it and, from then until the composition
    /// ends, show the typed text in the panel too (like Rime's non-inline
    /// preedit).
    private func updateTypedInPanel(caret: NSRect, attributes: [NSAttributedString.Key: Any],
                                    configuredCellWidth: Double?) {
        guard !state.showTypedInPanel else { return }
        // The panel also refreshes on every stream delta; only re-measure
        // when the typed text actually changed.
        guard state.raw.count != state.edgeCheckedCount else { return }
        state.edgeCheckedCount = state.raw.count
        if caret == .zero {
            state.showTypedInPanel = state.raw.count >= EdgeTracker.fallbackCharacterLimit
            return
        }
        // Re-measured on every keystroke: windows move and resize.
        let window = clientWindowBounds(containing: caret)
        let edgeX = window.map { Double($0.maxX) } ?? Double(NSScreen.main?.visibleFrame.maxX ?? 0)
        // Exact cell width: the config override, else the client's font if
        // it reports one (advance of "M" in a monospace font is the cell).
        var known: Double? = configuredCellWidth.flatMap { $0 > 0 ? $0 : nil }
        if known == nil, let font = attributes[.font] as? NSFont {
            known = Double(("M" as NSString).size(withAttributes: [.font: font]).width)
        }
        let reached = state.edgeTracker.update(caretMinX: Double(caret.minX),
                                               caretMaxX: Double(caret.maxX),
                                               caretHeight: Double(caret.height),
                                               characterCount: state.raw.count,
                                               edgeX: edgeX,
                                               knownCellWidth: known)
        // Persisted (default level) so `log show` can read it when tuning.
        let attrKeys = attributes.keys.map(\.rawValue).sorted().joined(separator: ",")
        ctlLog.notice("edge check: caret=\(NSStringFromRect(caret), privacy: .public) window=\(window.map(NSStringFromRect) ?? "none", privacy: .public) cell=\(known.map { String(format: "%.2f", $0) } ?? "est", privacy: .public) attrs=[\(attrKeys, privacy: .public)] follows=\(String(describing: self.state.edgeTracker.caretFollowsText), privacy: .public) chars=\(self.state.raw.count, privacy: .public) reached=\(reached, privacy: .public)")
        state.showTypedInPanel = reached
    }

    /// Bounds (AppKit screen coordinates) of the client's normal window
    /// containing the caret, else its frontmost normal window. Window bounds
    /// need no special permission.
    private func clientWindowBounds(containing caret: NSRect) -> NSRect? {
        guard let bundleID = client()?.bundleIdentifier() else { return nil }
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        // CG window bounds are top-left based on the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let caretPoint = NSPoint(x: caret.midX, y: primaryHeight - caret.midY)
        var first: NSRect?
        for info in list {  // front-to-back
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width > 100, bounds.height > 100
            else { continue }
            if bounds.contains(caretPoint) { return bounds }
            if first == nil { first = bounds }
        }
        return first
    }

    private func caretRect() -> NSRect {
        caretRectAndAttributes().0
    }

    /// The caret rect plus whatever text attributes the client reports for
    /// it (some include the font, which gives an exact cell width).
    private func caretRectAndAttributes() -> (NSRect, [NSAttributedString.Key: Any]) {
        guard let client = client() else { return (.zero, [:]) }
        var rect = NSRect.zero
        let attrs = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return (rect, attrs as? [NSAttributedString.Key: Any] ?? [:])
    }

    /// Commits what is shown, as typed (Chinese words already picked stay).
    private func commitRaw() {
        guard state.isComposing else { return }
        if let composer = state.chinese {
            commit(state.chinesePrefix + composer.interruptedText)
        } else {
            commit(state.raw)
        }
    }

    private func commit(_ text: String) {
        engine.cancel()
        clearAlternatives()
        if let client = client(), !text.isEmpty {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        state.reset()
        lastCommitWasChinese = false
        PreviewPanelController.shared.hide()
        CandidateBarController.shared.hide()
    }

    private func commitChinese(_ text: String) {
        commit(text)
        lastCommitWasChinese = true
    }

    private func cancelCurrentComposition() {
        engine.cancel()
        clearAlternatives()
        CandidateBarController.shared.hide()
        if let client = client() {
            client.setMarkedText(
                NSAttributedString(string: ""),
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }
        state.reset()
        PreviewPanelController.shared.hide()
    }

    // MARK: - Menu actions (IMK may pass the NSMenuItem or a dictionary)

    private func menuItem(from sender: Any?) -> NSMenuItem? {
        if let item = sender as? NSMenuItem { return item }
        if let dict = sender as? [String: Any] {
            return dict["IMKCommandMenuItem"] as? NSMenuItem
        }
        return nil
    }

    @objc func selectMode(_ sender: Any?) {
        guard let raw = menuItem(from: sender)?.representedObject as? String,
              let mode = Mode(rawValue: raw) else { return }
        Shared.mode = mode
        if state.isComposing && state.chinese == nil {
            requestRewrite()
            refreshPanel()
        }
    }

    @objc func toggleEnabledFromMenu(_ sender: Any?) {
        toggleEnabled()
    }

    @objc func openConfig(_ sender: Any?) {
        Shared.configStore.writeTemplateIfMissing()
        NSWorkspace.shared.open(Shared.configStore.configURL)
    }

    @objc func toggleShuangpin(_ sender: Any?) {
        Shared.shuangpinEnabled.toggle()
        if state.chinese != nil {
            commitRaw()
        } else if state.isComposing {
            afterEdit()
        }
    }

    @objc func reloadConfig(_ sender: Any?) {
        Shared.configStore.invalidate()
        if state.isComposing && state.chinese == nil {
            requestRewrite()
            refreshPanel()
        }
    }
}
