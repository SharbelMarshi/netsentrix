# Optional dev shortcuts (see README for full paths).
.PHONY: engine app app-run test-engine test-app bundle bundle-full

engine:
	cd engine && cargo run

app:
	cd app && swift build

app-run:
	cd app && swift run NetSentrix

test-engine:
	cd engine && cargo test

test-app:
	cd app && swift test

# dist/NetSentrix.app — release app with the engine embedded (the app
# auto-starts it). bundle-full kept as an alias; use --app-only to skip.
bundle bundle-full:
	swift packaging/macos/app/bundle.swift

bundle-app-only:
	swift packaging/macos/app/bundle.swift --app-only
