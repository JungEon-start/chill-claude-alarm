APP_NAME = Chill Claude
APP_EXEC = ChillClaude
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
SOURCES = $(wildcard ClaudeStatusBar/*.swift)
ARCH = $(shell uname -m)
INSTALL_DIR = $(HOME)/Applications
DMG_NAME = ChillClaude

.PHONY: build install uninstall clean run dmg

build: $(APP_BUNDLE)

$(APP_BUNDLE): $(SOURCES) ClaudeStatusBar/Info.plist
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	swiftc -parse-as-library \
		-framework SwiftUI -framework AppKit \
		-target $(ARCH)-apple-macos13.0 \
		-o "$(APP_BUNDLE)/Contents/MacOS/$(APP_EXEC)" \
		$(SOURCES)
	@cp ClaudeStatusBar/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@# Generate app icon from chill-claude.png
	@mkdir -p $(BUILD_DIR)/AppIcon.iconset
	@sips -z 512 512 chill-claude.png --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512.png > /dev/null 2>&1
	@sips -z 256 256 chill-claude.png --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256.png > /dev/null 2>&1
	@sips -z 128 128 chill-claude.png --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128.png > /dev/null 2>&1
	@sips -z 64 64 chill-claude.png --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32@2x.png > /dev/null 2>&1
	@sips -z 32 32 chill-claude.png --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32.png > /dev/null 2>&1
	@sips -z 16 16 chill-claude.png --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16.png > /dev/null 2>&1
	@iconutil -c icns $(BUILD_DIR)/AppIcon.iconset -o "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@rm -rf $(BUILD_DIR)/AppIcon.iconset
	@cp scripts/update-status.sh "$(APP_BUNDLE)/Contents/Resources/update-status.sh"
	@cp running.png "$(APP_BUNDLE)/Contents/Resources/running.png"
	@cp coffee3.png "$(APP_BUNDLE)/Contents/Resources/coffee3.png"
	@cp config/settings.sample.json "$(APP_BUNDLE)/Contents/Resources/settings.sample.json"

install: build
	@bash scripts/install.sh

uninstall:
	@bash scripts/uninstall.sh

run: build
	@open "$(APP_BUNDLE)"

dmg: build
	@echo "Creating DMG..."
	@rm -f $(BUILD_DIR)/$(DMG_NAME).dmg
	@python3 scripts/create-dmg-bg.py $(BUILD_DIR)/dmg-bg.png
	create-dmg \
		--volname "$(APP_NAME)" \
		--volicon "chill-claude.png" \
		--background "$(BUILD_DIR)/dmg-bg.png" \
		--window-pos 200 120 \
		--window-size 540 300 \
		--icon-size 96 \
		--icon "$(APP_NAME).app" 150 150 \
		--app-drop-link 390 150 \
		--no-internet-enable \
		"$(BUILD_DIR)/$(DMG_NAME).dmg" \
		"$(APP_BUNDLE)"
	@echo "DMG created: $(BUILD_DIR)/$(DMG_NAME).dmg"

release-zip: build
	@cd $(BUILD_DIR) && zip -r $(DMG_NAME).zip "$(APP_NAME).app"
	@echo "Release zip created: $(BUILD_DIR)/$(DMG_NAME).zip"

clean:
	@rm -rf $(BUILD_DIR)
