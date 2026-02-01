//
//  SessionManagerTests.swift
//  CopilotCompanionAppTests
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation
import Testing

@testable import CopilotCompanionApp

@Suite("SessionManager tests")
struct SessionManagerTests {
    // MARK: - Empty Directory Tests

    @Test
    func `returns empty array when directory does not exist`() async {
        let nonExistentDir = URL(fileURLWithPath: "/non/existent/session-state")
        let manager = SessionManager(sessionStateDirectory: nonExistentDir)

        let sessions = await manager.getActiveSessions()

        #expect(sessions.isEmpty)
    }

    @Test
    func `returns empty array for empty directory`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let manager = SessionManager(sessionStateDirectory: testDir)

        let sessions = await manager.getActiveSessions()

        #expect(sessions.isEmpty)
    }

    // MARK: - Folder Session Tests

    @Test
    func `discovers folder-based session`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create a folder session
        let sessionDir = testDir.appendingPathComponent("session-abc123")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let eventsContent = """
            {"type":"user.message"}
            {"type":"assistant.turn_start"}
            {"type":"assistant.message","data":{"content":"Done"}}
            {"type":"assistant.turn_end"}
            """
        try eventsContent.write(
            to: sessionDir.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let workspaceContent = """
            repository: test/repo
            summary: Test session
            """
        try workspaceContent.write(
            to: sessionDir.appendingPathComponent("workspace.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let manager = SessionManager(sessionStateDirectory: testDir)
        let sessions = await manager.getActiveSessions()

        #expect(sessions.count == 1)
        #expect(sessions[0].id == "session-abc123")
        #expect(sessions[0].type == .folder)
        #expect(sessions[0].eventCount == 4)
        #expect(sessions[0].state.status == .waitingForUser)
        #expect(sessions[0].workspace?.repository == "test/repo")
    }

    @Test
    func `ignores folder without events jsonl`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create a folder without events.jsonl
        let sessionDir = testDir.appendingPathComponent("incomplete-session")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        // Only create workspace.yaml
        try "repository: test".write(
            to: sessionDir.appendingPathComponent("workspace.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let manager = SessionManager(sessionStateDirectory: testDir)
        let sessions = await manager.getActiveSessions()

        #expect(sessions.isEmpty)
    }

    // MARK: - JSONL Session Tests

    @Test
    func `discovers JSONL file session`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let eventsContent = """
            {"type":"user.message"}
            {"type":"assistant.turn_start"}
            {"type":"assistant.turn_end"}
            """

        try eventsContent.write(
            to: testDir.appendingPathComponent("simple-session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let manager = SessionManager(sessionStateDirectory: testDir)
        let sessions = await manager.getActiveSessions()

        #expect(sessions.count == 1)
        #expect(sessions[0].id == "simple-session")
        #expect(sessions[0].type == .jsonl)
        #expect(sessions[0].eventCount == 3)
        #expect(sessions[0].workspace == nil)
    }

    // MARK: - Multiple Sessions Tests

    @Test
    func `discovers multiple sessions of different types`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create folder session
        let folderSession = testDir.appendingPathComponent("folder-session")
        try FileManager.default.createDirectory(at: folderSession, withIntermediateDirectories: true)
        try """
        {"type":"user.message"}
        """.write(
            to: folderSession.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        // Create JSONL session
        try """
        {"type":"user.message"}
        {"type":"assistant.turn_end"}
        """.write(
            to: testDir.appendingPathComponent("jsonl-session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let manager = SessionManager(sessionStateDirectory: testDir)
        let sessions = await manager.getActiveSessions()

        #expect(sessions.count == 2)
        #expect(sessions.contains { $0.type == .folder })
        #expect(sessions.contains { $0.type == .jsonl })
    }

    @Test
    func `sorts sessions by last modified descending`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create first session (older)
        let olderPath = testDir.appendingPathComponent("older.jsonl")
        try """
        {"type":"user.message"}
        """.write(to: olderPath, atomically: true, encoding: .utf8)

        // Create second session (newer)
        let newerPath = testDir.appendingPathComponent("newer.jsonl")
        try """
        {"type":"user.message"}
        """.write(to: newerPath, atomically: true, encoding: .utf8)

        let manager = SessionManager(sessionStateDirectory: testDir)
        let sessions = await manager.getActiveSessions()

        #expect(sessions.count == 2)
        #expect(sessions[0].id == "newer")
        #expect(sessions[1].id == "older")
    }

    // MARK: - Filtering Tests

    @Test
    func `getSessionsWaitingForUser filters correctly`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Session waiting for user
        let waitingSession = testDir.appendingPathComponent("waiting")
        try FileManager.default.createDirectory(at: waitingSession, withIntermediateDirectories: true)
        try """
        {"type":"user.message"}
        {"type":"assistant.turn_start"}
        {"type":"assistant.message","data":{"content":"Done"}}
        {"type":"assistant.turn_end"}
        """.write(
            to: waitingSession.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        // Session processing
        let processingSession = testDir.appendingPathComponent("processing")
        try FileManager.default.createDirectory(at: processingSession, withIntermediateDirectories: true)
        try """
        {"type":"user.message"}
        {"type":"assistant.turn_start"}
        """.write(
            to: processingSession.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let manager = SessionManager(sessionStateDirectory: testDir)
        let waitingSessions = await manager.getSessionsWaitingForUser()

        #expect(waitingSessions.count == 1)
        #expect(waitingSessions[0].id == "waiting")
    }

    @Test
    func `hasSessionWaitingForUser returns true when waiting`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let sessionDir = testDir.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"type":"assistant.turn_start"}
        {"type":"assistant.message","data":{"content":"Done"}}
        {"type":"assistant.turn_end"}
        """.write(
            to: sessionDir.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let manager = SessionManager(sessionStateDirectory: testDir)
        let hasWaiting = await manager.hasSessionWaitingForUser()

        #expect(hasWaiting)
    }

    @Test
    func `hasSessionWaitingForUser returns false when not waiting`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let sessionDir = testDir.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"type":"user.message"}
        {"type":"assistant.turn_start"}
        """.write(
            to: sessionDir.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let manager = SessionManager(sessionStateDirectory: testDir)
        let hasWaiting = await manager.hasSessionWaitingForUser()

        #expect(!hasWaiting)
    }

    // MARK: - Edge Cases

    @Test
    func `ignores hidden files and directories`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create hidden folder session
        let hiddenFolder = testDir.appendingPathComponent(".hidden-session")
        try FileManager.default.createDirectory(at: hiddenFolder, withIntermediateDirectories: true)
        try """
        {"type":"user.message"}
        """.write(
            to: hiddenFolder.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        // Create hidden JSONL file
        try """
        {"type":"user.message"}
        """.write(
            to: testDir.appendingPathComponent(".hidden.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let manager = SessionManager(sessionStateDirectory: testDir)
        let sessions = await manager.getActiveSessions()

        #expect(sessions.isEmpty)
    }

    @Test
    func `handles malformed events jsonl gracefully`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let sessionDir = testDir.appendingPathComponent("malformed")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        // Create file with some valid and some invalid JSON
        try """
        {"type":"user.message"}
        not valid json
        {"type":"assistant.turn_end"}
        """.write(
            to: sessionDir.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let manager = SessionManager(sessionStateDirectory: testDir)
        let sessions = await manager.getActiveSessions()

        #expect(sessions.count == 1)
        #expect(sessions[0].eventCount == 2)  // Only 2 valid events
    }

    // MARK: - CopilotSession Tests

    @Test
    func `CopilotSession shortId truncates long ids`() {
        let session = CopilotSession(
            id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890-extra-long-suffix",
            type: .folder,
            path: URL(fileURLWithPath: "/test"),
            eventCount: 0,
            state: SessionState(status: .empty, reason: ""),
            lastModified: Date()
        )

        #expect(session.shortId.hasSuffix("..."))
        #expect(session.shortId.count == 39)  // 36 + "..."
    }

    @Test
    func `CopilotSession shortId returns full id when short`() {
        let session = CopilotSession(
            id: "short-id",
            type: .folder,
            path: URL(fileURLWithPath: "/test"),
            eventCount: 0,
            state: SessionState(status: .empty, reason: ""),
            lastModified: Date()
        )

        #expect(session.shortId == "short-id")
    }

}
