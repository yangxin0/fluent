# The input method. Its bundle id (Resources/Info.plist) is what Input
# Sources knows it by; the folder was Fluent.app before the Settings app took
# that name, and install moves an old one in place.
IME_NAME      = Fluent-Input
IME_DIST      = dist/$(IME_NAME).app
INSTALL_DIR   = $(HOME)/Library/Input Methods
INSTALLED     = $(INSTALL_DIR)/$(IME_NAME).app
OLD_INSTALLED = $(INSTALL_DIR)/Fluent.app
BIN           = .build/debug/Fluent

# The Settings app: Sources/FluentSettings around the pages in Resources/Settings.
SETTINGS_DIST      = dist/Fluent.app
SETTINGS_BIN       = .build/debug/FluentSettings
SETTINGS_INSTALLED = /Applications/Fluent.app

# 小鹤双拼 dictionaries: rime-ice (GPL-3.0), pinned so builds are
# reproducible. Bump the revision to pick up dictionary updates.
RIME_ICE_REV   = da1fbe602e38f26db846fa10120ee64c2b0324c0
RIME_ICE_URL   = https://raw.githubusercontent.com/iDvel/rime-ice/$(RIME_ICE_REV)
RIME_ICE_DIR   = .build/rime-ice-$(RIME_ICE_REV)
RIME_ICE_FILES = $(addprefix $(RIME_ICE_DIR)/,cn_dicts/8105.dict.yaml cn_dicts/base.dict.yaml en_dicts/en.dict.yaml)
DICT_DIR       = .build/dict

.PHONY: build bundle bundle-ime bundle-settings settings install register reload logs dev test cli clean icon dict

build:
	swift build

test:
	swift test

# API smoke test through the debug CLI, e.g.:
#   make cli ARGS='--mode polish "helo wrld"'
# or the shuangpin engine (after make dict):
#   make cli ARGS='--xiaohe veui nihc'
cli:
	swift run fluent-cli $(ARGS)

icon: Resources/icon.tiff Resources/AppIcon.icns

Resources/icon.tiff: Scripts/make-icon.swift
	swift Scripts/make-icon.swift Resources/icon.tiff

Resources/AppIcon.icns: Scripts/make-app-icon.swift
	swift Scripts/make-app-icon.swift Resources/AppIcon.icns

# Download the pinned rime-ice sources and compile them into the compact
# files the IME loads (not committed: they are build products).
# One run writes both xiaohe.lexicon and english.txt.
dict: $(DICT_DIR)/xiaohe.lexicon

$(DICT_DIR)/xiaohe.lexicon: $(RIME_ICE_FILES) Sources/FluentDict/main.swift \
		Sources/FluentCore/Lexicon.swift Sources/FluentCore/Xiaohe.swift
	swift run fluent-dict "$(RIME_ICE_DIR)" "$(DICT_DIR)"

$(RIME_ICE_DIR)/%:
	mkdir -p "$(dir $@)"
	curl -fsSL --retry 3 -o "$@.part" "$(RIME_ICE_URL)/$*"
	mv "$@.part" "$@"

bundle: bundle-ime bundle-settings

bundle-ime: build icon dict
	rm -rf "$(IME_DIST)"
	mkdir -p "$(IME_DIST)/Contents/MacOS" "$(IME_DIST)/Contents/Resources"
	cp "$(BIN)" "$(IME_DIST)/Contents/MacOS/Fluent"
	cp Resources/Info.plist "$(IME_DIST)/Contents/Info.plist"
	cp Resources/icon.tiff "$(IME_DIST)/Contents/Resources/icon.tiff"
	cp "$(DICT_DIR)/xiaohe.lexicon" "$(DICT_DIR)/english.txt" LICENSE NOTICE "$(IME_DIST)/Contents/Resources/"

bundle-settings: build icon
	rm -rf "$(SETTINGS_DIST)"
	mkdir -p "$(SETTINGS_DIST)/Contents/MacOS" "$(SETTINGS_DIST)/Contents/Resources"
	cp "$(SETTINGS_BIN)" "$(SETTINGS_DIST)/Contents/MacOS/FluentSettings"
	cp Resources/Settings-Info.plist "$(SETTINGS_DIST)/Contents/Info.plist"
	cp Resources/AppIcon.icns LICENSE NOTICE "$(SETTINGS_DIST)/Contents/Resources/"
	cp -R Resources/Settings "$(SETTINGS_DIST)/Contents/Resources/Settings"

# Sync bundle contents in place: deleting the installed input method would
# silently un-register and disable the input source in Text Input Services,
# so an old Fluent.app is moved to the new name rather than replaced.
install: bundle
	if [ -d "$(OLD_INSTALLED)" ] && [ ! -e "$(INSTALLED)" ]; then mv "$(OLD_INSTALLED)" "$(INSTALLED)"; fi
	mkdir -p "$(INSTALLED)"
	rsync -a --delete "$(IME_DIST)/" "$(INSTALLED)/"
	codesign --force --sign - "$(INSTALLED)"
	swift Scripts/register.swift
	mkdir -p "$(SETTINGS_INSTALLED)"
	rsync -a --delete "$(SETTINGS_DIST)/" "$(SETTINGS_INSTALLED)/"
	codesign --force --sign - "$(SETTINGS_INSTALLED)"

# Build the Settings app and open it from dist/, for working on its pages.
settings: bundle-settings
	codesign --force --sign - "$(SETTINGS_DIST)"
	open "$(SETTINGS_DIST)"

# macOS relaunches the IME on the next keystroke in a client app (the
# pattern also matches a process started from the old Fluent.app).
reload:
	pkill -f "Input Methods/Fluent(-Input)?\.app/Contents/MacOS/Fluent" || true
	swift Scripts/reactivate.swift

# Re-register/enable the input source with TIS (also runs as part of install).
register:
	swift Scripts/register.swift

logs:
	log stream --predicate 'subsystem == "com.yangxin.inputmethod.Fluent"' --level debug

dev: install reload

clean:
	rm -rf .build dist
