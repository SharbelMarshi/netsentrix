# Optional dev shortcuts (see README for full paths).
.PHONY: engine app app-run test-engine test-app

engine:
	cd engine && cargo run

app:
	cd app && swift build

app-run:
	cd app && swift run NetSentrix

test-engine:
	cd engine && cargo test

test-app:
	cd app && swift build
