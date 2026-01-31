# Repository Guidelines

## Project Structure & Module Organization
- `CopilotCompanionApp/`: Swift Package library with sources and tests.
  - `Sources/CopilotCompanionApp/`: App library code (e.g., `FolderWatcher`, SwiftUI scene).
  - `Tests/CopilotCompanionAppTests/`: Tests using Swift Testing.
- `CopilotCompanion/`: macOS SwiftUI app wrapper importing the library.
- `CopilotCompanion.xcodeproj/`: Xcode project for building/running the app.
- `justfile`: Common developer commands.
- `copilot-watcher.mjs`: Utility script (optional, not required for builds).

## Build, Test, and Development Commands
- Always use the `justfile` tasks:
  - `just open` — open the Xcode project.
  - `just test` — run scheme tests via Xcode.
  - `just xcode-build` — build the macOS app via Xcode.
  - `just spm-list` — list Swift package directories in the repo.
  - `just spm-build <pkgdir>` — build a Swift package at `<pkgdir>` (e.g., `CopilotCompanionApp`).
  - `just spm-test <pkgdir>` — run tests for a Swift package at `<pkgdir>`.
  - `just package-describe <pkgdir>` — print SwiftPM package info for `<pkgdir>`.
  - `just list-schemes` — list Xcode schemes.
  - `just clean` — clean Xcode and SwiftPM artifacts.

## Coding Style & Naming Conventions
- Language: Swift 6.2+, macOS 13+.
- Indentation: 4 spaces; lines concise; prefer explicit access control.
- Naming: `UpperCamelCase` for types, `lowerCamelCase` for functions/vars; file names match primary type.
- Concurrency: prefer async/await and actors (e.g., `FolderWatcher`).

## Testing Guidelines
- Framework: Swift Testing (`import Testing`) with `@Test` functions.
- Location: mirror source structure under `Tests/…`.
- Naming: descriptive backticked test names, e.g., ``func `FolderWatcher detects file deletion`()``.
- Run: `swift test` (package) or `just test` (Xcode scheme).

## Commit & Pull Request Guidelines
- Commits: short, imperative subject (≤72 chars), optional body for rationale.
  - Example: `Add async API to FolderWatcher start/stop`
- PRs: include summary, screenshots if UI changes, reproduction steps for bugfixes, and link issues.
- Keep changes focused; update docs when touching public API.

## Security & Configuration Tips
- The app watches `~/.copilot/session-state`; avoid committing real user data.
- Do not commit secrets or local paths. Use temporary dirs in tests.
