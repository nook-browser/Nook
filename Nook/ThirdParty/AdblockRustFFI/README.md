# AdblockRustFFI

A thin C ABI over Brave's [adblock-rust](https://github.com/brave/adblock-rust) (`adblock` crate, MPL-2.0, compatible with Nook's GPL-3.0). Nook already blocks with `WKContentRuleList`; this engine only answers "would this URL be blocked?" so the UI can count blocked requests per tab. Exact parity with WebKit's blocking is not a goal.

Files: `Cargo.toml` + `src/lib.rs` (crate), `include/nook_adblock.h` (hand-written header, imported via the bridging header), `lib/macos-arm64/libnook_adblock.a` (committed, release-stripped, so machines without Rust can build the app).

## Rebuild

    ./build.sh

Requires rustup with the `aarch64-apple-darwin` target (default on Apple Silicon). The script runs `cargo test`, builds release with LTO, and copies the `.a` into `lib/`. Commit the updated `.a`. Bump the `adblock` version in `Cargo.toml` to upgrade; re-run the tests since the API moves between minor versions.

## iOS slices

Uncomment the stanza in `build.sh` after `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`, then either add per-SDK `LIBRARY_SEARCH_PATHS` or wrap the slices in an `.xcframework` (command in the script).

## Thread safety

An engine pointer is Send but not Sync: serialize every call on a given engine (one actor or serial queue). Different engines can be used from different threads at the same time.
