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

# dist/NetSentrix.app from the release build (app only).
bundle:
	swift packaging/macos/app/bundle.swift

# Same, with the Rust engine embedded at Contents/Resources/bin/.
bundle-full:
	swift packaging/macos/app/bundle.swift --with-engine
