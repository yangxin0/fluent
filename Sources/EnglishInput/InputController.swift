import Cocoa
import InputMethodKit
import Carbon.HIToolbox
import os.log
import EnglishInputCore

private let ctlLog = Logger(subsystem: "com.yangxin.inputmethod.EnglishInput", category: "controller")

/// Shared across all controller instances (one per client app) so the mode
/// and config stay consistent everywhere.
private enum Shared {
    static let configStore = ConfigStore()
    static var mode: Mode = {
        if let raw = UserDefaults.standard.string(forKey: "mode"), let m = Mode(rawValue: raw) {
            return m
        }
        return .fix
    }() {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    /// Double-tap Shift toggles this; when off every key passes through
    /// untouched (for terminals, passwords, code…). Not persisted — a fresh
    /// launch always starts enabled.
    static var enabled = true
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

@objc(InputController)
class InputController: IMKInputController {
    private var state = CompositionState()
    /// Monotonic across compositions; guards against stale stream updates.
    private var generation = 0
    private let engine = RewriteEngine()

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
        PreviewPanelController.shared.hide()
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
        if event.keyCode == Key.tab && flags == [.control] && state.isComposing {
            Shared.mode = Shared.mode.next
            requestRewrite()
            refreshPanel()
            return true
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
            if flags.contains(.shift) {
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
            state.moveLeft()
            updateMarkedText()
            refreshPanel()  // the typed-text line tracks the caret
            return true

        case Key.right:
            guard state.isComposing else { return false }
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
        PreviewPanelController.shared.flash(
            message: Shared.enabled ? "English Input ON" : "English Input OFF\n⇧⇧ to re-enable",
            appearance: appearance,
            near: caretRect()
        )
    }

    // MARK: - Composition plumbing

    private func afterEdit() {
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
        let attrs = mark(forStyle: kTSMHiliteConvertedText,
                         at: NSRange(location: NSNotFound, length: 0)) as? [NSAttributedString.Key: Any]
        client.setMarkedText(
            NSAttributedString(string: state.raw, attributes: attrs ?? [:]),
            selectionRange: NSRange(location: state.cursorUTF16Offset, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func refreshPanel() {
        guard state.isComposing else {
            PreviewPanelController.shared.hide()
            return
        }
        let status: String
        switch state.status {
        case .idle:
            status = state.raw.count >= maxCompositionLength
                ? "too long — ↵ inserts as typed" : "↵ inserts as typed"
        case .improving:
            status = "improving… (↵ now inserts as typed)"
        case .done:
            status = "↵ insert · ⇧↵ as typed · esc cancel"
        case .failed(let message):
            status = "⚠ \(message) — ↵ inserts as typed"
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

    private func commitRaw() {
        guard state.isComposing else { return }
        commit(state.raw)
    }

    private func commit(_ text: String) {
        engine.cancel()
        if let client = client(), !text.isEmpty {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        state.reset()
        PreviewPanelController.shared.hide()
    }

    private func cancelCurrentComposition() {
        engine.cancel()
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
        if state.isComposing {
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

    @objc func reloadConfig(_ sender: Any?) {
        Shared.configStore.invalidate()
        if state.isComposing {
            requestRewrite()
            refreshPanel()
        }
    }
}
