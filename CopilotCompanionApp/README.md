# CopilotCompanionApp (Swift Package)

Utilities for monitoring GitHub Copilot local session state on macOS. Includes file system watching, JSONL parsing, and analysis helpers used by the Copilot Companion app.

## Features

- FolderWatcher: Actor that detects created/modified/deleted items recursively.
- SessionWatcher: Debounced watcher for new sessions requiring attention.
- SessionManager: Discovers active sessions in `~/.copilot/session-state`.
- JSONLParser: Parses `events.jsonl` lines into strongly typed events.
- SessionStateAnalyzer: Derives session status (e.g., waiting for user/approval).
- WorkspaceInfoParser: Reads workspace metadata from `workspace.yaml`.

## Requirements

- macOS 13+
- Swift 6.2+

## Install

Add this package to an Xcode project or include it in a SwiftPM workspace. This repository also contains a macOS host app that imports this library.

## Usage

### Watch filesystem changes

```swift
import CopilotCompanionApp

let folderURL = URL(fileURLWithPath: "/path/to/watch")
let watcher = FolderWatcher(folderURL: folderURL)

try await watcher.startWatching { change in
    print("[\(change.timestamp)] \(change.type) => \(change.path.path)")
}

// ... later
await watcher.stopWatching()
```

Key types:
- `FolderWatcherChangeType`: `.created`, `.modified`, `.deleted`, `.renamed`
- `FolderWatcherChange`: `{ path: URL, type: FolderWatcherChangeType, timestamp: Date }`

You can also poll manually:

```swift
try await watcher.startWatching { _ in }
let changes = try await watcher.checkForChanges()
```

### Monitor Copilot sessions

```swift
import CopilotCompanionApp

let sessionManager = SessionManager() // defaults to ~/.copilot/session-state
let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".copilot/session-state")
let folderWatcher = FolderWatcher(folderURL: sessionsDir)
let sessionWatcher = SessionWatcher(sessionManager: sessionManager, folderWatcher: folderWatcher)

try await sessionWatcher.startWatching { sessions in
    // New or updated sessions that need user attention since watch start
    for s in sessions {
        print("\(s.projectName) [\(s.shortId)]: \(s.state.status.displayName) \(s.state.reason)")
    }
}

// ... later
await sessionWatcher.stopWatching()
```

Session status values include: `.waitingForUser`, `.waitingForApproval`, `.processing`, `.userWaiting`, `.ready`, `.empty`, `.unknown`.

## Errors

`FolderWatcher` throws:
- `.folderDoesNotExist`: Path missing or not a directory
- `.cannotOpenFolder`: Failed to open directory for events
- `.cannotEnumerateFolder`: Failed to list contents

## Development

From the repo root, use `just` tasks:

```bash
# Run SwiftPM tests for this package
just spm-test CopilotCompanionApp

# Open Xcode project (includes macOS app wrapper)
just open
```

Tests use Swift Testing (`import Testing`) and temporary directories; no real user data is read.

## Security Notes

- The app/library reads from `~/.copilot/session-state`. Do not commit real user data.
- Avoid embedding absolute local paths in code or tests.
