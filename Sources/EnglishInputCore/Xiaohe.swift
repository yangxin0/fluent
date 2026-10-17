import Foundation

/// Index into `Pinyin.syllables`. The compiled lexicon stores codes as
/// sequences of these, so the table below must not be reordered without
/// rebuilding the dictionary (`Pinyin.tableHash` guards against that).
public typealias SyllableID = UInt16

/// Toneless pinyin syllables as spelled by rime-ice's dictionaries (`v` for
/// ü: `lv`, `nve`), sorted.
public enum Pinyin {
    public static let syllables: [String] = """
        a ai an ang ao ba bai ban bang bao bei ben beng bi bian biang biao bie bin bing bo bu \
        ca cai can cang cao ce cei cen ceng cha chai chan chang chao che chen cheng chi chong \
        chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo da dai \
        dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo \
        e ei en eng er fa fan fang fei fen feng fiao fo fou fu ga gai gan gang gao ge gei gen \
        geng gong gou gu gua guai guan guang gui gun guo ha hai han hang hao he hei hen heng \
        hong hou hu hua huai huan huang hui hun huo ji jia jian jiang jiao jie jin jing jiong \
        jiu ju juan jue jun ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang \
        kui kun kuo la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo \
        long lou lu luan lun luo lv lve ma mai man mang mao me mei men meng mi mian miao mie \
        min ming miu mo mou mu na nai nan nang nao ne nei nen neng ni nian niang niao nie nin \
        ning niu nong nou nu nuan nuo nv nve o ou pa pai pan pang pao pei pen peng pi pian \
        piao pie pin ping po pou pu qi qia qian qiang qiao qie qin qing qiong qiu qu quan que \
        qun ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo sa sai san sang sao \
        se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan \
        shuang shui shun shuo si song sou su suan sui sun suo ta tai tan tang tao te tei teng \
        ti tian tiao tie ting tong tou tu tuan tui tun tuo wa wai wan wang wei wen weng wo wu \
        xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun ya yan yang yao ye yi yin \
        ying yo yong you yu yuan yue yun za zai zan zang zao ze zei zen zeng zha zhai zhan \
        zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun \
        zhuo zi zong zou zu zuan zui zun zuo
        """.split(separator: " ").map(String.init)

    private static let ids: [String: SyllableID] = Dictionary(
        uniqueKeysWithValues: syllables.enumerated().map { ($1, SyllableID($0)) })

    public static func id(of syllable: String) -> SyllableID? { ids[syllable] }

    /// Stamped into the compiled lexicon so a stale dictionary built against a
    /// different syllable table is rejected instead of decoding garbage.
    public static let tableHash: UInt32 = {
        var hash: UInt32 = 2_166_136_261  // FNV-1a
        for byte in syllables.joined(separator: " ").utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return hash
    }()
}

/// The 小鹤双拼 (Xiaohe shuangpin) layout: every syllable is exactly two keys,
/// an initial key (`v`=zh, `i`=ch, `u`=sh) and a final key. Zero-initial
/// syllables double a single vowel (`aa`, `oo`, `ee`), type two-letter ones
/// as is (`ai`, `an`, `er`…), and spell `ang`/`eng` as `ah`/`eg`.
public enum Xiaohe {
    private static let finalKeys: [String: Character] = [
        "iu": "q", "ei": "w", "e": "e", "uan": "r", "ue": "t", "ve": "t", "un": "y",
        "u": "u", "i": "i", "o": "o", "uo": "o", "ie": "p", "a": "a", "ong": "s",
        "iong": "s", "ai": "d", "en": "f", "eng": "g", "ang": "h", "an": "j",
        "ing": "k", "uai": "k", "iang": "l", "uang": "l", "ou": "z", "ia": "x",
        "ua": "x", "ao": "c", "ui": "v", "v": "v", "in": "b", "iao": "n", "ian": "m",
    ]

    private static let zeroInitialCodes: [String: [String]] = [
        "a": ["aa"], "o": ["oo"], "e": ["ee"], "ang": ["ah"], "eng": ["eg"], "er": ["er"],
        "ai": ["ai", "ad"], "an": ["an", "aj"], "ao": ["ao", "ac"],
        "ei": ["ei", "ew"], "en": ["en", "ef"], "ou": ["ou", "oz"],
    ]

    /// Every key pair that types `syllable`; empty for spellings outside the
    /// layout. `ju qu xu yu` also accept `v` as the final key.
    public static func codes(for syllable: String) -> [String] {
        if let codes = zeroInitialCodes[syllable] { return codes }
        let initial: Character
        let rest: Substring
        if syllable.hasPrefix("zh") {
            (initial, rest) = ("v", syllable.dropFirst(2))
        } else if syllable.hasPrefix("ch") {
            (initial, rest) = ("i", syllable.dropFirst(2))
        } else if syllable.hasPrefix("sh") {
            (initial, rest) = ("u", syllable.dropFirst(2))
        } else if let first = syllable.first, !"aoe".contains(first) {
            (initial, rest) = (first, syllable.dropFirst())
        } else {
            return []
        }
        guard let finalKey = finalKeys[String(rest)] else { return [] }
        var codes = [String([initial, finalKey])]
        if rest == "u", "jqxy".contains(initial) {
            codes.append(String([initial, "v"]))
        }
        return codes
    }

    /// Syllables for each key pair, indexed by `pairIndex`. Only `lo` is
    /// ambiguous (lo / luo).
    private static let pairTable: [[SyllableID]] = {
        var table = [[SyllableID]](repeating: [], count: 26 * 26)
        for (id, syllable) in Pinyin.syllables.enumerated() {
            for code in codes(for: syllable) {
                let keys = Array(code.utf8)
                table[pairIndex(keys[0], keys[1])].append(SyllableID(id))
            }
        }
        return table
    }()

    /// Syllables whose code starts with a given key, for a dangling last key.
    private static let firstKeyTable: [[SyllableID]] = {
        var table = [[SyllableID]](repeating: [], count: 26)
        for (id, syllable) in Pinyin.syllables.enumerated() {
            for first in Set(codes(for: syllable).map { $0.utf8.first! }) {
                table[Int(first - asciiA)].append(SyllableID(id))
            }
        }
        return table
    }()

    private static let asciiA = UInt8(ascii: "a")

    private static func pairIndex(_ a: UInt8, _ b: UInt8) -> Int {
        Int(a - asciiA) * 26 + Int(b - asciiA)
    }

    private static func isLowercaseLetter(_ byte: UInt8) -> Bool {
        byte >= asciiA && byte <= UInt8(ascii: "z")
    }

    /// Syllables typed by one key pair, or nil if the pair is not a syllable.
    public static func syllables(forPair pair: String) -> [SyllableID]? {
        let keys = Array(pair.utf8)
        guard keys.count == 2, keys.allSatisfy(isLowercaseLetter) else { return nil }
        let ids = pairTable[pairIndex(keys[0], keys[1])]
        return ids.isEmpty ? nil : ids
    }

    /// Splits keys into syllable slots, two keys each. A dangling last key
    /// becomes a slot of every syllable it can start (`isPartial`). Decoding
    /// stops at the first pair that is not a syllable, so `slots` may cover
    /// only a prefix of the keys; `isComplete` says whether it covers all.
    public struct Decoding: Equatable {
        /// Candidate syllables per slot; usually one, more for `lo` and for a
        /// partial last slot.
        public var slots: [[SyllableID]]
        /// The last slot is a single dangling key, not a full pair.
        public var lastSlotIsPartial: Bool
        /// Keys covered by `slots`.
        public var keyCount: Int
        public var isComplete: Bool

        /// Keys covered by the first `slotCount` slots.
        public func keyCount(ofSlots slotCount: Int) -> Int {
            if lastSlotIsPartial && slotCount == slots.count {
                return 2 * slotCount - 1
            }
            return 2 * slotCount
        }
    }

    public static func decode<S: StringProtocol>(_ keys: S) -> Decoding {
        let bytes = Array(keys.utf8)
        var slots: [[SyllableID]] = []
        var index = 0
        var partial = false
        while index < bytes.count {
            let first = bytes[index]
            guard isLowercaseLetter(first) else { break }
            if index + 1 == bytes.count {
                slots.append(firstKeyTable[Int(first - asciiA)])
                partial = true
                index += 1
                break
            }
            let second = bytes[index + 1]
            guard isLowercaseLetter(second) else { break }
            let ids = pairTable[pairIndex(first, second)]
            guard !ids.isEmpty else { break }
            slots.append(ids)
            index += 2
        }
        return Decoding(slots: slots, lastSlotIsPartial: partial, keyCount: index,
                        isComplete: index == bytes.count)
    }

    /// Whether every key pair is a syllable (a dangling last key is fine).
    public static func isValid<S: StringProtocol>(_ keys: S) -> Bool {
        !keys.isEmpty && decode(keys).isComplete
    }

    /// Raw keys grouped per syllable for the inline preedit, like the system
    /// shuangpin input method: `veui` → `ve ui`, `veu` → `ve u`.
    public static func grouped<S: StringProtocol>(_ keys: S) -> String {
        var result = ""
        for (offset, key) in keys.enumerated() {
            if offset > 0 && offset % 2 == 0 { result.append(" ") }
            result.append(key)
        }
        return result
    }
}
