# Repository Guidelines

## Project Structure & Module Organization
- App code lives in `Pulse/` with SwiftUI views under `Pulse/Components/<Feature>/`, logic in `Pulse/Managers/`, data types in `Pulse/Models/`, helpers in `Pulse/Utils/`, and assets in `Pulse/Assets.xcassets/`.
- Xcode project is `Pulse.xcodeproj`; the primary target and scheme are `Pulse`.
- Entry points: `Pulse/PulseApp.swift` (app + commands) and `Pulse/ContentView.swift`. Shared state is provided via `BrowserManager` as an `@EnvironmentObject`.

## Build, Test, and Development Commands
- Open in Xcode: `open Pulse.xcodeproj` (then select the `Pulse` scheme and run).
- CLI build: `xcodebuild -scheme Pulse -configuration Debug -destination 'platform=macOS' build`.
- Resolve SPM deps: `xcodebuild -resolvePackageDependencies` (uses the FaviconFinder package).
- Tests: No test target yet. If added, run with `⌘U` in Xcode or `xcodebuild -scheme Pulse test`.

## Coding Style & Naming Conventions
- Swift 5 + SwiftUI. Use Xcode’s formatter (Shift + Cmd + I) before committing.
- Indentation: 4 spaces; line length ~120 when practical.
- Types: PascalCase (`BrowserManager`, `SettingsView`); properties/functions: camelCase; files match the primary type (`Tab.swift`, `SidebarView.swift`).
- Views end with `View`; service objects end with `Manager`. Prefer `struct` for value types; use `final class` when reference semantics are required.
- Organize with `// MARK: -` and group by feature in `Components/`.

## Testing Guidelines
- Preferred framework: XCTest. Name files `FeatureNameTests.swift` and mirror source structure.
- Focus on unit tests for managers and models (e.g., cookie/cache/history behavior). UI is validated via smaller logic tests.
- No formal coverage threshold yet; include tests with new features or bug fixes when feasible.

## Commit & Pull Request Guidelines
- Messages: concise, imperative (“Fix cache eviction”), optionally scoped (“Managers: improve cookie cleanup”).
- Branching: open PRs against `dev` unless instructed otherwise.
- PRs include: a clear description, linked issues, test steps, and screenshots/GIFs for UI changes. Keep diffs focused and update docs when needed.

## Security & Configuration Tips
- macOS target: 15.5; Xcode 16.4+. Set your personal Development Team in Signing to run locally.
- Do not commit secrets or signing assets. Review extension-related permissions and user data handling when touching WebKit/extension code.
