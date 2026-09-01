# English Input

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
- First-time setup: `make install` (build → bundle → copy to `~/Library/Input Methods` → ad-hoc codesign) then `make register` (one-time; makes the source appear in System Settings ▸ Keyboard)
- Iterate: `make dev` (= `install` + `reload`: rebuild → reinstall → `pkill` the IME; macOS relaunches it on next keystroke). `make reload` alone just kills the running process.
- `make logs` · API smoke test: `make cli ARGS='--mode polish "helo wrld"'`
- `make clean` removes `.build/` and `dist/`
- `Sources/EnglishInputCore/` must stay AppKit-free so it remains unit-testable; IMK/AppKit code lives in `Sources/EnglishInput/`.
- All IMK client calls (`setMarkedText`, `insertText`, panel updates) must run on the main thread.
- Info.plist's `InputMethodConnectionName` must match the string passed to `IMKServer` in `main.swift`, or the IME silently never connects.
