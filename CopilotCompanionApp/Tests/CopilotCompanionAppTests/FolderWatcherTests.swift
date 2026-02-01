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

        let collector = FolderChangeTracker()
        let watcher = FolderWatcher(folderURL: testDir)

        try await watcher.startWatching { change in
            await collector.record(change: change)
        }

        // Create multiple files
        try createFile(at: testDir, named: "file1.txt")
        try createFile(at: testDir, named: "file2.txt")
        try createFile(at: testDir, named: "file3.txt")

        // Wait for all callbacks to be triggered
        var relevantChanges: [FolderWatcherChange] = []
        try await waitUntil {
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

        let collector = FolderChangeTracker()
        let watcher = FolderWatcher(folderURL: testDir)

        try await watcher.startWatching { change in
            await collector.record(change: change)
        }

        // Modify the file
        try await modifyFile(
            at: testDir, named: "test.txt", newContent: "Modified content with different size")

        // Wait for callback to be triggered
        var relevantChanges: [FolderWatcherChange] = []
        try await waitUntil {
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

        let collector = FolderChangeTracker()
        let watcher = FolderWatcher(folderURL: testDir)

        try await watcher.startWatching { change in
            await collector.record(change: change)
        }

        // Delete the file
        try deleteItem(at: testDir, named: "test.txt")

        // Wait for callback to be triggered
        var allChanges: [FolderWatcherChange] = []
        try await waitUntil {
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

        // Check for changes
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

        // Check for changes
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

        let collector = FolderChangeTracker()
        let watcher = FolderWatcher(folderURL: testDir)

        try await watcher.startWatching { change in
            await collector.record(change: change)
        }

        // Perform all operations
        try createFile(at: testDir, named: "new.txt")
        try await modifyFile(
            at: testDir, named: "to-modify.txt", newContent: "Modified content that is different")
        try deleteItem(at: testDir, named: "to-delete.txt")

        // Wait for all callbacks to be triggered
        var relevantChanges: [FolderWatcherChange] = []
        try await waitUntil {
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
        let collector1 = FolderChangeTracker()
        try await watcher.startWatching { change in
            await collector1.record(change: change)
        }

        try createFile(at: testDir, named: "file1.txt")

        var relevantChanges1: [FolderWatcherChange] = []
        try await waitUntil {
            let changes = await collector1.getChanges()
            relevantChanges1 = changes.filter { !$0.path.lastPathComponent.hasPrefix(".") }
            return relevantChanges1.count >= 1
        }
        #expect(relevantChanges1.count == 1)
        await watcher.stopWatching()

        // Second watch session
        let collector2 = FolderChangeTracker()
        try await watcher.startWatching { change in
            await collector2.record(change: change)
        }

        try createFile(at: testDir, named: "file2.txt")

        var relevantChanges2: [FolderWatcherChange] = []
        try await waitUntil {
            let changes = await collector2.getChanges()
            relevantChanges2 = changes.filter { !$0.path.lastPathComponent.hasPrefix(".") }
            return relevantChanges2.count >= 1
        }
        await watcher.stopWatching()

        #expect(relevantChanges2.count == 1)
        #expect(relevantChanges2[0].path.lastPathComponent == "file2.txt")
    }

}
