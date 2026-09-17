#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
# Compile the same model without the new indexes to seed an actual old store.
sed '/#Index<HistoryEntity>/d' Packages/NookWeb/Sources/NookWeb/HistoryEntity.swift > "$test_dir/HistoryEntity.swift"
xcrun swiftc -parse-as-library -module-name HistoryRegression "$test_dir/HistoryEntity.swift" Packages/NookWeb/Sources/NookWeb/HistoryManager.swift Packages/NookWeb/Sources/NookWeb/BrowserPerformance.swift scripts/tests/history-regression.swift -o "$test_dir/old"
"$test_dir/old" "$test_dir/history.store" seed
xcrun swiftc -parse-as-library -module-name HistoryRegression Packages/NookWeb/Sources/NookWeb/HistoryEntity.swift Packages/NookWeb/Sources/NookWeb/HistoryManager.swift Packages/NookWeb/Sources/NookWeb/BrowserPerformance.swift scripts/tests/history-regression.swift -o "$test_dir/new"
"$test_dir/new" "$test_dir/history.store"
