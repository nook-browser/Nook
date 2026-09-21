#!/bin/bash
# Refreshes the vendored uBlock Origin scriptlet resources and regenerates the
# manifest. Pass a commit SHA to pin a specific one, otherwise takes the newest
# commit that touched src/js/resources.
#
# These bodies are GPL-3.0 and are not Nook's. The iOS target must not ship them;
# see the #if os(iOS) in ScriptletResources.swift.
set -euo pipefail

cd "$(dirname "$0")/.."
DEST="Packages/NookBlocker/ThirdParty/ubo-scriptlets"
REPO="https://raw.githubusercontent.com/gorhill/uBlock"

SHA="${1:-$(curl -fsSL "https://api.github.com/repos/gorhill/uBlock/commits?path=src/js/resources&per_page=1" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["sha"])')}"
echo "Pinning uBlock Origin at $SHA"

# Imports reach outside the resources directory, so the upstream layout is kept.
for f in $(curl -fsSL "https://api.github.com/repos/gorhill/uBlock/contents/src/js/resources?ref=$SHA" \
  | python3 -c 'import sys,json; [print(e["name"]) for e in json.load(sys.stdin)]'); do
    curl -fsSL -o "$DEST/src/js/resources/$f" "$REPO/$SHA/src/js/resources/$f"
done
for f in arglist-parser.js jsonpath.js urlskip.js redirect-resources.js; do
    curl -fsSL -o "$DEST/src/js/$f" "$REPO/$SHA/src/js/$f"
done

# The redirect resources answer $redirect= rules; see scripts/build-redirects.mjs.
for f in $(curl -fsSL "https://api.github.com/repos/gorhill/uBlock/contents/src/web_accessible_resources?ref=$SHA" \
  | python3 -c 'import sys,json; [print(e["name"]) for e in json.load(sys.stdin)]'); do
    curl -fsSL -o "$DEST/src/web_accessible_resources/$f" "$REPO/$SHA/src/web_accessible_resources/$f"
done

echo "$SHA" > "$DEST/UPSTREAM_COMMIT"
sed -i '' -E "s/commit \`[0-9a-f]{40}\`/commit \`$SHA\`/" "$DEST/README.md"
node scripts/build-scriptlets.mjs
node scripts/build-redirects.mjs
node scripts/check-redirects.mjs
echo "Now run: cd Nook/ThirdParty/AdblockRustFFI && cargo test --test real_lists_scriptlets"
