# English Input

A macOS InputMethodKit IME that improves English phrases as you type via an
OpenAI Responses-compatible API. See README.md for usage and architecture.

## Commit messages

Write plain commit messages with no AI attribution: do not append
`Co-Authored-By: Claude ...`, `Claude-Session: ...`, "Generated with Claude
Code", or any similar marker/trailer.

## Development

- Build: `swift build` · Tests: `swift test` (core library only, no GUI needed)
- Install/iterate: `make dev` (rebuild → reinstall to `~/Library/Input Methods` → kill IME; macOS relaunches it on next keystroke)
- Logs: `make logs` · API smoke test: `swift run english-input-cli --mode polish "text"`
- `Sources/EnglishInputCore/` must stay AppKit-free so it remains unit-testable; IMK/AppKit code lives in `Sources/EnglishInput/`.
- All IMK client calls (`setMarkedText`, `insertText`, panel updates) must run on the main thread.
- Info.plist's `InputMethodConnectionName` must match the string passed to `IMKServer` in `main.swift`, or the IME silently never connects.
