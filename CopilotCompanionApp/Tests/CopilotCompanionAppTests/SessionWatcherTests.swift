//
//  SessionWatcherTests.swift
//  CopilotCompanionAppTests
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation
import Testing

@testable import CopilotCompanionApp

@Suite("SessionWatcher tests")
struct SessionWatcherTests {
    // MARK: - Basic Functionality Tests

    @Test
    func `starts and stops watching`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let manager = SessionManager(sessionStateDirectory: testDir)
        let folderWatcher = FolderWatcher(folderURL: testDir)
        let watcher = SessionWatcher(sessionManager: manager, folderWatcher: folderWatcher)

        let isWatchingBefore = await watcher.isWatching()
        #expect(!isWatchingBefore)

        try await watcher.startWatching { _ in }

        let isWatchingDuring = await watcher.isWatching()
        #expect(isWatchingDuring)

        await watcher.stopWatching()

        let isWatchingAfter = await watcher.isWatching()
        #expect(!isWatchingAfter)
    }

    @Test
    func `filters out old sessions before watch start`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create a session BEFORE watching starts
        let oldSession = testDir.appendingPathComponent("old-session")
        try FileManager.default.createDirectory(at: oldSession, withIntermediateDirectories: true)

        let eventsContent = """
            {"type":"user.message"}
            {"type":"assistant.turn_start"}
            {"type":"assistant.message","data":{"content":"Done"}}
            {"type":"assistant.turn_end"}
            """

        try eventsContent.write(
            to: oldSession.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        // Wait to ensure file is written
        try await waitUntil {
            FileManager.default.fileExists(atPath: oldSession.appendingPathComponent("events.jsonl").path)
        }

        // Now start watching
        let manager = SessionManager(sessionStateDirectory: testDir)
        let folderWatcher = FolderWatcher(folderURL: testDir)
        let watcher = SessionWatcher(sessionManager: manager, folderWatcher: folderWatcher)

        try await watcher.startWatching { _ in }

        // Get waiting sessions - should be empty because old session was created before watch started
        let sessions = await watcher.getWaitingSessions()

        await watcher.stopWatching()

        #expect(sessions.isEmpty)
    }

    @Test
    func `includes new sessions created after watch start`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let manager = SessionManager(sessionStateDirectory: testDir)
        let folderWatcher = FolderWatcher(folderURL: testDir)
        let watcher = SessionWatcher(sessionManager: manager, folderWatcher: folderWatcher)

        // Start watching first
        try await watcher.startWatching { _ in }

        // Create a session AFTER watching started
        let newSession = testDir.appendingPathComponent("new-session")
        try FileManager.default.createDirectory(at: newSession, withIntermediateDirectories: true)

        let eventsContent = """
            {"type":"user.message"}
            {"type":"assistant.turn_start"}
            {"type":"assistant.message","data":{"content":"Done"}}
            {"type":"assistant.turn_end"}
            """

        try eventsContent.write(
            to: newSession.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        // Wait for session to be detected
        try await waitUntil {
            let sessions = await watcher.getWaitingSessions()
            return sessions.count == 1
        }

        let sessions = await watcher.getWaitingSessions()

        await watcher.stopWatching()

        #expect(sessions.count == 1)
        #expect(sessions[0].id == "new-session")
    }

    @Test
    func `filters mixed old and new sessions`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create OLD session before watching
        let oldSession = testDir.appendingPathComponent("old-session")
        try FileManager.default.createDirectory(at: oldSession, withIntermediateDirectories: true)

        try """
        {"type":"assistant.turn_start"}
        {"type":"assistant.message","data":{"content":"Old"}}
        {"type":"assistant.turn_end"}
        """.write(
            to: oldSession.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        // Wait to ensure file is written
        try await waitUntil {
            FileManager.default.fileExists(atPath: oldSession.appendingPathComponent("events.jsonl").path)
        }

        // Start watching
        let manager = SessionManager(sessionStateDirectory: testDir)
        let folderWatcher = FolderWatcher(folderURL: testDir)
        let watcher = SessionWatcher(sessionManager: manager, folderWatcher: folderWatcher)

        try await watcher.startWatching { _ in }

        // Create NEW session after watching started
        let newSession = testDir.appendingPathComponent("new-session")
        try FileManager.default.createDirectory(at: newSession, withIntermediateDirectories: true)

        try """
        {"type":"assistant.turn_start"}
        {"type":"assistant.message","data":{"content":"New"}}
        {"type":"assistant.turn_end"}
        """.write(
            to: newSession.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        // Wait for session to be detected
        try await waitUntil {
            let sessions = await watcher.getWaitingSessions()
            return sessions.count == 1 && sessions[0].id == "new-session"
        }

        let sessions = await watcher.getWaitingSessions()

        await watcher.stopWatching()

        #expect(sessions.count == 1)
        #expect(sessions[0].id == "new-session")
    }

    // MARK: - Reactive Updates Tests

    @Test
    func `triggers callback when new session appears`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let manager = SessionManager(sessionStateDirectory: testDir)
        let folderWatcher = FolderWatcher(folderURL: testDir)
        let watcher = SessionWatcher(sessionManager: manager, folderWatcher: folderWatcher)

        // Track callback invocations
        let callbackInvoked = SessionCallbackTracker()

        try await watcher.startWatching { sessions in
            await callbackInvoked.record(sessions: sessions)
        }

        // Create a new session

        let newSession = testDir.appendingPathComponent("reactive-session")
        try FileManager.default.createDirectory(at: newSession, withIntermediateDirectories: true)

        try """
        {"type":"assistant.turn_start"}
        {"type":"assistant.message","data":{"content":"Test"}}
        {"type":"assistant.turn_end"}
        """.write(
            to: newSession.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        // Wait for callback to be invoked with sessions
        try await waitUntil {
            let invocations = await callbackInvoked.getInvocations()
            return !invocations.isEmpty && invocations.last?.isEmpty == false
        }

        let invocations = await callbackInvoked.getInvocations()

        await watcher.stopWatching()

        #expect(invocations.count > 0)
        #expect(invocations.last?.count == 1)
    }

    @Test
    func `does not trigger callback for old sessions`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create old session BEFORE watching
        let oldSession = testDir.appendingPathComponent("pre-existing")
        try FileManager.default.createDirectory(at: oldSession, withIntermediateDirectories: true)

        try """
        {"type":"assistant.turn_start"}
        {"type":"assistant.message","data":{"content":"Old"}}
        {"type":"assistant.turn_end"}
        """.write(
            to: oldSession.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        // Wait to ensure file is written
        try await waitUntil {
            FileManager.default.fileExists(atPath: oldSession.appendingPathComponent("events.jsonl").path)
        }

        // Now start watching
        let manager = SessionManager(sessionStateDirectory: testDir)
        let folderWatcher = FolderWatcher(folderURL: testDir)
        let watcher = SessionWatcher(sessionManager: manager, folderWatcher: folderWatcher)

        let callbackInvoked = SessionCallbackTracker()

        try await watcher.startWatching { sessions in
            await callbackInvoked.record(sessions: sessions)
        }

        // Wait to see if any callbacks fire (give it enough time for polling + debounce)
        try await Task.sleep(for: .milliseconds(1600))

        let invocations = await callbackInvoked.getInvocations()

        await watcher.stopWatching()

        // Should have no callbacks (or callbacks with empty arrays) since old session should be filtered
        if !invocations.isEmpty {
            #expect(invocations.allSatisfy { $0.isEmpty })
        }
    }

    @Test
    func `returns empty array when not watching`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let manager = SessionManager(sessionStateDirectory: testDir)
        let folderWatcher = FolderWatcher(folderURL: testDir)
        let watcher = SessionWatcher(sessionManager: manager, folderWatcher: folderWatcher)

        let sessions = await watcher.getWaitingSessions()

        #expect(sessions.isEmpty)
    }

    @Test
    func `clears state after stop watching`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let manager = SessionManager(sessionStateDirectory: testDir)
        let folderWatcher = FolderWatcher(folderURL: testDir)
        let watcher = SessionWatcher(sessionManager: manager, folderWatcher: folderWatcher)

        try await watcher.startWatching { _ in }
        await watcher.stopWatching()

        let sessions = await watcher.getWaitingSessions()

        #expect(sessions.isEmpty)
    }

}
