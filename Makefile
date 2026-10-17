APP_NAME    = Fluent
DIST        = dist/$(APP_NAME).app
INSTALL_DIR = $(HOME)/Library/Input Methods
INSTALLED   = $(INSTALL_DIR)/$(APP_NAME).app
BIN         = .build/debug/$(APP_NAME)

# 小鹤双拼 dictionaries: rime-ice (GPL-3.0), pinned so builds are
# reproducible. Bump the revision to pick up dictionary updates.
RIME_ICE_REV   = da1fbe602e38f26db846fa10120ee64c2b0324c0
RIME_ICE_URL   = https://raw.githubusercontent.com/iDvel/rime-ice/$(RIME_ICE_REV)
RIME_ICE_DIR   = .build/rime-ice-$(RIME_ICE_REV)
RIME_ICE_FILES = $(addprefix $(RIME_ICE_DIR)/,cn_dicts/8105.dict.yaml cn_dicts/base.dict.yaml)
DICT_DIR       = .build/dict

.PHONY: build bundle install register reload logs dev test cli clean icon dict

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

icon: Resources/icon.tiff

Resources/icon.tiff: Scripts/make-icon.swift
	swift Scripts/make-icon.swift Resources/icon.tiff

# Download the pinned rime-ice sources and compile them into the compact
# files the IME loads (not committed: they are build products).
dict: $(DICT_DIR)/xiaohe.lexicon

$(DICT_DIR)/xiaohe.lexicon: $(RIME_ICE_FILES) Sources/FluentDict/main.swift \
		Sources/FluentCore/Lexicon.swift Sources/FluentCore/Xiaohe.swift
	swift run fluent-dict "$(RIME_ICE_DIR)" "$(DICT_DIR)"

$(RIME_ICE_DIR)/%:
	mkdir -p "$(dir $@)"
	curl -fsSL --retry 3 -o "$@.part" "$(RIME_ICE_URL)/$*"
	mv "$@.part" "$@"

bundle: build icon dict
	rm -rf "$(DIST)"
	mkdir -p "$(DIST)/Contents/MacOS" "$(DIST)/Contents/Resources"
	cp "$(BIN)" "$(DIST)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(DIST)/Contents/Info.plist"
	cp Resources/icon.tiff "$(DIST)/Contents/Resources/icon.tiff"
	cp "$(DICT_DIR)/xiaohe.lexicon" LICENSE NOTICE "$(DIST)/Contents/Resources/"

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
	swift Scripts/reactivate.swift

# Re-register/enable the input source with TIS (also runs as part of install).
register:
	swift Scripts/register.swift

logs:
	log stream --predicate 'subsystem == "com.yangxin.inputmethod.Fluent"' --level debug

dev: install reload

clean:
	rm -rf .build dist
