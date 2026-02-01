//
//  RealWorldScenarioTests.swift
//  CopilotCompanionAppTests
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation
import Testing

@testable import CopilotCompanionApp

@Suite("Real World Scenario tests")
struct RealWorldScenarioTests {
    @Test
    func `detects bash command waiting for approval from real events`() {
        // This is the exact sequence from the user's report
        let jsonlContent = """
            {"type":"session.start","data":{"sessionId":"f4539556-b58f-4908-b6a1-67594d6cbd07","version":1,"producer":"copilot-agent","copilotVersion":"0.0.400","startTime":"2026-02-01T11:34:30.213Z","context":{"cwd":"/Users/kamaal/Projects/Swift/Apps/CopilotCompanion","gitRoot":"/Users/kamaal/Projects/Swift/Apps/CopilotCompanion","branch":"main","repository":"kamaal111/CopilotCompanion"}},"id":"aa1ccd9f-7867-4ae1-8fec-56dbdd345030","timestamp":"2026-02-01T11:34:30.294Z","parentId":null}
            {"type":"user.message","data":{"content":"Run `just build`","transformedContent":"<current_datetime>2026-02-01T11:34:49.333Z</current_datetime>\\n\\nRun `just build`","attachments":[]},"id":"372ce599-54cd-4455-8397-fb778e26ef7b","timestamp":"2026-02-01T11:34:49.333Z","parentId":"7a9e7e7b-9b65-45b6-aeb2-45ac4f6aafb3"}
            {"type":"assistant.turn_start","data":{"turnId":"0"},"id":"102e7223-9009-46d0-82c5-2d93777a29af","timestamp":"2026-02-01T11:34:49.554Z","parentId":"372ce599-54cd-4455-8397-fb778e26ef7b"}
            {"type":"assistant.message","data":{"messageId":"705910c1-35d2-4443-96cf-96f747cc97e5","content":"Running `just build` to build the project using the repo's justfile as requested.","toolRequests":[{"toolCallId":"call_jIszjbu2CpkBm2RBo2531pAC","name":"report_intent","arguments":{"intent":"Building project"},"type":"function"},{"toolCallId":"call_zmaYMibbs8tN9Uzcc04TwuEn","name":"bash","arguments":{"command":"just build","description":"Run just build","initial_wait":120},"type":"function"}],"reasoningOpaque":"test","reasoningText":"test"},"id":"787de1cf-4413-4a20-bba5-b2d4e242e353","timestamp":"2026-02-01T11:35:00.834Z","parentId":"a9a46840-3dfe-4dc7-93fb-be61a44d2014"}
            {"type":"tool.execution_start","data":{"toolCallId":"call_jIszjbu2CpkBm2RBo2531pAC","toolName":"report_intent","arguments":{"intent":"Building project"}},"id":"b1ebb39c-eedb-4226-8074-edf9f62860c2","timestamp":"2026-02-01T11:35:00.835Z","parentId":"5e5f5037-1bbb-4779-8697-5a583211ff56"}
            {"type":"tool.execution_start","data":{"toolCallId":"call_zmaYMibbs8tN9Uzcc04TwuEn","toolName":"bash","arguments":{"command":"just build","description":"Run just build","initial_wait":120}},"id":"16bfa58b-44d9-4132-9942-30f4ada75f97","timestamp":"2026-02-01T11:35:00.835Z","parentId":"b1ebb39c-eedb-4226-8074-edf9f62860c2"}
            {"type":"tool.execution_complete","data":{"toolCallId":"call_jIszjbu2CpkBm2RBo2531pAC","success":true,"result":{"content":"Intent logged","detailedContent":"Building project"},"toolTelemetry":{}},"id":"0ed21aa3-7bba-4ef9-b125-21941c471060","timestamp":"2026-02-01T11:35:00.849Z","parentId":"16bfa58b-44d9-4132-9942-30f4ada75f97"}
            """

        let events = JSONLParser.parse(content: jsonlContent)
        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .waitingForApproval)
        #expect(state.reason.contains("bash"))
        #expect(state.reason.contains("approval"))
    }

    @Test
    func `session manager detects sessions waiting for approval`() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create a session with tool waiting for approval
        let sessionDir = testDir.appendingPathComponent("approval-session")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let eventsContent = """
            {"type":"user.message","data":{"content":"Run command"}}
            {"type":"assistant.turn_start","data":{"turnId":"0"}}
            {"type":"assistant.message","data":{"content":"Running","toolRequests":[{"toolCallId":"call_1","name":"bash"}]}}
            {"type":"tool.execution_start","data":{"toolCallId":"call_1","toolName":"bash"}}
            """

        try eventsContent.write(
            to: sessionDir.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let workspaceContent = """
            repository: test/repo
            """
        try workspaceContent.write(
            to: sessionDir.appendingPathComponent("workspace.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let manager = SessionManager(sessionStateDirectory: testDir)
        let waitingSessions = await manager.getSessionsWaitingForUser()

        #expect(waitingSessions.count == 1)
        #expect(waitingSessions[0].state.status == .waitingForApproval)
    }

    @Test
    func `handles abort after tool execution start`() {
        let jsonlContent = """
            {"type":"user.message","data":{"content":"Run command"}}
            {"type":"assistant.turn_start","data":{"turnId":"0"}}
            {"type":"tool.execution_start","data":{"toolCallId":"call_1","toolName":"bash"}}
            {"type":"abort","data":{"reason":"user initiated"}}
            """

        let events = JSONLParser.parse(content: jsonlContent)
        let state = SessionStateAnalyzer.analyze(events: events)

        // After abort, should not be waiting for approval
        #expect(state.status != .waitingForApproval)
    }

}
