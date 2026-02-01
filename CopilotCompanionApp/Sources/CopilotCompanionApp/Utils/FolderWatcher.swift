//
//  FolderWatcher.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 1/31/26.
//

import Foundation

/// A utility for watching changes in a folder and its subfolders/files
actor FolderWatcher {
    private let folderURL: URL
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32?
    private var changeHandler: (@Sendable (FolderWatcherChange) async -> Void)?
    private var isWatching = false
    private var accumulatedChanges: [FolderWatcherChange] = []
    private var initialSnapshot: [String: FileAttributes] = [:]
    private var pollingTask: Task<Void, Never>?

    init(folderURL: URL) {
        self.folderURL = folderURL
    }

    deinit {
        Task { [weak self] in await self?.stopWatching() }
    }

    func startWatching(onChange: @escaping @Sendable (FolderWatcherChange) async -> Void) throws {
        guard !isWatching else {
            assertionFailure("Do not call startWatching after starting, stop the previous session first")
            return
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { throw FolderWatcherError.folderDoesNotExist }

        initialSnapshot = try captureSnapshot()

        let fd = open(folderURL.path, O_EVTONLY)
        guard fd >= 0 else { throw FolderWatcherError.cannotOpenFolder }

        self.fileDescriptor = fd
        self.changeHandler = onChange

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.global(qos: .background)
        )
        source.setEventHandler { [weak self] in
            Task { [weak self] in await self?.handleFileSystemEvent() }
        }

        source.setCancelHandler { [fd] in close(fd) }

        source.resume()
        self.dispatchSource = source
        self.isWatching = true

        // Start polling task to detect file modifications
        startPolling()
    }

    func stopWatching() {
        guard isWatching else { return }

        pollingTask?.cancel()
        pollingTask = nil

        dispatchSource?.cancel()
        dispatchSource = nil

        if let fd = fileDescriptor {
            close(fd)
            fileDescriptor = nil
        }

        isWatching = false
        changeHandler = nil
        initialSnapshot.removeAll()
        accumulatedChanges.removeAll()
    }

    func checkForChanges() throws -> [FolderWatcherChange] {
        let accumulated = accumulatedChanges
        accumulatedChanges.removeAll()

        let currentSnapshot = try captureSnapshot()
        let newChanges = detectChanges(from: initialSnapshot, to: currentSnapshot)
        initialSnapshot = currentSnapshot

        var allChanges = accumulated + newChanges
        var seenPaths = Set<String>()
        allChanges = allChanges.filter { change in
            let path = change.path.path
            if seenPaths.contains(path) {
                return false
            }
            seenPaths.insert(path)
            return true
        }

        return allChanges
    }

    private func handleFileSystemEvent() async {
        guard let currentSnapshot = try? captureSnapshot() else { return }

        let changes = detectChanges(from: initialSnapshot, to: currentSnapshot)
        accumulatedChanges.append(contentsOf: changes)
        for change in changes {
            await changeHandler?(change)
        }
    }

    private func startPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.pollForChanges()
            }
        }
    }

    private func pollForChanges() async {
        guard isWatching else { return }
        guard let currentSnapshot = try? captureSnapshot() else { return }

        let changes = detectChanges(from: initialSnapshot, to: currentSnapshot)
        guard !changes.isEmpty else { return }

        initialSnapshot = currentSnapshot
        accumulatedChanges.append(contentsOf: changes)

        for change in changes {
            await changeHandler?(change)
        }
    }

    private func captureSnapshot() throws -> [String: FileAttributes] {
        var snapshot: [String: FileAttributes] = [:]
        let fileManager = FileManager.default
        let resolvedFolderURL = folderURL.resolvingSymlinksInPath()

        // Get all items recursively
        let enumerator = fileManager.enumerator(
            at: resolvedFolderURL,
            includingPropertiesForKeys: [
                .isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
            ],
            options: []  // Don't skip hidden files, we'll filter them ourselves if needed
        )
        guard let enumerator else { throw FolderWatcherError.cannotEnumerateFolder }

        for case let fileURL as URL in enumerator {
            let resolvedFileURL = fileURL.resolvingSymlinksInPath()
            let relativePath = resolvedFileURL.path.replacingOccurrences(of: resolvedFolderURL.path + "/", with: "")

            // Skip if the relative path is empty (shouldn't happen but be safe)
            guard !relativePath.isEmpty else { continue }

            let resourceValues = try resolvedFileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .contentModificationDateKey,
                .fileSizeKey,
            ])

            let attributes = FileAttributes(
                modificationDate: resourceValues.contentModificationDate,
                size: resourceValues.fileSize.map { Int64($0) },
                isDirectory: resourceValues.isDirectory ?? false
            )

            snapshot[relativePath] = attributes
        }

        return snapshot
    }

    private func detectChanges(
        from oldSnapshot: [String: FileAttributes],
        to newSnapshot: [String: FileAttributes]
    ) -> [FolderWatcherChange] {
        var changes: [FolderWatcherChange] = []
        let resolvedFolderURL = folderURL.resolvingSymlinksInPath()

        // Detect new and modified files
        for (path, newAttrs) in newSnapshot {
            if let oldAttrs = oldSnapshot[path] {
                // File existed before, check if modified
                if newAttrs.modificationDate != oldAttrs.modificationDate || newAttrs.size != oldAttrs.size {
                    let fullURL = resolvedFolderURL.appending(path: path)
                    changes.append(FolderWatcherChange(path: fullURL, type: .modified))
                }
            } else {
                // New file
                let fullURL = resolvedFolderURL.appending(path: path)
                changes.append(FolderWatcherChange(path: fullURL, type: .created))
            }
        }

        // Detect deleted files
        for (path, _) in oldSnapshot {
            if newSnapshot[path] == nil {
                let fullURL = resolvedFolderURL.appending(path: path)
                changes.append(FolderWatcherChange(path: fullURL, type: .deleted))
            }
        }

        return changes
    }

    private struct FileAttributes: Sendable {
        let modificationDate: Date?
        let size: Int64?
        let isDirectory: Bool
    }
}

enum FolderWatcherChangeType: Sendable {
    case created
    case modified
    case deleted
    case renamed
}

struct FolderWatcherChange: Sendable {
    let path: URL
    let type: FolderWatcherChangeType
    let timestamp: Date

    fileprivate init(path: URL, type: FolderWatcherChangeType, timestamp: Date = Date()) {
        self.path = path
        self.type = type
        self.timestamp = timestamp
    }
}

enum FolderWatcherError: Error, LocalizedError {
    case folderDoesNotExist
    case cannotOpenFolder
    case cannotEnumerateFolder

    public var errorDescription: String? {
        switch self {
        case .folderDoesNotExist:
            return "The folder does not exist or is not a directory"
        case .cannotOpenFolder:
            return "Cannot open the folder for watching"
        case .cannotEnumerateFolder:
            return "Cannot enumerate the folder contents"
        }
    }
}
