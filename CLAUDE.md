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

- `make build` · `make test` (core library only, no GUI needed)
- First-time setup: `make install` (build → bundle → rsync into `~/Library/Input Methods` → ad-hoc codesign → register/enable with TIS). Never `rm -rf` the installed bundle: deleting it un-registers and disables the input source, which is why `install` syncs contents in place and re-registers every time.
- Iterate: `make dev` (= `install` + `reload`: rebuild → reinstall → `pkill` the IME → re-activate the input source via `Scripts/reactivate.swift`; macOS relaunches it on next keystroke). The re-activation matters: after a kill, the front app keeps delivering keyDown to the new process but not modifier-only (`flagsChanged`) events until the input source is re-selected, so the ⇧⇧ toggle silently dies until the user switches apps. `make reload` alone kills + re-activates without rebuilding.
- `make logs` · API smoke test: `make cli ARGS='--mode polish "helo wrld"'`
- `make dict` downloads the rime-ice dictionaries pinned by `RIME_ICE_REV` and compiles them into `.build/dict` (`xiaohe.lexicon` + `english.txt`; build products, never committed); `bundle`/`install` run it. Shuangpin smoke test: `make cli ARGS='--xiaohe veui'`. The lexicon stores syllable ids, so changing `Pinyin.syllables` needs a `make dict` (stale files are rejected by `Pinyin.tableHash`).
- `make clean` removes `.build/` and `dist/`
- `Sources/FluentCore/` must stay AppKit-free so it remains unit-testable; IMK/AppKit code lives in `Sources/Fluent/`.
- All IMK client calls (`setMarkedText`, `insertText`, panel updates) must run on the main thread.
- Info.plist's `InputMethodConnectionName` must match the string passed to `IMKServer` in `main.swift`, or the IME silently never connects.
