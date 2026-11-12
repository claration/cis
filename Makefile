SCHEME	:= CIS
DMG		?= 0

.PHONY: all clean

all: build

clean:
	rm -rf _build

build:
	$(MAKE) clean

	xcodebuild \
		-project $(SCHEME).xcodeproj \
		-scheme $(SCHEME) \
		-arch x86_64 \
		-arch arm64 \
		-configuration Release \
		ONLY_ACTIVE_ARCH=NO
ifeq ($(DMG),1)
ifeq ($(shell command -v create-dmg 2>/dev/null),)
	$(error create-dmg is not installed)
endif
	create-dmg \
		--volname "$(SCHEME) Installer" \
		--background "Packaging/background.png" \
		--window-pos 200 120 \
		--window-size 1400 210 \
		--icon-size 100 \
		--icon $(SCHEME).app 20 95 \
		--hide-extension $(SCHEME).app \
		--app-drop-link 1200 95 \
		_build/$(SCHEME).dmg \
		_build/Applications/$(SCHEME).app
endif # DMG
