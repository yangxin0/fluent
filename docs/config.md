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
| `providers` | array of objects | `[]` | Saved LLM endpoints (below) |
| `provider` | string | the first | The `name` of the provider in use |
| `baseURL` | string, **required** without `providers` | | The Responses API root, e.g. `https://api.openai.com/v1` |
| `apiKey` | string, **required** without `providers` | | Sent as `Authorization: Bearer …`; `sk-REPLACE_ME` means not set |
| `model` | string, **required** without `providers` | | |
| `reasoningEffort` | string | not sent | Sent as `reasoning.effort` |
| `prompts` | object of strings | `{}` | Your own prompt per mode (below) |
| `debounceMs` | number | `350` | Wait after typing, clamped to 0–10000 |
| `timeoutSeconds` | number | `10` | How long a reply may stay silent, clamped to 1–300 |
| `appearance` | string | `"auto"` | Candidate bar: `"auto"`, `"light"` or `"dark"` |
| `candidateBarSize` | string | `"medium"` | The bar's padding, number labels and badge: `"small"`, `"medium"` or `"large"` |
| `candidateTextSize` | number | `18` | The candidates' text size in points, clamped to 14–28; the bar grows to fit it |
| `candidatePageSize` | number | `6` | Chinese candidates in one row of the bar, rounded and clamped to 5–9 |
| `toggleNotice` | string | `"badge"` | What ⇧⇧ shows: `"badge"`, `"pill"`, `"bubble"` or `"keys"` |
| `terminalMode` | string | `"auto"` | `"auto"`, `"always"` or `"never"` |
| `terminalApps` | array of strings | `[]` | More terminals, as bundle identifiers |
| `terminalCellWidth` | number | measured | A terminal cell's width in points |
| `chinese` | string | `"pinyin"` | `"pinyin"` (全拼), `"xiaohe"` (小鹤双拼) or `"off"` |
| `pinyinAbbreviations` | boolean | `true` | Full pinyin: an initial alone spells a syllable |
| `fuzzyPinyin` | array of strings | `[]` | Full pinyin: pairs read alike, e.g. `"zh=z"` |

Required strings are trimmed of surrounding whitespace. An optional key
with the wrong type is ignored, as if it were missing; an unknown key is
ignored.

**Providers.** Each object in `providers` is one endpoint:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | `""` | What the pages and the IME menu call it, and what `provider` names |
| `api` | string | `"responses"` | `"responses"` (`POST <baseURL>/responses`) or `"chat"` (`POST <baseURL>/chat/completions`), either case |
| `baseURL` | string | `""` | The API root, e.g. `https://api.deepseek.com` |
| `apiKey` | string | `""` | As above |
| `model` | string | `""` | |
| `reasoningEffort` | string | not sent | `reasoning.effort` for Responses, `reasoning_effort` for Chat Completions |

Every value but `reasoningEffort` is trimmed; a missing value, or one of the
wrong type, reads as empty, so a provider is never a problem, only not set
up. An element that isn't an object doesn't count. The provider in use is
the first one whose `name` equals `provider` (trimmed), else the first one;
when `provider` isn't a string, the first one. While `providers` holds no
object (missing, empty, or of the wrong type), the top-level `baseURL`,
`apiKey`, `model` and `reasoningEffort` are the one provider (no name,
Responses API), as before there were providers; once it holds one, those
keys are ignored and not required. Settings moves them into the list (named
after the URL's host) the first time you save a provider, and removes them.

The input method can rewrite once the provider in use has a non-empty
`baseURL`, `apiKey` and `model` and its `apiKey` isn't `sk-REPLACE_ME`.

**Requests.** Both apps stream (`"stream": true`) one message, as
nextai-translator does: the mode's prompt, a blank line (`\n\n`), the
output rule, a blank line, then the text. There is no system prompt, so
text that reads like a request (帮我写一封邮件) is translated or rewritten,
not answered. For the Responses API the message is the `input` (no
`instructions`); a model whose name starts with `gpt` or contains `codex`
is sent as the Codex CLI (`originator: codex_cli_rs`). For Chat Completions
it is the one `user` message, and the reply is the
`choices[0].delta.content` chunks until a chunk with a `finish_reason`
(`length` or `content_filter` mean it was cut short) or `data: [DONE]`.

**Prompts.** `prompts` maps `fix`, `polish` and `translate` to your own
prompt for that mode; a mode that is missing, blank or not a string uses
the built-in prompt (Polish and Translate are nextai-translator's, Fix one
in their style). The output rule, `Only reply the result and nothing
else.`, follows every prompt and no prompt replaces it: the reply is
inserted as it comes. [`default-prompts.json`](default-prompts.json) holds
the built-in prompts and the rule; both apps' tests check theirs against
it.

When the file can't be used at all, both apps say why in the same words:

| The file | Problem |
|---|---|
| isn't JSON | `not valid JSON` |
| is JSON but not an object | `not a JSON object` |
| has no providers, and no `baseURL`, `apiKey` or `model` (checked in that order) | `"apiKey" is missing` |
| has no providers, and one of those as anything but a string, `null` included | `"apiKey" has the wrong type` |

`docs/config-examples/` holds sample files and, in `expected.json`, what
each one makes: both apps' tests read them (`ConfigExamplesTests` in Swift,
`TestConfigExamples` in Go).

**Writing.** Both apps change one key at a time, editing only that key's
text, so the other keys keep their order, spacing and number formatting.
Where the file puts its keys on lines of their own, Settings writes an
object a line per key and a list of objects (`providers`) a line per
object, `name`, `api`, `baseURL`, `apiKey` and `model` first. A
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

## Your English words

`~/Library/Application Support/Fluent/english-words.txt`: words the input
method keeps in English instead of reading them as pinyin, such as product
names the dictionary lacks, one per line. Both apps keep only lowercased
words of two or more letters a–z, each once; other lines are dropped.

The input method adds a word when you press Enter in the Chinese bar to
insert the keys as typed, unless you picked a candidate first. Settings ▸
English shows and edits the list. Each app writes the whole file at once,
and the input method rereads it when its modification time changes.

## Settings' own preferences

`~/Library/Application Support/Fluent/Settings.json` keeps the Settings
pages' language and the window's size. The input method doesn't read it.
