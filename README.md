# Fluent

A macOS input method (IME) that improves your English as you type. Your raw
text appears inline as underlined composition text in any app; an LLM
rewrites it, and a candidate bar next to the caret shows what Enter will
insert (`P  We should figure out a way.  ↵`): **Enter inserts the improved
text**, Shift+Enter inserts exactly what you typed, Esc cancels. The same bar
is used for Chinese, 全拼 or 小鹤双拼 (see below).

Powered by any **OpenAI-compatible endpoint** that streams: the Responses
API (OpenAI, or any provider exposing `/v1/responses`) or Chat Completions
(DeepSeek, Ollama, LM Studio, OpenRouter…). Save several providers and
switch between them.

## Modes

| Badge | Mode | What it does |
|---|---|---|
| **F** | **Fix** | Grammar, spelling, punctuation only — keeps your wording |
| **P** | **Polish** | Rewrites into natural, native-speaker English |
| **T** | **Translate** | Turns rough / fragmentary / Chinese-mixed input into the intended English (`"interpret"` in the CLI) |

The bar starts with the mode's badge (`拼` while typing 全拼, `双` for
小鹤双拼). Switch modes
from the input-method menu in the menu bar, or **Ctrl+Tab** while composing
English.
The last mode is remembered. Each mode's prompt can be replaced with your
own in Settings ▸ English, where *Try* runs a sample through it.

## Install

```sh
make install    # build both apps, ad-hoc sign, register the input method
```

Building needs Xcode (or its command-line tools) for the Swift input method
and Go for the Settings app; any recent Go will do, as `make` fetches the
version `Settings/go.mod` names.

This installs two apps:

- **`~/Library/Input Methods/Fluent-Input.app`**, the input method. It was
  `Fluent.app` before; `make install` moves an old one to the new name in
  place, so the input source stays enabled.
- **`/Applications/Fluent.app`**, the Settings app. Its *Setup* page checks
  each step below, and its other pages edit the config (also IME menu ▸
  *Open Fluent Settings…*). It is optional: the input method runs on its
  own and reads the config file itself.

Then (one-time, macOS requires manual consent for third-party input sources):

1. **System Settings ▸ Keyboard ▸ Text Input ▸ Input Sources ▸ Edit… ▸ +**
2. Under **English**, add **Fluent**.
3. Pick **Fluent** from the input menu in the menu bar (or Ctrl+Space).

## Configure

Use the Settings app (`/Applications/Fluent.app`, or IME menu ▸ *Open
Fluent Settings…*), in English or 简体中文: it edits
`~/.config/fluent/config.json`, one key at a time, leaving the rest of the
file as you wrote it. You can also edit the file by hand (a template is
created on first run, or your config from before the rename to Fluent is
copied over):

```json
{
  "providers": [
    {"name": "OpenAI", "api": "responses", "baseURL": "https://api.openai.com/v1", "apiKey": "sk-...", "model": "gpt-4o-mini"},
    {"name": "DeepSeek", "api": "chat", "baseURL": "https://api.deepseek.com", "apiKey": "sk-...", "model": "deepseek-chat"}
  ],
  "provider": "OpenAI",
  "prompts": {
    "polish": "Rewrite it as a friendly native speaker would, keeping it short."
  },
  "appearance": "auto",
  "terminalMode": "auto",
  "chinese": "pinyin",
  "debounceMs": 350,
  "timeoutSeconds": 10
}
```

Every key, and how the two apps share the file, is in
[docs/config.md](docs/config.md).
Each provider speaks the Responses API (`"api": "responses"`, the default)
or Chat Completions (`"chat"`); point `baseURL` at its `/v1` root.
`provider` is the one in use, also picked from Settings ▸ LLM or the IME
menu. A config from before providers, with `baseURL`, `apiKey` and `model`
at the top level, still works as one provider; Settings moves them into the
list when you first save a provider.
`reasoningEffort` (optional, e.g. `"low"` or `"none"`) is sent as
`reasoning.effort` (`reasoning_effort` for Chat Completions). For models
whose name starts with `gpt` or contains `codex`, Responses requests
identify as the Codex CLI (`originator: codex_cli_rs`), which some gateways
require. `prompts` replaces a mode's built-in prompt (`fix`, `polish`,
`translate`); the rule "Only reply the result and nothing else." always
follows it, so the reply can be inserted as is. Prompt and rule go right
before your text in one message, as nextai-translator sends them, so text
that reads like a request is translated or rewritten rather than answered. `timeoutSeconds` is how
long the stream may stay silent before the rewrite fails, not a cap on the
whole reply.
`appearance` controls the candidate bar's color scheme: `"auto"` follows the
system light/dark setting (and updates live when it changes), or force it with
`"light"` / `"dark"`. `candidateBarSize` (`"small"`, `"medium"`, `"large"`)
sizes the bar's padding, number labels and badge, `candidateTextSize` (14–28,
default 18) the candidates' text, and `candidatePageSize` (5–9, default 6) how
many Chinese candidates a row holds; Settings ▸ Appearance previews them.
`toggleNotice` is what double-tapping Shift shows at the caret: `"badge"`
(the FL badge alone, the default), `"pill"` (the badge and On/Off in a
capsule, with the ⇧⇧ keys when off), `"bubble"` (the badge and On/Off in a
bubble pointing at the caret) or `"keys"` (that bubble with the badge alone,
and the ⇧⇧ keys when off). Settings ▸ Appearance shows each one.
`terminalMode` handles terminal emulators, which draw marked text as a single
row and clip it at the window edge. In terminal mode the composition stays
inline as usual, but once it is about to reach the edge the panel also shows
your typed text with a caret (like Rime's non-inline preedit) until you commit.
`"auto"` detects common terminals (Terminal.app, iTerm2, WezTerm, Ghostty,
Alacritty, kitty, Warp, …); force it on or off with `"always"` / `"never"`.
Add more apps to the whitelist with `"terminalApps": ["com.example.term"]`
(bundle identifiers). Edge detection measures the terminal's cell width from
what the app reports; if it triggers too early or late, set the exact width in
points with `"terminalCellWidth": 9.7`.
`chinese` picks the one Chinese input method (see below): `"pinyin"`
(full pinyin, the default), `"xiaohe"` (小鹤双拼) or `"off"`; the IME menu
offers the same choice and writes it here. For full pinyin,
`"pinyinAbbreviations"` (default `true`) lets an initial alone spell a
syllable (`zg` → 中国), and `"fuzzyPinyin"` lists pairs to treat as the same,
e.g. `["zh=z", "ch=c", "sh=s", "n=l", "an=ang", "en=eng", "in=ing"]`
(default none).
Config changes are picked up automatically (or use IME menu ▸ *Reload Config*).
The file holds your API key, so Fluent keeps it readable only by you. A
wrongly typed optional key is ignored; if the file can't be used at all, the
bar says why (`Config error: "apiKey" is missing`).

## Keys while composing

| Key | Action |
|---|---|
| Enter | Insert the **improved** text (falls back to raw if not ready/offline) |
| Shift+Enter | Insert the text exactly **as typed** |
| Esc | Cancel the composition |
| Backspace, ← → | Edit within the composition |
| Ctrl+Tab | Cycle mode (Fix → Polish → Translate) while composing English |
| Space / punctuation | Just text — composition continues until Enter (punctuation, a space or a digit typed with nothing composed goes straight in) |
| Cmd-shortcuts, Tab, ↑ ↓ | Commit raw text, then act normally |
| Shift, Shift (double tap) | Toggle the IME **on/off** |
| A prefix key you listed (e.g. Ctrl-X) | Goes to the app, and so does the next key, instead of starting a composition: the N in Ctrl-X N, the c in tmux's Ctrl-B c. Set them in Settings ▸ Advanced ▸ *Prefix keys* (none by default) |

Switching apps or clicking elsewhere commits the raw text — nothing you type
is ever silently lost. If the API is unreachable, Enter simply inserts what
you typed.

**Double-tap Shift** turns the IME off: every key then passes straight
through to the app — handy for terminal commands, code, or anything you
don't want rewritten. The FL badge flashes under the caret, indigo for on
and grey for off (Settings ▸ Appearance has other styles); double-tap Shift
again (or use the IME menu ▸ *Enabled*) to turn it back on. The toggle
resets to *on* at relaunch.

## Chinese (全拼 or 小鹤双拼)

You can also type Chinese without switching input sources, with one Chinese
input method at a time: full pinyin (全拼) by default, or the 小鹤双拼
(Xiaohe shuangpin) layout with `"chinese": "xiaohe"` or IME menu ▸
*Chinese: 小鹤双拼*.
English always comes first: Chinese conversion starts only when the letters
you type can't be English. The examples below are 小鹤双拼; full pinyin works
the same way with whole syllables (`nihao`, `zhongguo`).

- At the start of a composition, letters that are valid shuangpin and don't
  begin any English word (`nihc`, `veuiyg`) open a **candidate bar** like the
  system shuangpin input method. The keys show inline grouped per syllable
  (`ve ui`).
- Right after Chinese text, any shuangpin that isn't a whole English word
  converts, so you can keep typing Chinese.
- Letters that are also English (`make`, `like`, `here`) stay English: the
  candidate bar shows the word first, then its Chinese readings
  (`1 make  2 马克  3 马克思`). Press 2–6 to pick one, 1 or Enter to insert
  the word as typed, or just keep typing English.
- A word the dictionary lacks (a product name like `copatent`) reads as
  pinyin at first. Press Enter in the Chinese bar to insert it as typed:
  Fluent remembers it, and from then on it stays English. Settings ▸ English
  ▸ *Your words* lists them, to add names up front or remove one; they are
  kept in `~/Library/Application Support/Fluent/english-words.txt`.
- Inside an English sentence there are no Chinese candidates at all, so a
  typo like `rela` never turns into 热辣. One English word inside Chinese text
  (`这个 bug 修好了`) doesn't count: the Chinese after it still converts. Two
  or more words are an English sentence, even right after Chinese.
- A stray key that can't continue the pinyin (`woxianzaijiu` + `i`) doesn't
  turn the run into English: the keys before it convert and the rest stay as
  typed (`wo xian zai jiu i`). Backspace fixes the typo; picking 我现在就
  leaves `i` in the composition to fix, or to insert as typed.

In full pinyin, keys can split more than one way (`xian` is 先 or 西安):
every reading is offered, best first. Type `'` to split syllables yourself
(`xi'an` → 西安), type only initials (`zg` → 中国, `bj` → 北京, `zhg` with
`zh` as one initial), and an unfinished last syllable is completed
(`zhongg` → 中国); an -ong or -ou syllable reads as itself while you type it
(`zhon`, `zho` → 中, as in librime's luna_pinyin). Fuzzy pairs from the config add the other spelling
(`zh=z`: `zi` also finds 只). The inline keys are split the same way
(`zhong guo`).

| Key (candidate bar) | Action |
|---|---|
| Space, 1–6 | Pick the highlighted / numbered candidate |
| ← → | Move the highlight |
| ↑ ↓, - = | Previous / next page (also scrolling); ↑ ↓ move by row in the grid |
| Tab | Expand the bar into a grid of more candidates (also the chevron), or collapse it |
| Enter | Insert the keys as typed (when they lead, the bar marks them: `1 make ↵`) |
| Backspace | Take back the last pick, else delete a key (after punctuation, a character of the line) |
| Esc | Cancel (collapse the grid first) |
| Punctuation | Keep the highlighted candidate and Chinese punctuation (`，。？`) in the composition and go on typing the line (`我是，` then `nihc` → `我是，你好`); in full pinyin `'` splits syllables instead |
| A capital letter | Keep the picked words and continue in English |

Picking a candidate that covers only part of the keys keeps converting the
rest. Punctuation in the middle of the input doesn't insert anything: the
line stays in the composition until a pick converts its last keys, or until
Space or Enter with no keys left (an English word inside it goes in as typed,
not rewritten). Only punctuation typed with nothing composed goes straight
in, as Chinese right after Chinese text. Turn the whole feature off with IME
menu ▸ *Chinese: Off* (or `"chinese": "off"`).

Words you pick are learned the way Rime does it: they move ahead of other
words of the same length, words picked one after another become a new
phrase, and words you stop using fade over a few hundred picks. They are
saved in `~/Library/Application Support/Fluent/xiaohe-user.tsv`; to forget
them, use Settings ▸ Chinese ▸ *Forget learned words*.

The dictionaries come from [rime-ice](https://github.com/iDvel/rime-ice):
`make install` downloads and compiles them (see `make dict` below).

## Development

```sh
make dev        # rebuild + reinstall + restart the IME and re-select it (macOS relaunches it on next keystroke)
make settings   # build the Settings app (Go + Wails, Settings/) and open it from dist/
make test       # unit tests: the Swift core (SSE parser, config, prompts, Chinese engine), then Settings' Go tests
make logs       # tail the IME's os_log output
swift run fluent-cli --mode polish "helo wrold how r u"   # test the API path without the IME (--help)
make dict       # download the pinned rime-ice dictionaries and compile them (bundle/install run it)
make cli ARGS='--xiaohe veui nihc'   # 小鹤双拼 candidates from the compiled dictionary
make cli ARGS='--pinyin nihao zg'    # full pinyin (--no-abbreviations, --fuzzy zh=z,an=ang)
```

If typing goes dead after a change, check for a crash report:
`ls -lt ~/Library/Logs/DiagnosticReports | head`.

## Known limitations

- **Password fields**: macOS Secure Input bypasses all IMEs there by design.
- **Dead keys** (e.g. Option-e for accents) are not composed; unusual modifier
  combos end the composition and pass through.
- Compositions over 500 characters are no longer improved; keep typing, and
  Enter inserts your raw text.
- Some Electron apps report no caret position; the panel then falls back to a
  fixed position near the bottom of the screen under the pointer.
- Terminals cannot wrap marked text, so a composition longer than the rest of
  the row is clipped in the terminal itself; the panel shows the full typed
  text once that is about to happen (see `terminalMode`).

## License

GPL-3.0 — see [LICENSE](LICENSE). The Chinese and English dictionaries come
from [rime-ice](https://github.com/iDvel/rime-ice) (GPL-3.0) and the Chinese
engine ports algorithms from [librime](https://github.com/rime/librime)
(BSD-3-Clause); see [NOTICE](NOTICE).
