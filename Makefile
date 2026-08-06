APP_NAME := Post
BUNDLE := $(APP_NAME).app
INSTALL_DIR := /Applications

build:
	swift build -c release

bundle: build icon
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	command cp .build/release/Post $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	command cp Info.plist $(BUNDLE)/Contents/Info.plist
	@if [ -f AppIcon.icns ]; then \
		command cp AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns; \
	fi

icon:
	@if [ ! -f AppIcon.icns ] && [ -f scripts/generate-icon.swift ]; then \
		swift scripts/generate-icon.swift; \
	fi

deploy: bundle
	pkill -9 -f "$(APP_NAME)" 2>/dev/null || true
	@sleep 1
	command rm -rf $(INSTALL_DIR)/$(BUNDLE)
	ditto $(BUNDLE) $(INSTALL_DIR)/$(BUNDLE)
	@if [ -f $(INSTALL_DIR)/$(BUNDLE)/Contents/Resources/AppIcon.icns ]; then \
		osascript -e 'use framework "AppKit"' \
			-e 'set iconImage to current application'\''s NSImage'\''s alloc()'\''s initWithContentsOfFile:"$(INSTALL_DIR)/$(BUNDLE)/Contents/Resources/AppIcon.icns"' \
			-e 'current application'\''s NSWorkspace'\''s sharedWorkspace()'\''s setIcon:iconImage forFile:"$(INSTALL_DIR)/$(BUNDLE)" options:0'; \
	fi
	@echo "Deployed to $(INSTALL_DIR)/$(BUNDLE)"
	open $(INSTALL_DIR)/$(BUNDLE)

clean:
	rm -rf .build $(BUNDLE)

test:
	swift test

.PHONY: build bundle icon deploy clean test
