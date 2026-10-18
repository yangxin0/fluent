# The config file

`Fluent-Input.app` (the input method, Swift, `Sources/`) and `Fluent.app`
(Settings, Go, `Settings/`) share no code. They meet only in the files and
the one notification below, so this page is the contract between them: a
change to either side that touches these files changes this page too.

## `~/.config/fluent/config.json`

A JSON object, readable by the user only (`0600`, in a `0700` folder): it
holds an API key. The input method takes group and other access away when
it finds them. The file may be a symlink, for example into a dotfiles
repository; a writer writes the file the link points at and keeps the link.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `baseURL` | string, **required** | | The Responses API root, e.g. `https://api.openai.com/v1` |
| `apiKey` | string, **required** | | Sent as `Authorization: Bearer …`; `sk-REPLACE_ME` means not set |
| `model` | string, **required** | | |
| `reasoningEffort` | string | not sent | Sent as `reasoning.effort` |
| `debounceMs` | number | `350` | Wait after typing, clamped to 0–10000 |
| `timeoutSeconds` | number | `10` | How long a reply may stay silent, clamped to 1–300 |
| `appearance` | string | `"auto"` | Candidate bar: `"auto"`, `"light"` or `"dark"` |
| `terminalMode` | string | `"auto"` | `"auto"`, `"always"` or `"never"` |
| `terminalApps` | array of strings | `[]` | More terminals, as bundle identifiers |
| `terminalCellWidth` | number | measured | A terminal cell's width in points |
| `chinese` | string | `"xiaohe"` | `"xiaohe"` (小鹤双拼), `"pinyin"` (全拼) or `"off"` |
| `pinyinAbbreviations` | boolean | `true` | Full pinyin: an initial alone spells a syllable |
| `fuzzyPinyin` | array of strings | `[]` | Full pinyin: pairs read alike, e.g. `"zh=z"` |

Required strings are trimmed of surrounding whitespace. An optional key
with the wrong type is ignored, as if it were missing; an unknown key is
ignored. The input method can rewrite once `baseURL`, `apiKey` and `model`
are non-empty and `apiKey` isn't `sk-REPLACE_ME`.

When the file can't be used at all, both apps say why in the same words:

| The file | Problem |
|---|---|
| isn't JSON | `not valid JSON` |
| is JSON but not an object | `not a JSON object` |
| has no `baseURL`, `apiKey` or `model` (checked in that order) | `"apiKey" is missing` |
| has one of them as anything but a string, `null` included | `"apiKey" has the wrong type` |

`docs/config-examples/` holds sample files and, in `expected.json`, what
each one makes: both apps' tests read them (`ConfigExamplesTests` in Swift,
`TestConfigExamples` in Go).

**Writing.** Both apps change one key at a time, editing only that key's
text, so the other keys keep their order, spacing and number formatting. A
missing file is created from the starter template; when it is missing but
`~/.config/english-input/config.json` (Fluent's name before) exists, that
one is copied instead.

**Taking effect.** Nothing has to be told. Each time the input method needs
a setting it compares the file's modification time with the one it last
read and re-reads the file if it changed, so a saved change applies from
the next keystroke. Writing the file (in place, or a new file renamed over
it) is all a writer does.

## Learned words

`~/Library/Application Support/Fluent/xiaohe-user.tsv`, written by the
input method: a `#tick<TAB>n` line, then one word per line as
`text<TAB>syllables<TAB>commits<TAB>dee<TAB>tick` (syllables in pinyin,
space-separated). Settings counts the words.

To forget them, Settings deletes the file and then posts the distributed
notification `com.yangxin.inputmethod.Fluent.forgetLearnedWords`. A running
input method drops the words it holds in memory, which it would otherwise
save back.

## Settings' own preferences

`~/Library/Application Support/Fluent/Settings.json` keeps the Settings
pages' language and the window's size. The input method doesn't read it.
