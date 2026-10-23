import Cocoa
import os.log
import FluentCore

private let voiceLog = Logger(subsystem: "com.yangxin.inputmethod.Fluent", category: "voice")

/// The input method session a recording belongs to: it shows what is heard
/// and takes the text at the end.
protocol VoiceSessionDelegate: AnyObject {
    /// What has been heard so far ("" before the first words); `finishing`
    /// once the recording stopped and the final text is on its way.
    func voiceHeard(_ text: String, finishing: Bool)
    func voiceFinished(_ text: String)
    func voiceFailed(_ message: String)
    func voiceCancelled()
}

/// Voice input (#28): records from the microphone between a start and a
/// stop (the hold key, or two presses of the toggle key), streams it to the
/// engine in use, and hands the text to the session that started it.
final class VoiceInput {
    static let shared = VoiceInput()
    /// A recording stops by itself after this long.
    static let maxDuration: TimeInterval = 60
    /// How long to wait for the final text after the last packet.
    static let finalTimeout: TimeInterval = 8

    enum Phase {
        case idle, listening, finishing
    }

    private(set) var phase = Phase.idle
    private weak var delegate: VoiceSessionDelegate?
    private var capture: MicrophoneCapture?
    private var recognizer: VolcengineRecognizer?
    private var heard = ""
    /// Bumped when a recording ends, so its timers and late events find
    /// nothing to do.
    private var token = 0

    var isActive: Bool { phase != .idle }

    func isOwned(by delegate: VoiceSessionDelegate) -> Bool {
        self.delegate === delegate
    }

    func start(engine: VoiceEngine, hotwords: [String], delegate: VoiceSessionDelegate) {
        guard phase == .idle else { return }
        token += 1
        let token = self.token
        self.delegate = delegate
        phase = .listening
        heard = ""
        delegate.voiceHeard("", finishing: false)
        MicrophoneCapture.requestAccess { [weak self] granted in
            guard let self, self.token == token, self.phase == .listening else { return }
            guard granted else {
                return self.fail("Fluent can't use the microphone: allow it in System Settings ▸ Privacy & Security ▸ Microphone.")
            }
            let recognizer = VolcengineRecognizer(engine: engine, hotwords: hotwords) { [weak self] event in
                self?.handle(event, token: token)
            }
            let capture = MicrophoneCapture()
            capture.onChunk = { [weak recognizer] chunk in recognizer?.send(chunk) }
            do {
                try capture.start()
            } catch {
                return self.fail("The microphone didn't start: \(error.localizedDescription)")
            }
            recognizer.start()
            self.recognizer = recognizer
            self.capture = capture
            voiceLog.notice("listening, engine \(engine.name, privacy: .public), \(hotwords.count, privacy: .public) hotwords")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxDuration) { [weak self] in
                guard let self, self.token == token, self.phase == .listening else { return }
                voiceLog.notice("\(Int(Self.maxDuration), privacy: .public) s reached: stopping")
                self.stop()
            }
        }
    }

    /// Stops recording; the final text follows.
    func stop() {
        guard phase == .listening else { return }
        guard let capture, let recognizer else {
            // Let go before the microphone was granted: nothing was recorded.
            return cancel()
        }
        phase = .finishing
        recognizer.finish(with: capture.stop())
        self.capture = nil
        delegate?.voiceHeard(heard, finishing: true)
        let token = self.token
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finalTimeout) { [weak self] in
            guard let self, self.token == token, self.phase == .finishing else { return }
            voiceLog.error("no final text in \(Int(Self.finalTimeout), privacy: .public) s: using what was heard")
            self.finish(with: self.heard)
        }
    }

    /// Ends the recording and drops its text.
    func cancel() {
        guard phase != .idle else { return }
        voiceLog.notice("cancelled")
        let delegate = self.delegate
        end()
        delegate?.voiceCancelled()
    }

    private func handle(_ event: VolcengineRecognizer.Event, token: Int) {
        guard token == self.token, phase != .idle else { return }
        switch event {
        case .partial(let text):
            heard = text
            delegate?.voiceHeard(text, finishing: phase == .finishing)
        case .final(let text):
            finish(with: text.isEmpty ? heard : text)
        case .failed(let message):
            if phase == .finishing, !heard.isEmpty {
                voiceLog.error("no final text (\(message, privacy: .public)): using what was heard")
                finish(with: heard)
            } else {
                fail(message)
            }
        }
    }

    private func finish(with text: String) {
        voiceLog.notice("heard \(text.count, privacy: .public) characters")
        let delegate = self.delegate
        end()
        delegate?.voiceFinished(text)
    }

    private func fail(_ message: String) {
        voiceLog.error("failed: \(message, privacy: .public)")
        let delegate = self.delegate
        end()
        delegate?.voiceFailed(message)
    }

    private func end() {
        token += 1
        capture?.stop()
        capture = nil
        recognizer?.cancel()
        recognizer = nil
        phase = .idle
        delegate = nil
        heard = ""
    }
}

/// Hold to talk: Fn or one side's modifier held alone for a moment starts
/// a recording, and letting go of it stops one; a shortcut held (`ctrl-space`)
/// starts one at once, and letting go of its key stops it. Modifiers come
/// from the global flagsChanged events ShiftTapMonitor sees, so they work
/// in apps that hand an input method no modifiers.
///
/// It must not get in the way of shortcuts made with the same key (⌘C with
/// Left ⌘): a key pressed before the recording starts makes it a shortcut,
/// one pressed during a recording cancels it and goes to the app (see
/// InputController), and letting go after any key went to the app, even
/// one Fluent never saw, discards what was recorded.
final class VoiceHoldKey {
    static let shared = VoiceHoldKey()
    /// How long a modifier has to be held alone before recording starts.
    static let delay: TimeInterval = 0.3

    /// The key to watch, read on each event: `.off` while voice can't start.
    var key: () -> VoiceSettings.HoldKey = { .off }
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}

    private var pending: DispatchWorkItem?
    /// A recording this key started is running.
    private(set) var isHolding = false
    /// Key presses so far when it started, for a modifier hold.
    private var keysAtStart: UInt32?
    /// The held shortcut's key and modifiers, for a shortcut hold.
    private var shortcut: (keyCode: UInt16, flags: NSEvent.ModifierFlags)?
    private var poll: Timer?

    func flagsChanged(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift, .function])
        if let shortcut, isHolding {
            // Letting go of the shortcut's modifiers lets go of it.
            if !modifiers.isSuperset(of: shortcut.flags) { release() }
            return
        }
        guard let (code, flag) = Self.modifierKey(key()) else {
            interrupt()
            return
        }
        guard event.keyCode == code else {
            interrupt()  // another modifier: a shortcut
            return
        }
        if modifiers.contains(flag) {
            guard modifiers == flag else { return interrupt() }
            let keysAtPress = Self.keyDownCount()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pending = nil
                // A key pressed with it, even one the app kept to itself.
                guard Self.keyDownCount() == keysAtPress else { return }
                self.isHolding = true
                self.keysAtStart = keysAtPress
                self.onStart()
            }
            pending?.cancel()
            pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: item)
        } else {
            interrupt()
            release()
        }
    }

    /// The held shortcut was pressed (seen through IMK): recording starts
    /// now and stops when its key comes up.
    func shortcutPressed(_ event: NSEvent) {
        guard !isHolding else { return }
        isHolding = true
        keysAtStart = nil
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        shortcut = (event.keyCode, flags)
        onStart()
        // Watch the key itself; if its state can't be read (it reads up
        // while plainly down), letting go of the modifiers ends it instead.
        let code = CGKeyCode(event.keyCode)
        guard CGEventSource.keyState(.combinedSessionState, key: code) else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            if !CGEventSource.keyState(.combinedSessionState, key: code) { self?.release() }
        }
    }

    /// Whether `event` is the held shortcut repeating.
    func isHeldShortcut(_ event: NSEvent) -> Bool {
        isHolding && shortcut?.keyCode == event.keyCode
    }

    /// A key went to the app while the hold key was down: not talking.
    func interrupt() {
        pending?.cancel()
        pending = nil
    }

    /// The recording this key started was cancelled: let go of it quietly.
    func abandon() {
        interrupt()
        reset()
    }

    private func release() {
        guard isHolding else { return }
        let keysAtStart = self.keysAtStart
        reset()
        if let keysAtStart, Self.keyDownCount() != keysAtStart {
            onCancel()  // a shortcut went to the app meanwhile
        } else {
            onStop()
        }
    }

    private func reset() {
        isHolding = false
        keysAtStart = nil
        shortcut = nil
        poll?.invalidate()
        poll = nil
    }

    /// The key code and flag of a hold key that is a modifier alone.
    static func modifierKey(_ key: VoiceSettings.HoldKey) -> (UInt16, NSEvent.ModifierFlags)? {
        switch key {
        case .fn: (63, .function)
        case .modifier(let modifier):
            switch modifier {
            case .leftControl: (59, .control)
            case .rightControl: (62, .control)
            case .leftOption: (58, .option)
            case .rightOption: (61, .option)
            case .leftCommand: (55, .command)
            case .rightCommand: (54, .command)
            case .leftShift: (56, .shift)
            case .rightShift: (60, .shift)
            }
        case .off, .shortcut: nil
        }
    }

    /// Key presses so far in this login session, the app's own included.
    static func keyDownCount() -> UInt32 {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
    }
}
