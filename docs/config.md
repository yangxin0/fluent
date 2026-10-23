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
| `prefixKeys` | array of strings | `[]` | Shortcuts after which the next key goes straight to the app, such as `"ctrl-x"` (below) |
| `toggleNotice` | string | `"badge"` | What ⇧⇧ shows: `"badge"`, `"pill"`, `"bubble"` or `"keys"` |
| `offBadge` | boolean | `true` | While ⇧⇧ has Fluent off, the grey FL badge stays by the caret |
| `voice` | object | `{}` | Voice input: speech engines and shortcuts (below) |
| `badgeSize` | number | `18` | The FL badge's height in points, for the `"badge"` notice and the badge kept while off, clamped to 16–32 |
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

**Prefix keys.** Each entry of `prefixKeys` names a shortcut: modifiers in
the order `ctrl`, `opt`, `shift`, `cmd`, then the key, joined by `-`
(`ctrl-x`, `ctrl-shift-b`, `cmd-k`, `opt-f1`, `ctrl--` for Control and the
minus key). The key is a letter, digit or symbol as typed without
modifiers, or `space`, `tab`, `return`, `escape`, `delete`, `left`, `right`,
`up`, `down` or `f1`–`f12`. Either case and the aliases `control`,
`option`, `alt` and `command` are read, and an entry without Control,
Option or Command is dropped. The shortcut itself goes to the app as any
shortcut does, inserting what was composed first; the key after it, if it
comes within 2 seconds, goes straight to the app too instead of starting a
composition. Some apps never hand an input method a Ctrl key (WezTerm
passes only plain and Shift keys), so while `prefixKeys` isn't empty the
input method asks for Input Monitoring and, with it, watches key presses
during its sessions (below).

**Voice.** `voice` is an object; a missing or mistyped key in it reads as
its default, and a `voice` that isn't an object as `{}`:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `engines` | array of objects | `[]` | Saved speech engines (below) |
| `engine` | string | the first | The `name` of the engine in use |
| `holdKey` | string | `"fn"` | Held to talk: `"off"`, `"fn"`, one side's modifier alone (`"left-command"`, `"right-option"`, `"left-control"`, `"right-shift"`, …), or a shortcut named as in `prefixKeys` (`"ctrl-space"`) |
| `toggleKey` | string | none | A shortcut, named as in `prefixKeys`, pressed to start and again to stop |
| `afterSpeaking` | string | `"insert"` | `"insert"` the text as recognized, or `"improve"` it: it becomes the composition, as if typed |
| `hotwords` | boolean | `true` | Send your English words (below) to the engine as hotwords, at most 60 |

Each object in `engines` is one service and its credentials; an element
that isn't an object doesn't count:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | `""` | What the Voice page calls it, and what `engine` names |
| `type` | string | `"volcengine"` | `"volcengine"`: 豆包流式语音识别; more types are to come, and one this version doesn't know isn't set up |
| `apiKey` | string | `""` | The new Volcengine console's API key, sent as `X-Api-Key` |
| `appId`, `accessToken` | string | `""` | The old console's App ID and Access Token (`X-Api-App-Key`, `X-Api-Access-Key`), used while `apiKey` is empty |
| `resourceId` | string | `"volc.seedasr.sauc.duration"` | `X-Api-Resource-Id`: model 2.0 (`volc.seedasr.…`) or 1.0 (`volc.bigasr.…`), by the hour (`….duration`) or concurrent (`….concurrent`) |

Values are trimmed. An engine is set up once its type is known and it has
an `apiKey`, or an `appId` and `accessToken`; until the engine in use is,
neither shortcut does anything, and both act only while Fluent is on and
selected. A modifier held alone for 0.3 s starts a recording and letting go
stops it; a held shortcut starts one at once and stops when its key (or its
modifiers) is let go. A key pressed with the hold key before the recording
starts makes it a shortcut instead; one pressed during a recording cancels
it and goes to the app; and letting go after any key went to the app,
even one the app kept to itself, discards the recording. The input method streams
the microphone (it asks for the permission on first use) to
`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async` in 200 ms
packets of 16 kHz, 16-bit mono PCM, uncompressed, with the two-pass mode,
punctuation and digits on; what it hears shows as the composition. Letting
go, or the toggle key again, sends the last packet and takes the final
text; Esc cancels, and a recording stops by itself after 60 s. Settings'
*Test* sends one second of silence with an engine's credentials.

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
object, `name`, `api`, `baseURL`, `apiKey` and `model` first; inside an
object written a line per key, a nested list of objects (`voice.engines`)
gets a line per object too, `name`, `type`, `apiKey`, `appId`,
`accessToken` and `resourceId` first. A
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

## Input Monitoring

`~/Library/Application Support/Fluent/status.json`, written by the input
method: `{"inputMonitoring": true}` or `false`, whether macOS lets it watch
key presses, as it found the last time a session started with prefix keys
set. It writes the file when that changes; until then there is no file.
Settings shows it under Advanced ▸ Prefix keys, and nothing while the list
is empty.

With the permission the input method notes, for the last few key presses
while one of its sessions is active, only when each came and whether it was
a prefix key, so the key after a prefix key the app kept to itself still
goes straight to the app.

## Settings' own preferences

`~/Library/Application Support/Fluent/Settings.json` keeps the Settings
pages' language and the window's size. The input method doesn't read it.
