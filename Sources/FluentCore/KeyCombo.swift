import Foundation

/// A shortcut as the config writes it: modifiers in a fixed order, then the
/// key, joined by "-" (`ctrl-x`, `ctrl-shift-b`, `cmd-k`, `opt-f1`). Both
/// the input method (from a key event) and the Settings app (from a recorded
/// key press) build these names, so they compare as strings.
public enum KeyCombo {
    /// The modifier names, in the order a name lists them.
    public static let modifierOrder = ["ctrl", "opt", "shift", "cmd"]

    private static let aliases = [
        "control": "ctrl", "ctl": "ctrl", "^": "ctrl",
        "option": "opt", "alt": "opt", "⌥": "opt",
        "command": "cmd", "⌘": "cmd", "⇧": "shift",
    ]

    /// The name for a key pressed with these modifiers; nil without Control,
    /// Option or Command, since Shift alone is typing.
    public static func name(ctrl: Bool, opt: Bool, shift: Bool, cmd: Bool, key: String) -> String? {
        let key = key.lowercased()
        guard ctrl || opt || cmd, !key.isEmpty, !key.contains("-") || key == "-" else { return nil }
        let mods = zip(modifierOrder, [ctrl, opt, shift, cmd]).filter(\.1).map(\.0)
        return (mods + [key]).joined(separator: "-")
    }

    /// A name from the config in its canonical form: aliases resolved,
    /// modifiers reordered, lowercase. Nil when it isn't a shortcut.
    public static func normalized(_ text: String) -> String? {
        var parts = text.lowercased().split(separator: "-", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        // `ctrl--` is Control and the minus key.
        if parts.count >= 2, parts[parts.count - 1].isEmpty, parts[parts.count - 2].isEmpty {
            parts.removeLast(2)
            parts.append("-")
        }
        guard let key = parts.popLast(), !key.isEmpty else { return nil }
        var mods = Set<String>()
        for part in parts {
            let mod = aliases[part] ?? part
            guard modifierOrder.contains(mod) else { return nil }
            mods.insert(mod)
        }
        // A modifier on its own is no key.
        let isModifier = aliases[key] != nil || modifierOrder.contains(key)
        return name(ctrl: mods.contains("ctrl"), opt: mods.contains("opt"), shift: mods.contains("shift"),
                    cmd: mods.contains("cmd"), key: isModifier ? "" : key)
    }
}
