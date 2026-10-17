# English Input

A macOS input method (IME) that improves your English as you type. Your raw
text appears inline as underlined composition text in any app; an LLM
continuously rewrites it in a floating preview panel; **Enter inserts the
improved text**, Shift+Enter inserts exactly what you typed, Esc cancels.

Powered by any **OpenAI Responses-API-compatible endpoint** (OpenAI, or any
provider exposing `/v1/responses` with SSE streaming).

## Modes

| Mode | What it does |
|---|---|
| **Fix** | Grammar, spelling, punctuation only — keeps your wording |
| **Polish** | Rewrites into natural, native-speaker English |
| **Interpret** | Turns rough / fragmentary / Chinese-mixed input into the intended English |

Switch modes from the input-method menu in the menu bar, or **Ctrl+Tab**
while composing. The last mode is remembered.

## Install

```sh
make install    # build, assemble EnglishInput.app, install to ~/Library/Input Methods, ad-hoc sign, register
```

Then (one-time, macOS requires manual consent for third-party input sources):

1. **System Settings ▸ Keyboard ▸ Text Input ▸ Input Sources ▸ Edit… ▸ +**
2. Under **English**, add **English Input**.
3. Pick **English Input** from the input menu in the menu bar (or Ctrl+Space).

## Configure

Edit `~/.config/english-input/config.json` (a template is created on first run;
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
`appearance` controls the preview panel's color scheme: `"auto"` follows the
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
| Ctrl+Tab | Cycle mode (Fix → Polish → Interpret) |
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

## Development

```sh
make dev        # rebuild + reinstall + kill the running IME (macOS relaunches it on next keystroke)
make test       # unit tests (SSE parser, config, prompts)
make logs       # tail the IME's os_log output
swift run english-input-cli --mode polish "helo wrold how r u"   # test the API path without the IME
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

GPL-3.0 — see [LICENSE](LICENSE).
