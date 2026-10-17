# Fluent

A macOS input method (IME) that improves your English as you type. Your raw
text appears inline as underlined composition text in any app; an LLM
rewrites it, and a candidate bar next to the caret shows what Enter will
insert (`P  We should figure out a way.  ↵`): **Enter inserts the improved
text**, Shift+Enter inserts exactly what you typed, Esc cancels. The same bar
is used for Chinese, 小鹤双拼 or 全拼 (see below).

Powered by any **OpenAI Responses-API-compatible endpoint** (OpenAI, or any
provider exposing `/v1/responses` with SSE streaming).

## Modes

| Badge | Mode | What it does |
|---|---|---|
| **F** | **Fix** | Grammar, spelling, punctuation only — keeps your wording |
| **P** | **Polish** | Rewrites into natural, native-speaker English |
| **T** | **Translate** | Turns rough / fragmentary / Chinese-mixed input into the intended English (`"interpret"` in the CLI) |

The bar starts with the mode's badge (`双` while typing 小鹤双拼, `拼` for
全拼). Switch modes
from the input-method menu in the menu bar, or **Ctrl+Tab** while composing
English.
The last mode is remembered.

## Install

```sh
make install    # build, assemble Fluent.app, install to ~/Library/Input Methods, ad-hoc sign, register
```

Then (one-time, macOS requires manual consent for third-party input sources):

1. **System Settings ▸ Keyboard ▸ Text Input ▸ Input Sources ▸ Edit… ▸ +**
2. Under **English**, add **Fluent**.
3. Pick **Fluent** from the input menu in the menu bar (or Ctrl+Space).

## Configure

Edit `~/.config/fluent/config.json` (a template is created on first run, or
your config from before the rename to Fluent is copied over;
also reachable via IME menu ▸ *Open Config File*):

```json
{
  "baseURL": "https://api.openai.com/v1",
  "apiKey": "sk-...",
  "model": "gpt-4o-mini",
  "appearance": "auto",
  "terminalMode": "auto",
  "chinese": "xiaohe",
  "debounceMs": 350,
  "timeoutSeconds": 10
}
```

Any Responses-compatible provider works — point `baseURL` at its `/v1` root.
`reasoningEffort` (optional, e.g. `"low"` or `"none"`) is sent as
`reasoning.effort`. For models whose name starts with `gpt` or contains
`codex`, requests identify as the Codex CLI (`originator: codex_cli_rs`),
which some gateways require for the Responses API. `timeoutSeconds` is how
long the stream may stay silent before the rewrite fails, not a cap on the
whole reply.
`appearance` controls the candidate bar's color scheme: `"auto"` follows the
system light/dark setting (and updates live when it changes), or force it with
`"light"` / `"dark"`.
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
`chinese` picks the one Chinese input method (see below): `"xiaohe"`
(小鹤双拼, the default), `"pinyin"` (full pinyin) or `"off"`; the IME menu
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
| Space / punctuation | Just text — composition continues until Enter |
| Cmd-shortcuts, Tab, ↑ ↓ | Commit raw text, then act normally |
| Shift, Shift (double tap) | Toggle the IME **on/off** |

Switching apps or clicking elsewhere commits the raw text — nothing you type
is ever silently lost. If the API is unreachable, Enter simply inserts what
you typed.

**Double-tap Shift** turns the IME off: every key then passes straight
through to the app — handy for terminal commands, code, or anything you
don't want rewritten. A small notice flashes near the caret; double-tap
Shift again (or use the IME menu ▸ *Enabled*) to turn it back on. The
toggle resets to *on* at relaunch.

## Chinese (小鹤双拼 or 全拼)

You can also type Chinese without switching input sources, with one Chinese
input method at a time: the 小鹤双拼 (Xiaohe shuangpin) layout by default, or
full pinyin (全拼) with `"chinese": "pinyin"` or IME menu ▸ *Chinese: 全拼*.
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
| Backspace | Take back the last pick, else delete a key |
| Esc | Cancel (collapse the grid first) |
| Punctuation | Insert the highlighted candidate and Chinese punctuation (`，。？`); in full pinyin `'` splits syllables instead |
| A capital letter | Keep the picked words and continue in English |

Picking a candidate that covers only part of the keys keeps converting the
rest. Punctuation typed right after Chinese text is Chinese too. Turn the
whole feature off with IME menu ▸ *Chinese: Off* (or `"chinese": "off"`).

Words you pick are learned the way Rime does it: they move ahead of other
words of the same length, words picked one after another become a new
phrase, and words you stop using fade over a few hundred picks. They are
saved in `~/Library/Application Support/Fluent/xiaohe-user.tsv`;
delete the file to forget them.

The dictionaries come from [rime-ice](https://github.com/iDvel/rime-ice):
`make install` downloads and compiles them (see `make dict` below).

## Development

```sh
make dev        # rebuild + reinstall + restart the IME and re-select it (macOS relaunches it on next keystroke)
make test       # unit tests (SSE parser, config, prompts, Chinese engine)
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
