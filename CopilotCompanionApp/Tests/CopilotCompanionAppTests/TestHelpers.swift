//
//  TestHelpers.swift
//  CopilotCompanionAppTests
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation
import Testing

@testable import CopilotCompanionApp

// MARK: - Polling Helper

/// Polls a condition until it becomes true or times out
func waitUntil(
    timeout: Duration = .seconds(3),
    pollingInterval: Duration = .milliseconds(100),
    condition: @escaping () async -> Bool
) async throws {
    let startTime = Date()
    while Date().timeIntervalSince(startTime) < timeout.timeInterval {
        if await condition() {
            return
        }
        try await Task.sleep(for: pollingInterval)
    }
    throw TestTimeoutError()
}

struct TestTimeoutError: Error {}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = self.components
        return TimeInterval(seconds) + (TimeInterval(attoseconds) / 1_000_000_000_000_000_000)
    }
}

// MARK: - Tracker Actors

/// Tracks callback invocations for session watchers
actor SessionCallbackTracker {
    private var invocations: [[CopilotSession]] = []

    func record(sessions: [CopilotSession]) {
        invocations.append(sessions)
    }

    func getInvocations() -> [[CopilotSession]] {
        invocations
    }
}

/// Tracks folder watcher changes (deduplicates by path, keeping latest)
actor FolderChangeTracker {
    private var changesByPath: [URL: FolderWatcherChange] = [:]

    func record(change: FolderWatcherChange) {
        changesByPath[change.path] = change
    }

    func getChanges() -> [FolderWatcherChange] {
        Array(changesByPath.values)
    }
}

// MARK: - Test Directory Helpers

func createTestDirectory(prefix: String = "Test") throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let testDir = tempDir.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    return testDir
}

func cleanupTestDirectory(_ url: URL) throws {
    try FileManager.default.removeItem(at: url)
}

// MARK: - FolderWatcher Test Helpers

func createFile(at directory: URL, named name: String, content: String = "test content") throws {
    let fileURL = directory.appendingPathComponent(name)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
}

func createSubdirectory(at directory: URL, named name: String) throws {
    let subdirURL = directory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: subdirURL, withIntermediateDirectories: true)
}

func modifyFile(at directory: URL, named name: String, newContent: String) async throws {
    let fileURL = directory.appendingPathComponent(name)
    try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
}

func deleteItem(at directory: URL, named name: String) throws {
    let itemURL = directory.appendingPathComponent(name)
    try FileManager.default.removeItem(at: itemURL)
}
