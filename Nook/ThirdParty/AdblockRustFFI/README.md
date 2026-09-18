# AdblockRustFFI

A thin C ABI over Brave's [adblock-rust](https://github.com/brave/adblock-rust) (`adblock` crate, MPL-2.0, compatible with Nook's GPL-3.0). It backs two things in `Packages/NookBlocker`: converting ABP/uBlock filter rules into `WKContentRuleList` JSON (`RustContentBlockingConverter`, replacing AdGuard's GPL-3.0 SafariConverterLib), and a single `BlockerEngine` used for both per-URL cosmetic lookup and the `check_urls` DevMCP tool. Exact parity with WebKit's own blocking is not a goal.

Files: `Cargo.toml` + `src/lib.rs` (crate), `include/nook_adblock.h` (hand-written header) plus `include/module.modulemap`, and `NookAdblock.xcframework` (committed, release-stripped, so machines without Rust can build the app).

## Consumer

`build.sh` wraps the release static library and the header in `NookAdblock.xcframework` (currently one slice, `macos-arm64`). `Packages/NookBlocker/Package.swift` declares it as a `binaryTarget` named `NookAdblockFFI` and depends on it directly; there is no bridging header and no `HEADER_SEARCH_PATHS`/`LIBRARY_SEARCH_PATHS` entry in the Xcode project. Swift files import it as `import NookAdblockFFI`.

## Rebuild

    ./build.sh

Requires rustup with the `aarch64-apple-darwin` target (default on Apple Silicon). The script runs `cargo test`, builds release with LTO, and re-creates `NookAdblock.xcframework` from the fresh `.a` and the header. Commit the updated xcframework. Bump the `adblock` version in `Cargo.toml` to upgrade; re-run the tests since the API moves between minor versions.

## iOS slices

Phase 3 of the iOS port. Uncomment the stanza in `build.sh` after `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`, build for each target, and add the resulting `-library`/`-headers` pairs to the `xcodebuild -create-xcframework` invocation so the xcframework carries an iOS and iOS-simulator slice alongside macos-arm64.

## Thread safety

An engine pointer is Send but not Sync: serialize every call on a given engine (one actor or serial queue; `BlockerEngine` is `@MainActor`). Different engines can be used from different threads at the same time.
