//
//  FolderWatcherTests.swift
//  CopilotCompanionAppTests
//
//  Created by Kamaal M Farah on 1/31/26.
//

import Foundation
import Testing

@testable import CopilotCompanionApp

@Suite("FolderWatcher tests")
struct FolderWatcherTests {
    // MARK: - Tests

    @Test
    func `FolderWatcher detects multiple file creations`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let collector = ChangeCollector()
        let watcher = FolderWatcher(folderURL: testDir)

        try await watcher.startWatching { change in
            await collector.append(change)
        }

        // Create multiple files
        try createFile(at: testDir, named: "file1.txt")
        try createFile(at: testDir, named: "file2.txt")
        try createFile(at: testDir, named: "file3.txt")

        // Wait for all callbacks to be triggered
        var relevantChanges: [FolderWatcherChange] = []
        try await pollUntil {
            let changes = await collector.getChanges()
            relevantChanges = changes.filter { !$0.path.lastPathComponent.hasPrefix(".") }
            return relevantChanges.count >= 3
        }

        await watcher.stopWatching()

        #expect(relevantChanges.count == 3)
        #expect(relevantChanges.allSatisfy { $0.type == .created })
    }

    @Test
    func `FolderWatcher detects file modification`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create a file first
        try createFile(at: testDir, named: "test.txt", content: "Original content")

        let collector = ChangeCollector()
        let watcher = FolderWatcher(folderURL: testDir)

        try await watcher.startWatching { change in
            await collector.append(change)
        }

        // Modify the file
        try await modifyFile(
            at: testDir, named: "test.txt", newContent: "Modified content with different size")

        // Wait for callback to be triggered
        var relevantChanges: [FolderWatcherChange] = []
        try await pollUntil {
            let changes = await collector.getChanges()
            relevantChanges = changes.filter { !$0.path.lastPathComponent.hasPrefix(".") }
            return relevantChanges.count >= 1
        }

        await watcher.stopWatching()

        #expect(relevantChanges.count == 1)
        #expect(relevantChanges[0].type == .modified)
        #expect(relevantChanges[0].path.lastPathComponent == "test.txt")
    }

    @Test
    func `FolderWatcher detects file deletion`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create a file first
        try createFile(at: testDir, named: "test.txt")

        let collector = ChangeCollector()
        let watcher = FolderWatcher(folderURL: testDir)

        try await watcher.startWatching { change in
            await collector.append(change)
        }

        // Delete the file
        try deleteItem(at: testDir, named: "test.txt")

        // Wait for callback to be triggered
        var allChanges: [FolderWatcherChange] = []
        try await pollUntil {
            allChanges = await collector.getChanges()
            return allChanges.contains { $0.path.lastPathComponent == "test.txt" }
        }

        await watcher.stopWatching()

        #expect(allChanges.contains { $0.type == .deleted && $0.path.lastPathComponent == "test.txt" })
    }

    @Test
    func `FolderWatcher detects changes in subdirectories`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let watcher = FolderWatcher(folderURL: testDir)

        // Start watching with a no-op callback
        try await watcher.startWatching { _ in }

        // Create a subdirectory
        try createSubdirectory(at: testDir, named: "subdir")

        // Create a file in the subdirectory
        let subdirURL = testDir.appendingPathComponent("subdir")
        try createFile(at: subdirURL, named: "nested.txt")

        // Manual checking more reliable for nested operations
        try await Task.sleep(for: .milliseconds(100))
        let changes = try await watcher.checkForChanges()
        let relevantChanges = changes.filter { !$0.path.lastPathComponent.hasPrefix(".") }

        await watcher.stopWatching()

        #expect(relevantChanges.count >= 2)
        #expect(relevantChanges.contains { $0.type == .created && $0.path.lastPathComponent == "subdir" })
        #expect(relevantChanges.contains { $0.type == .created && $0.path.lastPathComponent == "nested.txt" })
    }

    @Test
    func `FolderWatcher detects file deletion in subdirectory`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Setup: create subdirectory with file
        try createSubdirectory(at: testDir, named: "subdir")
        let subdirURL = testDir.appendingPathComponent("subdir")
        try createFile(at: subdirURL, named: "nested.txt")

        let watcher = FolderWatcher(folderURL: testDir)
        try await watcher.startWatching { _ in }

        // Delete the file in subdirectory
        try deleteItem(at: subdirURL, named: "nested.txt")

        // For deletions in subdirectories, manual checking is more reliable
        // as file system events for nested deletions may not always propagate immediately
        try await Task.sleep(for: .milliseconds(100))
        let changes = try await watcher.checkForChanges()

        await watcher.stopWatching()

        // Filter out system files
        let relevantChanges = changes.filter { !$0.path.lastPathComponent.hasPrefix(".") }

        let deletions = relevantChanges.filter { $0.type == .deleted }
        #expect(deletions.contains { $0.path.lastPathComponent == "nested.txt" })
    }

    @Test
    func `FolderWatcher handles mixed operations`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Setup: create initial files
        try createFile(at: testDir, named: "existing.txt")
        try createFile(at: testDir, named: "to-delete.txt")
        try createFile(at: testDir, named: "to-modify.txt", content: "Original")

        let collector = ChangeCollector()
        let watcher = FolderWatcher(folderURL: testDir)

        try await watcher.startWatching { change in
            await collector.append(change)
        }

        // Perform all operations
        try createFile(at: testDir, named: "new.txt")
        try await modifyFile(
            at: testDir, named: "to-modify.txt", newContent: "Modified content that is different")
        try deleteItem(at: testDir, named: "to-delete.txt")

        // Wait for all callbacks to be triggered
        var relevantChanges: [FolderWatcherChange] = []
        try await pollUntil {
            let changes = await collector.getChanges()
            relevantChanges = changes.filter { !$0.path.lastPathComponent.hasPrefix(".") }
            return relevantChanges.contains { $0.path.lastPathComponent == "new.txt" }
                && relevantChanges.contains { $0.path.lastPathComponent == "to-modify.txt" }
                && relevantChanges.contains { $0.path.lastPathComponent == "to-delete.txt" }
        }

        await watcher.stopWatching()

        #expect(relevantChanges.count == 3)
        #expect(relevantChanges.contains { $0.type == .created && $0.path.lastPathComponent == "new.txt" })
        #expect(relevantChanges.contains { $0.type == .deleted && $0.path.lastPathComponent == "to-delete.txt" })
        #expect(relevantChanges.contains { $0.type == .modified && $0.path.lastPathComponent == "to-modify.txt" })
    }

    @Test
    func `FolderWatcher throws error for non-existent folder`() async throws {
        let nonExistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("non-existent-\(UUID().uuidString)")

        let watcher = FolderWatcher(folderURL: nonExistentURL)

        await #expect(throws: FolderWatcherError.self) {
            try await watcher.startWatching { _ in }
        }
    }

    @Test
    func `FolderWatcher can be stopped and restarted`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let watcher = FolderWatcher(folderURL: testDir)

        // First watch session
        let collector1 = ChangeCollector()
        try await watcher.startWatching { change in
            await collector1.append(change)
        }

        try createFile(at: testDir, named: "file1.txt")

        var relevantChanges1: [FolderWatcherChange] = []
        try await pollUntil {
            let changes = await collector1.getChanges()
            relevantChanges1 = changes.filter { !$0.path.lastPathComponent.hasPrefix(".") }
            return relevantChanges1.count >= 1
        }
        #expect(relevantChanges1.count == 1)
        await watcher.stopWatching()

        // Second watch session
        let collector2 = ChangeCollector()
        try await watcher.startWatching { change in
            await collector2.append(change)
        }

        try createFile(at: testDir, named: "file2.txt")

        var relevantChanges2: [FolderWatcherChange] = []
        try await pollUntil {
            let changes = await collector2.getChanges()
            relevantChanges2 = changes.filter { !$0.path.lastPathComponent.hasPrefix(".") }
            return relevantChanges2.count >= 1
        }
        await watcher.stopWatching()

        #expect(relevantChanges2.count == 1)
        #expect(relevantChanges2[0].path.lastPathComponent == "file2.txt")
    }

}

// MARK: - Test Setup Helpers

private actor ChangeCollector {
    private var changesByPath: [URL: FolderWatcherChange] = [:]

    func append(_ change: FolderWatcherChange) {
        changesByPath[change.path] = change
    }

    func getChanges() -> [FolderWatcherChange] {
        return Array(changesByPath.values)
    }
}

private func pollUntil(
    timeout: Duration = .seconds(3),
    interval: Duration = .milliseconds(20),
    condition: () async throws -> Bool
) async throws {
    let startTime = ContinuousClock.now
    while true {
        if try await condition() {
            return
        }

        let elapsed = ContinuousClock.now - startTime
        guard elapsed <= timeout else { throw PollingError.timeout }

        try await Task.sleep(for: interval)
    }
}

private enum PollingError: Error {
    case timeout
}

private func createTestDirectory(named name: String = "TestFolder") throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let testDir = tempDir.appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
    try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

    return testDir
}

private func cleanupTestDirectory(_ url: URL) throws {
    let parentDir = url.deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: parentDir.path) {
        try FileManager.default.removeItem(at: parentDir)
    }
}

private func createFile(at directory: URL, named name: String, content: String = "test content") throws {
    let fileURL = directory.appendingPathComponent(name)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
}

private func createSubdirectory(at directory: URL, named name: String) throws {
    let subdirURL = directory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: subdirURL, withIntermediateDirectories: true)
}

private func modifyFile(at directory: URL, named name: String, newContent: String) async throws {
    let fileURL = directory.appendingPathComponent(name)
    try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
}

private func deleteItem(at directory: URL, named name: String) throws {
    let itemURL = directory.appendingPathComponent(name)
    try FileManager.default.removeItem(at: itemURL)
}
