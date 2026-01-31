# FolderWatcher

A Swift utility for monitoring file system changes in a folder and its subdirectories.

## Features

- 🔍 **Real-time Monitoring**: Automatically detects file and folder changes
- 📁 **Recursive Watching**: Monitors all subdirectories and nested files  
- 🎯 **Change Types**: Detects creation, modification, deletion, and rename events
- ⚡ **Async/Await**: Built with modern Swift concurrency
- 🧪 **Well Tested**: Comprehensive test suite using Swift Testing
- 🔄 **Background Processing**: Uses DispatchSource for efficient file system monitoring

## Usage

### Basic Example

```swift
import CopilotCompanionApp

// Create a watcher for a specific folder
let folderURL = URL(fileURLWithPath: "/path/to/watch")
let watcher = FolderWatcher(folderURL: folderURL)

// Start watching with a callback
try await watcher.startWatching { change in
    print("Change detected:")
    print("  Type: \(change.type)")
    print("  Path: \(change.path)")
    print("  Time: \(change.timestamp)")
}

// Later, stop watching
await watcher.stopWatching()
```

### Manual Change Checking

For testing or manual polling:

```swift
let watcher = FolderWatcher(folderURL: folderURL)
try await watcher.startWatching { _ in }

// ... perform file operations ...

// Manually check for changes
let changes = try await watcher.checkForChanges()
for change in changes {
    print("\(change.type): \(change.path.lastPathComponent)")
}
```

### Change Types

```swift
public enum ChangeType: Sendable {
    case created   // New file or folder
    case modified  // Existing file modified
    case deleted   // File or folder removed
    case renamed   // File or folder renamed
}
```

### Change Object

```swift
public struct Change: Sendable {
    public let path: URL          // Full path to the changed item
    public let type: ChangeType   // Type of change
    public let timestamp: Date    // When the change was detected
}
```

## Error Handling

```swift
do {
    try await watcher.startWatching { change in
        // Handle change
    }
} catch FolderWatcherError.folderDoesNotExist {
    print("The folder does not exist")
} catch FolderWatcherError.cannotOpenFolder {
    print("Cannot open the folder for watching")
} catch {
    print("Unexpected error: \(error)")
}
```

## Implementation Details

- Uses `DispatchSource.makeFileSystemObjectSource` for efficient file system monitoring
- Maintains snapshots of folder contents to detect changes
- Automatically handles symbolic links (e.g., `/var` → `/private/var` on macOS)
- Filters out temporary system files
- Thread-safe using Swift's actor isolation

## Testing

The FolderWatcher includes a comprehensive test suite that verifies:

- ✅ File creation detection
- ✅ File modification detection  
- ✅ File deletion detection
- ✅ Subdirectory changes
- ✅ Multiple simultaneous changes
- ✅ Callback triggering
- ✅ Start/stop/restart functionality
- ✅ Error handling for invalid folders
- ✅ Timestamp accuracy

Run tests with:

```bash
swift test
```

All tests use isolated temporary directories to ensure no side effects.

## Requirements

- macOS 13.0+
- Swift 6.2+

## License

Created by Kamaal M Farah on 1/31/26.
