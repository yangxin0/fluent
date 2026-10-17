# Fluent

A macOS input method (IME) that improves your English as you type. Your raw
text appears inline as underlined composition text in any app; an LLM
rewrites it, and a candidate bar next to the caret shows what Enter will
insert (`P  We should figure out a way.  ↵`): **Enter inserts the improved
text**, Shift+Enter inserts exactly what you typed, Esc cancels. The same bar
is used for 小鹤双拼 Chinese (see below).

Powered by any **OpenAI Responses-API-compatible endpoint** (OpenAI, or any
provider exposing `/v1/responses` with SSE streaming).

## Modes

| Badge | Mode | What it does |
|---|---|---|
| **F** | **Fix** | Grammar, spelling, punctuation only — keeps your wording |
| **P** | **Polish** | Rewrites into natural, native-speaker English |
| **T** | **Translate** | Turns rough / fragmentary / Chinese-mixed input into the intended English (`"interpret"` in the CLI) |

The bar starts with the mode's badge (`双` while typing Chinese). Switch modes
from the input-method menu in the menu bar, or **Ctrl+Tab** while composing.
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
  "debounceMs": 350,
  "timeoutSeconds": 10
}
```

Any Responses-compatible provider works — point `baseURL` at its `/v1` root.
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
Config changes are picked up automatically (or use IME menu ▸ *Reload Config*).

## Keys while composing

| Key | Action |
|---|---|
| Enter | Insert the **improved** text (falls back to raw if not ready/offline) |
| Shift+Enter | Insert the text exactly **as typed** |
| Esc | Cancel the composition |
| Backspace, ← → | Edit within the composition |
| Ctrl+Tab | Cycle mode (Fix → Polish → Translate) |
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

## 小鹤双拼 (Chinese)

You can also type Chinese with the 小鹤双拼 (Xiaohe shuangpin) layout without
switching input sources. English always comes first: Chinese conversion
starts only when the letters you type can't be English.

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
  typo like `rela` never turns into 热辣. English words inside Chinese text
  (`这个 bug 修好了`) don't count: the Chinese after them still converts.

| Key (candidate bar) | Action |
|---|---|
| Space, 1–6 | Pick the highlighted / numbered candidate |
| ← → | Move the highlight |
| ↑ ↓, - = | Previous / next page (also scrolling); ↑ ↓ move by row in the grid |
| Tab | Expand the bar into a grid of more candidates (also the chevron), or collapse it |
| Enter | Insert the keys as typed (when they lead, the bar marks them: `1 make ↵`) |
| Backspace | Take back the last pick, else delete a key |
| Esc | Cancel (collapse the grid first) |
| Punctuation | Insert the highlighted candidate and Chinese punctuation (`，。？`) |
| A capital letter | Keep the picked words and continue in English |

Picking a candidate that covers only part of the keys keeps converting the
rest. Punctuation typed right after Chinese text is Chinese too. Turn the
whole feature off with IME menu ▸ *小鹤双拼 Chinese*.

Words you pick are learned the way Rime does it: they move ahead of other
words of the same length, words picked one after another become a new
phrase, and words you stop using fade over a few hundred picks. They are
saved in `~/Library/Application Support/Fluent/xiaohe-user.tsv`;
delete the file to forget them.

The dictionaries come from [rime-ice](https://github.com/iDvel/rime-ice):
`make install` downloads and compiles them (see `make dict` below).

## Development

```sh
make dev        # rebuild + reinstall + kill the running IME (macOS relaunches it on next keystroke)
make test       # unit tests (SSE parser, config, prompts, shuangpin engine)
make logs       # tail the IME's os_log output
swift run fluent-cli --mode polish "helo wrold how r u"   # test the API path without the IME
make dict       # download the pinned rime-ice dictionaries and compile them (bundle/install run it)
make cli ARGS='--xiaohe veui nihc'   # 小鹤双拼 candidates from the compiled dictionary
```

If typing goes dead after a change, check for a crash report:
`ls -lt ~/Library/Logs/DiagnosticReports | head`.

## Known limitations

- **Password fields**: macOS Secure Input bypasses all IMEs there by design.
- **Dead keys** (e.g. Option-e for accents) are not composed; unusual modifier
  combos end the composition and pass through.
- Composition is capped at 500 characters; beyond that the LLM is no longer
  queried (Enter still inserts your raw text).
- Some Electron apps report no caret position; the panel then falls back to a
  fixed position near the bottom of the screen.
- Terminals cannot wrap marked text, so a composition longer than the rest of
  the row is clipped in the terminal itself; the panel shows the full typed
  text once that is about to happen (see `terminalMode`).

## License

GPL-3.0 — see [LICENSE](LICENSE). The 小鹤双拼 dictionaries come from
[rime-ice](https://github.com/iDvel/rime-ice) (GPL-3.0) and the shuangpin
engine ports algorithms from [librime](https://github.com/rime/librime)
(BSD-3-Clause); see [NOTICE](NOTICE).
