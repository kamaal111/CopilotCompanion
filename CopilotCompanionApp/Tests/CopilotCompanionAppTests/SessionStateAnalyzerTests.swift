//
//  SessionStateAnalyzerTests.swift
//  CopilotCompanionAppTests
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation
import Testing

@testable import CopilotCompanionApp

@Suite("SessionStateAnalyzer tests")
struct SessionStateAnalyzerTests {
    // MARK: - Empty State Tests

    @Test
    func `returns empty status for no events`() {
        let events: [CopilotEvent] = []

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .empty)
        #expect(state.reason == "No events")
    }

    // MARK: - Processing State Tests

    @Test
    func `returns processing when turn started but not ended`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(
                type: .assistantTurnStart,
                data: CopilotEventData(turnId: "turn-123")
            ),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .processing)
        #expect(state.reason == "Agent is actively working")
        #expect(state.turnId == "turn-123")
    }

    @Test
    func `returns processing when new turn started after previous ended`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(type: .assistantMessage, data: CopilotEventData(content: "Done")),
            CopilotEvent(type: .assistantTurnEnd),
            CopilotEvent(type: .userMessage),
            CopilotEvent(
                type: .assistantTurnStart,
                data: CopilotEventData(turnId: "turn-456")
            ),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .processing)
        #expect(state.turnId == "turn-456")
    }

    // MARK: - Waiting For User State Tests

    @Test
    func `returns waitingForUser when turn ended without tool requests`() {
        let now = Date()
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(
                type: .assistantMessage,
                data: CopilotEventData(content: "I've completed the task.")
            ),
            CopilotEvent(type: .assistantTurnEnd, timestamp: now),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .waitingForUser)
        #expect(state.reason == "Agent completed turn, awaiting user response")
        #expect(state.lastMessage == "I've completed the task.")
        #expect(state.timestamp == now)
    }

    @Test
    func `returns waitingForUser when no user message exists`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(type: .assistantMessage, data: CopilotEventData(content: "Hello!")),
            CopilotEvent(type: .assistantTurnEnd),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .waitingForUser)
    }

    @Test
    func `truncates long messages in waitingForUser state`() {
        let longMessage = String(repeating: "x", count: 300)
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(type: .assistantMessage, data: CopilotEventData(content: longMessage)),
            CopilotEvent(type: .assistantTurnEnd),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .waitingForUser)
        #expect(state.lastMessage?.count == 200)
    }

    // MARK: - Ready State Tests

    @Test
    func `returns ready when turn ended with tool requests`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(
                type: .assistantMessage,
                data: CopilotEventData(
                    content: "Running tool...",
                    toolRequests: [CopilotToolRequest(id: "req-1", name: "read_file")]
                )
            ),
            CopilotEvent(type: .assistantTurnEnd),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .ready)
        #expect(state.reason == "Turn ended, agent ready for more input")
    }

    // MARK: - User Waiting State Tests

    @Test
    func `returns userWaiting when user message is after turn end`() {
        let userMessageTime = Date()
        let events: [CopilotEvent] = [
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(type: .assistantMessage, data: CopilotEventData(content: "Done")),
            CopilotEvent(type: .assistantTurnEnd),
            CopilotEvent(type: .userMessage, timestamp: userMessageTime),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .userWaiting)
        #expect(state.reason == "User sent message, waiting for agent")
        #expect(state.timestamp == userMessageTime)
    }

    @Test
    func `returns userWaiting for initial user message with no assistant response`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage)
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .userWaiting)
    }

    // MARK: - Unknown State Tests

    @Test
    func `handles edge case with only turn end`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .assistantTurnEnd)
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        // Turn ended but no message found before it - goes to ready state
        #expect(state.status == .ready)
    }

    // MARK: - Complex Scenarios

    @Test
    func `detects tool waiting for approval`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(
                type: .assistantMessage,
                data: CopilotEventData(
                    content: "Running command",
                    toolRequests: [CopilotToolRequest(id: "call_1", name: "bash")]
                )
            ),
            CopilotEvent(
                type: .toolExecutionStart,
                data: CopilotEventData(toolCallId: "call_1", toolName: "bash")
            ),
            // No tool.execution_complete - waiting for approval
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .waitingForApproval)
        #expect(state.reason.contains("bash"))
        #expect(state.reason.contains("approval"))
    }

    @Test
    func `does not detect approval when tool completes`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(
                type: .toolExecutionStart,
                data: CopilotEventData(toolCallId: "call_1", toolName: "bash")
            ),
            CopilotEvent(
                type: .toolExecutionComplete,
                data: CopilotEventData(toolCallId: "call_1")
            ),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status != .waitingForApproval)
        #expect(state.status == .processing)  // Turn still in progress
    }

    @Test
    func `handles multiple tools with one pending approval`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(
                type: .toolExecutionStart,
                data: CopilotEventData(toolCallId: "call_1", toolName: "report_intent")
            ),
            CopilotEvent(
                type: .toolExecutionComplete,
                data: CopilotEventData(toolCallId: "call_1")
            ),
            CopilotEvent(
                type: .toolExecutionStart,
                data: CopilotEventData(toolCallId: "call_2", toolName: "bash")
            ),
            // bash tool not completed - waiting for approval
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .waitingForApproval)
        #expect(state.reason.contains("bash"))
    }

    @Test
    func `does not show approval after abort`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(
                type: .toolExecutionStart,
                data: CopilotEventData(toolCallId: "call_1", toolName: "bash")
            ),
            CopilotEvent(type: .abort),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status != .waitingForApproval)
    }

    @Test
    func `handles full conversation flow`() {
        // Simulate: user asks -> agent responds -> user asks again -> agent is working
        var events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(type: .assistantMessage, data: CopilotEventData(content: "First response")),
            CopilotEvent(type: .assistantTurnEnd),
        ]

        var state = SessionStateAnalyzer.analyze(events: events)
        #expect(state.status == .waitingForUser)

        // User sends another message
        events.append(CopilotEvent(type: .userMessage))
        state = SessionStateAnalyzer.analyze(events: events)
        #expect(state.status == .userWaiting)

        // Agent starts processing
        events.append(CopilotEvent(type: .assistantTurnStart))
        state = SessionStateAnalyzer.analyze(events: events)
        #expect(state.status == .processing)

        // Agent finishes
        events.append(CopilotEvent(type: .assistantMessage, data: CopilotEventData(content: "Done")))
        events.append(CopilotEvent(type: .assistantTurnEnd))
        state = SessionStateAnalyzer.analyze(events: events)
        #expect(state.status == .waitingForUser)
    }

    @Test
    func `handles multiple tool request cycles`() {
        let events: [CopilotEvent] = [
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            // First tool request
            CopilotEvent(
                type: .assistantMessage,
                data: CopilotEventData(
                    content: "Reading file...",
                    toolRequests: [CopilotToolRequest(id: "req-1")]
                )
            ),
            // Second message without tool requests (final response)
            CopilotEvent(
                type: .assistantMessage,
                data: CopilotEventData(content: "Here's what I found")
            ),
            CopilotEvent(type: .assistantTurnEnd),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        #expect(state.status == .waitingForUser)
        #expect(state.lastMessage == "Here's what I found")
    }

    // MARK: - Multiple Sessions Tests

    @Test
    func `ignores events from previous sessions when analyzing current state`() {
        // Simulates a file with multiple sessions where previous sessions had aborted tool calls
        // but the current session is waiting for user input
        let events: [CopilotEvent] = [
            // Previous session with aborted tool call
            CopilotEvent(type: .sessionStart),
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(
                type: .assistantMessage,
                data: CopilotEventData(toolRequests: [CopilotToolRequest(name: "bash")])
            ),
            CopilotEvent(
                type: .toolExecutionStart,
                data: CopilotEventData(toolCallId: "old-call", toolName: "bash")
            ),
            CopilotEvent(type: .abort),  // Previous session was aborted

            // New session - user asked a question and agent responded
            CopilotEvent(type: .sessionStart),
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(
                type: .assistantMessage,
                data: CopilotEventData(content: "Build succeeded")
            ),
            CopilotEvent(type: .assistantTurnEnd),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        // Should detect waitingForUser from the NEW session, not see the old aborted tool
        #expect(state.status == .waitingForUser)
        #expect(state.reason == "Agent completed turn, awaiting user response")
        #expect(state.lastMessage == "Build succeeded")
    }

    @Test
    func `only analyzes events from current session after session start`() {
        // Simulates multiple sessions in same file
        let events: [CopilotEvent] = [
            // Old session waiting for user
            CopilotEvent(type: .sessionStart),
            CopilotEvent(type: .userMessage),
            CopilotEvent(type: .assistantTurnStart),
            CopilotEvent(
                type: .assistantMessage,
                data: CopilotEventData(content: "Old session response")
            ),
            CopilotEvent(type: .assistantTurnEnd),

            // New session - agent is processing
            CopilotEvent(type: .sessionStart),
            CopilotEvent(type: .userMessage),
            CopilotEvent(
                type: .assistantTurnStart,
                data: CopilotEventData(turnId: "new-turn")
            ),
        ]

        let state = SessionStateAnalyzer.analyze(events: events)

        // Should detect processing state from NEW session only
        #expect(state.status == .processing)
        #expect(state.turnId == "new-turn")
    }
}
