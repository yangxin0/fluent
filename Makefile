APP_NAME    = EnglishInput
DIST        = dist/$(APP_NAME).app
INSTALL_DIR = $(HOME)/Library/Input Methods
INSTALLED   = $(INSTALL_DIR)/$(APP_NAME).app
BIN         = .build/debug/$(APP_NAME)

.PHONY: build bundle install register reload logs dev test cli clean icon

build:
	swift build

test:
	swift test

# API smoke test through the debug CLI, e.g.:
#   make cli ARGS='--mode polish "helo wrld"'
cli:
	swift run english-input-cli $(ARGS)

icon: Resources/icon.tiff

Resources/icon.tiff: Scripts/make-icon.swift
	swift Scripts/make-icon.swift Resources/icon.tiff

bundle: build icon
	rm -rf "$(DIST)"
	mkdir -p "$(DIST)/Contents/MacOS" "$(DIST)/Contents/Resources"
	cp "$(BIN)" "$(DIST)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(DIST)/Contents/Info.plist"
	cp Resources/icon.tiff "$(DIST)/Contents/Resources/icon.tiff"

# Sync bundle contents in place: deleting the installed .app would silently
# un-register and disable the input source in Text Input Services.
install: bundle
	mkdir -p "$(INSTALLED)"
	rsync -a --delete "$(DIST)/" "$(INSTALLED)/"
	codesign --force --sign - "$(INSTALLED)"
	swift Scripts/register.swift

# macOS relaunches the IME on the next keystroke in a client app.
reload:
	pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" || true

# Re-register/enable the input source with TIS (also runs as part of install).
register:
	swift Scripts/register.swift

logs:
	log stream --predicate 'subsystem == "com.yangxin.inputmethod.EnglishInput"' --level debug

dev: install reload

clean:
	rm -rf .build dist
