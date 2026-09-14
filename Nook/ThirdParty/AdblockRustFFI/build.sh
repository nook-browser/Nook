#!/bin/sh
# Builds libnook_adblock.a (release, stripped) for macOS arm64 and copies it
# into lib/ so machines without a Rust toolchain can still build Nook.
set -eu
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
# Keep cargo output out of Nook/ (a filesystem-synchronized Xcode group would
# otherwise copy every target/ file into the app bundle). build/ is gitignored.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$PWD/../../../build/AdblockRustFFI-target}"

cargo test --release
cargo build --release --target aarch64-apple-darwin
mkdir -p lib/macos-arm64
cp "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/libnook_adblock.a" lib/macos-arm64/

# iOS slices (later). First: rustup target add aarch64-apple-ios aarch64-apple-ios-sim
# cargo build --release --target aarch64-apple-ios
# cargo build --release --target aarch64-apple-ios-sim
# mkdir -p lib/ios-arm64 lib/ios-sim-arm64
# cp "$CARGO_TARGET_DIR"/aarch64-apple-ios/release/libnook_adblock.a lib/ios-arm64/
# cp "$CARGO_TARGET_DIR"/aarch64-apple-ios-sim/release/libnook_adblock.a lib/ios-sim-arm64/
# Then point LIBRARY_SEARCH_PATHS per SDK, or wrap all slices in an .xcframework:
# xcodebuild -create-xcframework -library lib/macos-arm64/libnook_adblock.a -headers include \
#   -library lib/ios-arm64/libnook_adblock.a -headers include \
#   -library lib/ios-sim-arm64/libnook_adblock.a -headers include -output NookAdblock.xcframework

ls -lh lib/macos-arm64/libnook_adblock.a
