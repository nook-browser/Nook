#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
# Exercise lightweight migration from the exact pre-activeTabId schema in a separate process.
python3 - "$test_dir" <<'PY'
from pathlib import Path
import sys
out = Path(sys.argv[1])
space = Path('Nook/Models/Space/SpaceModels.swift').read_text()
space = '\n'.join(line for line in space.splitlines() if 'var activeTabId:' not in line and 'self.activeTabId =' not in line)
space = space.replace(', activeTabId: UUID? = nil', '')
(out / 'LegacySpaceModels.swift').write_text(space)
actor = Path('Nook/Managers/TabManager/TabManager.swift').read_text().split('\n@MainActor\nclass TabManager:', 1)[0]
assert 'actor PersistenceActor' in actor and 'class TabManager:' not in actor
(out / 'PersistenceActor.swift').write_text(actor)
(out / 'SpaceGradient.swift').write_text('import Foundation\nstruct SpaceGradient { static let `default` = SpaceGradient(); var encoded: Data? { Data() }; static func decode(_ data: Data) -> SpaceGradient { .default } }\n')
source = Path('Nook/Managers/TabManager/TabManager.swift').read_text()
load = source.split('    private func loadFromStore() {', 1)[1]
spaces = load.split('            // Spaces\n', 1)[1].split('            // Ensure all spaces have profile assignments', 1)[0]
folders = load.split('            // Folders\n', 1)[1].split('            // Attach browser manager', 1)[0]
selection = source.split('    private func validActiveTabID(', 1)[1].split('    // Build a persistence snapshot', 1)[0]
(out / 'RestorationSections.swift').write_text('import SwiftData\nimport Foundation\nimport AppKit\nextension RestorationFixture {\nfunc loadSpaces() throws {\n' + spaces + '\n}\nfunc loadFoldersAndRepair() throws {\n' + folders + '\n}\nfunc validActiveTabID(' + selection + '\n}\n')
PY
xcrun swiftc -parse-as-library -module-name TabPersistenceRegression -D LEGACY_SCHEMA \
    Nook/Models/Tab/TabsModel.swift "$test_dir/LegacySpaceModels.swift" "$test_dir/SpaceGradient.swift" \
    scripts/tests/tab-persistence-regression.swift -o "$test_dir/old"
"$test_dir/old" "$test_dir/tabs.store"
xcrun swiftc -parse-as-library -module-name TabPersistenceRegression \
    Nook/Models/Tab/TabsModel.swift Nook/Models/Space/SpaceModels.swift "$test_dir/SpaceGradient.swift" \
    "$test_dir/PersistenceActor.swift" Nook/Utils/BrowserPerformance.swift \
    scripts/tests/tab-persistence-restoration.swift "$test_dir/RestorationSections.swift" \
    scripts/tests/tab-persistence-regression.swift -o "$test_dir/new"
"$test_dir/new" "$test_dir/tabs.store"
"$test_dir/new" "$test_dir/tabs.store" verify-restart
