#!/bin/bash
# Compiles the Foundation-level logic plus tests/main.swift into a scratch binary and runs it.
# Does not touch build.sh or the installed app. Exit code 0 = all checks passed.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)/onyx-tests"
swiftc -target arm64-apple-macos14.0 -sdk "$(xcrun --show-sdk-path)" \
    "$DIR/Sources/Core/URLClassifier.swift" \
    "$DIR/Sources/Passwords/PasswordVault.swift" \
    "$DIR/Sources/Support/JavaScript.swift" \
    "$DIR/Sources/Support/Persistence.swift" \
    "$DIR/Sources/Models/BookmarkItem.swift" \
    "$DIR/Sources/Models/BrowserProfile.swift" \
    "$DIR/Sources/Support/Extensions.swift" \
    "$DIR/tests/main.swift" -o "$OUT"
"$OUT"
