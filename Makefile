# The input method. Its bundle id (Resources/Info.plist) is what Input
# Sources knows it by; the folder was Fluent.app before the Settings app took
# that name, and install moves an old one in place.
IME_NAME      = Fluent-Input
IME_DIST      = dist/$(IME_NAME).app
INSTALL_DIR   = $(HOME)/Library/Input Methods
INSTALLED     = $(INSTALL_DIR)/$(IME_NAME).app
OLD_INSTALLED = $(INSTALL_DIR)/Fluent.app
# `make release` builds with CONFIG=release; everything else is a debug build.
CONFIG       ?= debug
BIN           = .build/$(CONFIG)/Fluent

# The Settings app (Fluent.app): Go + Wails in Settings/, the way magpie is
# built, sharing no code with the input method. Go fetches the toolchain
# Settings/go.mod names when the one on PATH is older (GOTOOLCHAIN=auto).
SETTINGS_DIR       = Settings
SETTINGS_DIST      = dist/Fluent.app
SETTINGS_BIN       = .build/settings/Fluent
SETTINGS_INSTALLED = /Applications/Fluent.app
# "Fluent Local Signing" once `make signing-identity` made it, else ad hoc.
SIGN_ID = $(shell security find-identity -p codesigning 2>/dev/null | grep -q '"Fluent Local Signing"' && echo "Fluent Local Signing" || echo -)
SETTINGS_VERSION   = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' $(SETTINGS_DIR)/build/darwin/Info.plist)
GO                 = GOTOOLCHAIN=auto go
# Wails links the webview through cgo: built for the macOS Info.plist names.
export CGO_CFLAGS  = -O2 -mmacosx-version-min=13.0
export CGO_LDFLAGS = -mmacosx-version-min=13.0

# 小鹤双拼 dictionaries: rime-ice (GPL-3.0), pinned so builds are
# reproducible. Bump the revision to pick up dictionary updates.
RIME_ICE_REV   = da1fbe602e38f26db846fa10120ee64c2b0324c0
RIME_ICE_URL   = https://raw.githubusercontent.com/iDvel/rime-ice/$(RIME_ICE_REV)
RIME_ICE_DIR   = .build/rime-ice-$(RIME_ICE_REV)
RIME_ICE_FILES = $(addprefix $(RIME_ICE_DIR)/,cn_dicts/8105.dict.yaml cn_dicts/base.dict.yaml en_dicts/en.dict.yaml)
DICT_DIR       = .build/dict

.PHONY: build bundle bundle-ime bundle-settings settings settings-icon install release signing-identity register reload logs dev test cli clean icon dict

build:
	swift build -c $(CONFIG)

test:
	swift test
	cd $(SETTINGS_DIR) && $(GO) vet ./... && $(GO) test ./...

# API smoke test through the debug CLI, e.g.:
#   make cli ARGS='--mode polish "helo wrld"'
# or the shuangpin engine (after make dict):
#   make cli ARGS='--xiaohe veui nihc'
cli:
	swift run fluent-cli $(ARGS)

# The input method's menu-bar icon.
icon: Resources/icon.tiff

Resources/icon.tiff: Scripts/make-icon.swift
	swift Scripts/make-icon.swift Resources/icon.tiff

# The Settings app's icon, drawn by Settings/build/icon. What it makes is
# kept in the tree, so a build needs neither the generator nor actool.
ICON_TOOL = .build/settings/icon
ICONSET   = .build/settings/AppIcon.iconset
ACTOOL    = .build/settings/actool
settings-icon:
	cd $(SETTINGS_DIR) && $(GO) build -o "$(CURDIR)/$(ICON_TOOL)" ./build/icon
	$(ICON_TOOL) app 256 $(SETTINGS_DIR)/assets/icon.png
	rm -rf $(ICONSET) && mkdir -p $(ICONSET)
	for s in 16 32 128 256 512; do \
		$(ICON_TOOL) app $$s $(ICONSET)/icon_$${s}x$${s}.png && \
		$(ICON_TOOL) app $$((s * 2)) $(ICONSET)/icon_$${s}x$${s}@2x.png || exit 1; \
	done
	iconutil -c icns $(ICONSET) -o $(SETTINGS_DIR)/build/darwin/AppIcon.icns
	@# macOS 26 draws the Dock icon from AppIcon.icon, light or dark (Xcode 26's actool)
	$(ICON_TOOL) glyph 1024 $(SETTINGS_DIR)/build/darwin/AppIcon.icon/Assets/glyph.png
	rm -rf $(ACTOOL) && mkdir -p $(ACTOOL)
	xcrun actool $(SETTINGS_DIR)/build/darwin/AppIcon.icon --compile $(ACTOOL) --platform macosx \
		--minimum-deployment-target 13.0 --app-icon AppIcon --output-partial-info-plist $(ACTOOL)/partial.plist >/dev/null
	mv $(ACTOOL)/Assets.car $(SETTINGS_DIR)/build/darwin/Assets.car

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

# The pages are embedded in the binary (Settings/assets).
bundle-settings:
	cd $(SETTINGS_DIR) && $(GO) build -tags production -trimpath \
		-ldflags "-s -w -X main.version=$(SETTINGS_VERSION)" -o "$(CURDIR)/$(SETTINGS_BIN)" .
	rm -rf "$(SETTINGS_DIST)"
	mkdir -p "$(SETTINGS_DIST)/Contents/MacOS" "$(SETTINGS_DIST)/Contents/Resources"
	cp "$(SETTINGS_BIN)" "$(SETTINGS_DIST)/Contents/MacOS/Fluent"
	cp $(SETTINGS_DIR)/build/darwin/Info.plist "$(SETTINGS_DIST)/Contents/Info.plist"
	cp $(SETTINGS_DIR)/build/darwin/AppIcon.icns $(SETTINGS_DIR)/build/darwin/Assets.car LICENSE NOTICE \
		"$(SETTINGS_DIST)/Contents/Resources/"

# Sync bundle contents in place: deleting the installed input method would
# silently un-register and disable the input source in Text Input Services,
# so an old Fluent.app is moved to the new name rather than replaced.
install: bundle
	if [ -d "$(OLD_INSTALLED)" ] && [ ! -e "$(INSTALLED)" ]; then mv "$(OLD_INSTALLED)" "$(INSTALLED)"; fi
	mkdir -p "$(INSTALLED)"
	rsync -a --delete "$(IME_DIST)/" "$(INSTALLED)/"
	codesign --force --sign "$(SIGN_ID)" "$(INSTALLED)"
	swift Scripts/register.swift
	Scripts/forget-stale-input-caches.sh "$(INSTALLED)"
	mkdir -p "$(SETTINGS_INSTALLED)"
	rsync -a --delete "$(SETTINGS_DIST)/" "$(SETTINGS_INSTALLED)/"
	codesign --force --sign "$(SIGN_ID)" "$(SETTINGS_INSTALLED)"

# Both apps for a GitHub release, optimized and signed ad hoc (a local
# signing identity means nothing on another Mac), in one zip that unpacks to
# a Fluent-<version> folder: dist/Fluent-<version>-macos-<arch>.zip.
VERSION     = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
RELEASE_DIR = dist/release/Fluent-$(VERSION)
RELEASE_ZIP = dist/Fluent-$(VERSION)-macos-$(shell uname -m).zip
release:
	$(MAKE) bundle CONFIG=release
	rm -rf dist/release "$(RELEASE_ZIP)"
	mkdir -p "$(RELEASE_DIR)"
	cp -R "$(IME_DIST)" "$(SETTINGS_DIST)" "$(RELEASE_DIR)/"
	codesign --force --sign - "$(RELEASE_DIR)/$(IME_NAME).app"
	codesign --force --sign - "$(RELEASE_DIR)/Fluent.app"
	ditto -c -k --norsrc --keepParent "$(RELEASE_DIR)" "$(RELEASE_ZIP)"
	shasum -a 256 "$(RELEASE_ZIP)"

# A self-signed identity to sign with instead of ad hoc, so an Input
# Monitoring grant survives rebuilds (Scripts/signing-identity.sh).
signing-identity:
	Scripts/signing-identity.sh

# Build the Settings app and open it from dist/, for working on its pages.
settings: bundle-settings
	codesign --force --sign "$(SIGN_ID)" "$(SETTINGS_DIST)"
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
