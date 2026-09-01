APP_NAME    = EnglishInput
DIST        = dist/$(APP_NAME).app
INSTALL_DIR = $(HOME)/Library/Input Methods
INSTALLED   = $(INSTALL_DIR)/$(APP_NAME).app
BIN         = .build/debug/$(APP_NAME)

.PHONY: build bundle install register reload logs dev test clean icon

build:
	swift build

test:
	swift test

icon: Resources/icon.tiff

Resources/icon.tiff: Scripts/make-icon.swift
	swift Scripts/make-icon.swift Resources/icon.tiff

bundle: build icon
	rm -rf "$(DIST)"
	mkdir -p "$(DIST)/Contents/MacOS" "$(DIST)/Contents/Resources"
	cp "$(BIN)" "$(DIST)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(DIST)/Contents/Info.plist"
	cp Resources/icon.tiff "$(DIST)/Contents/Resources/icon.tiff"

install: bundle
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED)"
	cp -R "$(DIST)" "$(INSTALLED)"
	codesign --force --sign - "$(INSTALLED)"

# macOS relaunches the IME on the next keystroke in a client app.
reload:
	pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" || true

# One-time: makes the input source appear in System Settings > Keyboard.
register:
	swift Scripts/register.swift

logs:
	log stream --predicate 'subsystem == "com.yangxin.inputmethod.EnglishInput"' --level debug

dev: install reload

clean:
	rm -rf .build dist
