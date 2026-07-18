# Dev shortcuts (see README for details).
.PHONY: engine app app-run test-engine test-app bundle bundle-full bundle-app-only

XCODEBUILD = xcodebuild -project app/NetSentrix.xcodeproj -scheme NetSentrix -destination 'platform=macOS'

engine:
	cd engine && cargo run

app:
	$(XCODEBUILD) -configuration Debug build

app-run: app
	open "$$(xcodebuild -project app/NetSentrix.xcodeproj -scheme NetSentrix -configuration Debug -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $$3}')/NetSentrix.app"

test-engine:
	cd engine && cargo test

test-app:
	$(XCODEBUILD) test

# dist/NetSentrix.app — release app with the engine embedded (the app
# auto-starts it). bundle-full kept as an alias; bundle-app-only skips the engine.
bundle bundle-full:
	swift packaging/macos/app/bundle.swift

bundle-app-only:
	swift packaging/macos/app/bundle.swift --app-only
