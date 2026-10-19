# Fluent

A macOS InputMethodKit IME that improves English phrases as you type via an
OpenAI Responses-compatible API. See README.md for usage and architecture.

## Commit messages

Write plain commit messages with no AI attribution: do not append
`Co-Authored-By: Claude ...`, `Claude-Session: ...`, "Generated with Claude
Code", or any similar marker/trailer.

## Development

The `Makefile` is the entrypoint for every task — use `make <target>`, not raw
`swift`/`codesign`/`log` commands, so this doc and the build stay in sync.

- `make build` · `make test` (the Swift core library, then the Settings app's Go tests; no GUI needed)
- First-time setup: `make install` (build → bundle → rsync the input method into `~/Library/Input Methods/Fluent-Input.app` → ad-hoc codesign → register/enable with TIS → forget per-app input-source caches that still list it at another path → rsync the Settings app into `/Applications/Fluent.app`). Each app (every sandboxed one has its own, under `DARWIN_USER_CACHE_DIR`) caches where input methods live; one still pointing at an old path can't switch to Fluent at all and only rebuilds when relaunched. Never `rm -rf` the installed input method: deleting it un-registers and disables the input source, which is why `install` syncs contents in place, moves a pre-rename `Fluent.app` to the new name instead of replacing it, and re-registers every time. Its bundle id `com.yangxin.inputmethod.Fluent` is what Input Sources knows it by: keep it.
- Iterate: `make dev` (= `install` + `reload`: rebuild → reinstall → `pkill` the IME → re-activate the input source via `Scripts/reactivate.swift`; macOS relaunches it on next keystroke). The re-activation matters: after a kill, the front app keeps delivering keyDown to the new process but not modifier-only (`flagsChanged`) events until the input source is re-selected, so the ⇧⇧ toggle silently dies until the user switches apps. `make reload` alone kills + re-activates without rebuilding.
- Settings app (`Fluent.app`): Go + Wails v3 in `Settings/`, magpie's stack, with its own `go.mod`. It shares **no code** with the Swift side: the two meet only in the files and the notification `docs/config.md` describes, so a change to the config's keys or rules updates both sides and that page (the sample files in `docs/config-examples/` are checked by both test suites). The plain HTML/CSS/JS pages are `Settings/assets` (embedded; English strings are the keys of `i18n.js`) and call Go through `fluent(op, args)`, a `fetch` to `/api/<op>` (`api.go`). `make settings` builds it and opens it from `dist/`. The Makefile runs Go with `GOTOOLCHAIN=auto`, so the toolchain `Settings/go.mod` names is fetched when the one on PATH is older; Wails is pinned to the version magpie uses. Its icon comes from `Settings/build/icon` via `make settings-icon` (outputs committed).
- `make logs` · API smoke test: `make cli ARGS='--mode polish "helo wrld"'`
- `make dict` downloads the rime-ice dictionaries pinned by `RIME_ICE_REV` and compiles them into `.build/dict` (`xiaohe.lexicon` + `english.txt`; build products, never committed); `bundle`/`install` run it. Chinese smoke tests: `make cli ARGS='--xiaohe veui'` (小鹤双拼) and `make cli ARGS='--pinyin nihao'` (full pinyin). The lexicon stores syllable ids, so changing `Pinyin.syllables` needs a `make dict` (stale files are rejected by `Pinyin.tableHash`).
- `make clean` removes `.build/` and `dist/`
- `Sources/FluentCore/` must stay AppKit-free so it remains unit-testable; IMK/AppKit code lives in `Sources/Fluent/`.
- All IMK client calls (`setMarkedText`, `insertText`, panel updates) must run on the main thread.
- `main.swift` passes Info.plist's `InputMethodConnectionName` to `IMKServer` (its hard-coded fallback must match it), or the IME silently never connects.
