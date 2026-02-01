//
//  SessionWatcherRealScenarioTests.swift
//  CopilotCompanionAppTests
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation
import Testing

@testable import CopilotCompanionApp

@Suite("SessionWatcher Real Scenario tests")
struct SessionWatcherRealScenarioTests {
    @Test
    func `detects bash tool waiting for approval in real time`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create session directory
        let sessionDir = testDir.appendingPathComponent("session-4460c31c")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let eventsPath = sessionDir.appendingPathComponent("events.jsonl")

        // Write initial events (before watching)
        let initialEvents = """
            {"type":"session.start","data":{"sessionId":"4460c31c-763e-496b-8eaa-c7a41959e581"}}
            {"type":"user.message","data":{"content":"Run just xcode-build"}}
            {"type":"assistant.turn_start","data":{"turnId":"0"}}
            """

        try initialEvents.write(to: eventsPath, atomically: true, encoding: .utf8)

        // Ensure file is written
        try await waitUntil {
            FileManager.default.fileExists(atPath: eventsPath.path)
        }

        // Now start watching
        let manager = SessionManager(sessionStateDirectory: testDir)
        let folderWatcher = FolderWatcher(folderURL: testDir)
        let watcher = SessionWatcher(sessionManager: manager, folderWatcher: folderWatcher)

        let callbackTracker = SessionCallbackTracker()

        try await watcher.startWatching { sessions in
            await callbackTracker.record(sessions: sessions)
        }

        // Initial check - should be empty since session existed before watching
        let initialSessions = await watcher.getWaitingSessions()
        #expect(initialSessions.isEmpty)

        // Now append the tool execution events (simulating agent requesting approval)
        let newEvents = """
            {"type":"assistant.message","data":{"content":"","toolRequests":[{"toolCallId":"call_1","name":"bash"}]}}
            {"type":"tool.execution_start","data":{"toolCallId":"call_1","toolName":"bash"}}
            """

        // APPEND to existing file (this is what happens in real scenario)
        if let fileHandle = try? FileHandle(forWritingTo: eventsPath) {
            try fileHandle.seekToEnd()
            if let data = ("\n" + newEvents).data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
            }
            try fileHandle.close()
        }

        // Wait for callback to detect the approval state
        try await waitUntil {
            let invocations = await callbackTracker.getInvocations()
            return !invocations.isEmpty && invocations.last?.first?.state.status == .waitingForApproval
        }

        let updatedSessions = await watcher.getWaitingSessions()
        let invocations = await callbackTracker.getInvocations()

        await watcher.stopWatching()

        #expect(updatedSessions.count == 1)
        #expect(updatedSessions[0].state.status == .waitingForApproval)
        #expect(invocations.count > 0)
        let lastInvocation = invocations.last
        #expect(lastInvocation?.count == 1)
        #expect(lastInvocation?.first?.state.status == .waitingForApproval)
    }

    @Test
    func `file modification time updates when appending to events jsonl`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let sessionDir = testDir.appendingPathComponent("session-test")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let eventsPath = sessionDir.appendingPathComponent("events.jsonl")

        // Write initial content
        try "initial".write(to: eventsPath, atomically: true, encoding: .utf8)

        let initialModTime =
            try FileManager.default.attributesOfItem(atPath: eventsPath.path)[
                .modificationDate] as? Date

        // Append to file
        if let fileHandle = try? FileHandle(forWritingTo: eventsPath) {
            try fileHandle.seekToEnd()
            if let data = "\nappended".data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
            }
            try fileHandle.close()
        }

        let finalModTime =
            try FileManager.default.attributesOfItem(atPath: eventsPath.path)[
                .modificationDate] as? Date

        #expect(finalModTime != nil)
        #expect(initialModTime != nil)
        #expect(finalModTime! > initialModTime!)
    }

    @Test
    func `folder watcher detects file content changes`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let sessionDir = testDir.appendingPathComponent("session-watch")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let eventsPath = sessionDir.appendingPathComponent("events.jsonl")
        try "initial".write(to: eventsPath, atomically: true, encoding: .utf8)

        let folderWatcher = FolderWatcher(folderURL: testDir)
        let changeTracker = FolderChangeTracker()

        try await folderWatcher.startWatching { change in
            await changeTracker.record(change: change)
        }

        // Append to file
        if let fileHandle = try? FileHandle(forWritingTo: eventsPath) {
            try fileHandle.seekToEnd()
            if let data = "\nappended".data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
            }
            try fileHandle.close()
        }

        // Wait for change to be detected
        try await waitUntil {
            let changes = await changeTracker.getChanges()
            return changes.contains { $0.path.lastPathComponent == "events.jsonl" }
        }

        let changes = await changeTracker.getChanges()

        await folderWatcher.stopWatching()

        #expect(changes.count > 0)
        #expect(changes.contains { $0.path.lastPathComponent == "events.jsonl" })
    }

}
