import Foundation

/// Full-width punctuation for typing right after Chinese text, following
/// rime-prelude's defaults. Quotes alternate between opening and closing.
/// `-` and `=` are missing on purpose: they turn candidate pages.
public struct ChinesePunctuation {
    private static let table: [Character: String] = [
        ",": "，", ".": "。", "?": "？", "!": "！", ";": "；", ":": "：",
        "\\": "、", "^": "……", "_": "——", "(": "（", ")": "）", "[": "【", "]": "】",
        "<": "《", ">": "》", "$": "￥", "~": "～",
    ]

    private var doubleQuoteOpen = false
    private var singleQuoteOpen = false

    public init() {}

    /// Punctuation or a symbol (`.`, `(`, `-`, `@`, `$`): typed with nothing
    /// composed, it goes straight in, since there is nothing to improve yet.
    public static func isPunctuation(_ character: Character) -> Bool {
        character.isPunctuation || character.isSymbol
    }

    /// The Chinese form of `character`, or nil if it has none.
    public mutating func convert(_ character: Character) -> String? {
        switch character {
        case "\"":
            doubleQuoteOpen.toggle()
            return doubleQuoteOpen ? "“" : "”"
        case "'":
            singleQuoteOpen.toggle()
            return singleQuoteOpen ? "‘" : "’"
        default:
            return Self.table[character]
        }
    }
}
