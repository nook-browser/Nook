#!/bin/bash
# Refresh the bundled filter-list snapshots in Nook/Managers/ContentBlockerManager/Resources.
# Run before a release (CI does) so first-run protection ships with current lists.
# Keep the URL/filename pairs in sync with FilterListManager.defaultLists.
set -euo pipefail
DEST="$(cd "$(dirname "$0")/.." && pwd)/Nook/Managers/ContentBlockerManager/Resources"
LISTS=(
  "easylist.txt|https://easylist.to/easylist/easylist.txt"
  "easyprivacy.txt|https://easylist.to/easylist/easyprivacy.txt"
  "peter-lowes.txt|https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=0&mimetype=plaintext"
  "ublock-filters.txt|https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt"
  "ublock-unbreak.txt|https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt"
  "ublock-badware.txt|https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt"
  "ublock-privacy.txt|https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt"
  "ublock-quick-fixes.txt|https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt"
  "adguard-url-tracking.txt|https://filters.adtidy.org/extension/ublock/filters/17.txt"
  "urlhaus-filter.txt|https://malware-filter.gitlab.io/malware-filter/urlhaus-filter-online.txt"
)
for entry in "${LISTS[@]}"; do
  name="${entry%%|*}"; url="${entry#*|}"
  tmp="$(mktemp)"
  curl -sfL --max-time 90 "$url" -o "$tmp"
  first="$(grep -m1 -v '^[[:space:]]*$' "$tmp" || true)"
  if [ "$(wc -c < "$tmp")" -lt 5000 ] || ! [[ "$first" == "["* || "$first" == "!"* || "$first" == "#"* ]]; then
    echo "refresh-filter-lists: $name looks wrong (size $(wc -c < "$tmp"), first line: ${first:0:40}); keeping old copy" >&2
    rm -f "$tmp"; continue
  fi
  mv "$tmp" "$DEST/$name"
  echo "$name $(wc -c < "$DEST/$name") bytes"
done
