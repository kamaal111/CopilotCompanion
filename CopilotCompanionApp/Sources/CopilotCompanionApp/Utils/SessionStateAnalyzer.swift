//
//  SessionStateAnalyzer.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation

/// Analyzes Copilot events to determine the current session state
enum SessionStateAnalyzer {
    /// Analyze an array of events to determine the session state
    ///
    /// The agent is considered "waiting for user response" when:
    /// 1. There's an active session with events
    /// 2. The last event is "assistant.turn_end"
    /// 3. No subsequent "user.message" event exists
    /// 4. The assistant's last message had no toolRequests (finished its work)
    ///
    /// - Parameter events: Array of CopilotEvent objects to analyze
    /// - Returns: The analyzed SessionState
    static func analyze(events: [CopilotEvent]) -> SessionState {
        guard !events.isEmpty else {
            return SessionState(status: .empty, reason: "No events")
        }

        // Filter events to only include those from the current session
        // (i.e., events after the last session.start event)
        let currentSessionEvents = filterToCurrentSession(events: events)

        guard !currentSessionEvents.isEmpty else {
            return SessionState(status: .empty, reason: "No events in current session")
        }

        let lastEvent = currentSessionEvents[currentSessionEvents.count - 1]
        let eventTypes = currentSessionEvents.map(\.type)

        // Find indices of key events
        let lastUserMessageIdx = eventTypes.lastIndex(of: .userMessage) ?? -1
        let lastTurnEndIdx = eventTypes.lastIndex(of: .assistantTurnEnd) ?? -1
        let lastTurnStartIdx = eventTypes.lastIndex(of: .assistantTurnStart) ?? -1

        // Check for tool waiting for approval (tool.execution_start without matching tool.execution_complete)
        let toolApprovalState = checkForToolAwaitingApproval(events: currentSessionEvents)
        if let approvalState = toolApprovalState {
            return approvalState
        }

        // Check if agent is currently processing (turn started but not ended)
        if lastTurnStartIdx > lastTurnEndIdx {
            let turnId = currentSessionEvents[lastTurnStartIdx].data?.turnId
            return SessionState(
                status: .processing,
                reason: "Agent is actively working",
                turnId: turnId
            )
        }

        // Check if waiting for user input
        if lastTurnEndIdx > lastUserMessageIdx || (lastTurnEndIdx >= 0 && lastUserMessageIdx == -1) {
            // Find the assistant message before turn_end
            var waitingForInput = false
            var lastAssistantMessage: CopilotEvent?

            // Walk backwards from turn_end to find the message
            for i in stride(from: lastTurnEndIdx - 1, through: 0, by: -1) {
                let event = currentSessionEvents[i]

                if event.type == .assistantMessage {
                    lastAssistantMessage = event
                    // If no tool requests, the agent finished and is waiting for user
                    let toolRequests = event.data?.toolRequests ?? []
                    if toolRequests.isEmpty {
                        waitingForInput = true
                    }
                    break
                }

                if event.type == .assistantTurnStart {
                    break  // Stop searching
                }
            }

            if waitingForInput {
                let truncatedMessage = lastAssistantMessage?.data?.content.map { content in
                    if content.count > 200 {
                        return String(content.prefix(200))
                    }
                    return content
                }

                return SessionState(
                    status: .waitingForUser,
                    reason: "Agent completed turn, awaiting user response",
                    lastMessage: truncatedMessage,
                    timestamp: lastEvent.timestamp
                )
            } else {
                return SessionState(
                    status: .ready,
                    reason: "Turn ended, agent ready for more input",
                    timestamp: lastEvent.timestamp
                )
            }
        }

        // User message is the last relevant event - agent should respond
        if lastUserMessageIdx > lastTurnEndIdx {
            let userMessageTimestamp =
                lastUserMessageIdx >= 0 ? currentSessionEvents[lastUserMessageIdx].timestamp : nil
            return SessionState(
                status: .userWaiting,
                reason: "User sent message, waiting for agent",
                timestamp: userMessageTimestamp
            )
        }

        return SessionState(
            status: .unknown,
            reason: "Unable to determine state"
        )
    }

    /// Filter events to only include those from the current session
    /// Returns events after the last session.start event, or all events if no session.start exists
    private static func filterToCurrentSession(events: [CopilotEvent]) -> [CopilotEvent] {
        // Find the last session.start event
        guard let lastSessionStartIndex = events.lastIndex(where: { $0.type == .sessionStart }) else {
            // No session.start event found, return all events
            return events
        }

        // Return events from the last session.start onwards
        return Array(events[lastSessionStartIndex...])
    }

    /// Check if there's a tool execution waiting for approval
    /// This happens when a tool.execution_start exists without a matching tool.execution_complete
    private static func checkForToolAwaitingApproval(events: [CopilotEvent]) -> SessionState? {
        // Build a map of tool call IDs that have started and completed
        var startedTools: Set<String> = []
        var completedTools: Set<String> = []

        for event in events {
            switch event.type {
            case .toolExecutionStart:
                if let toolCallId = event.data?.toolCallId {
                    startedTools.insert(toolCallId)
                }
            case .toolExecutionComplete:
                if let toolCallId = event.data?.toolCallId {
                    completedTools.insert(toolCallId)
                }
            case .abort:
                // If there's an abort, no tools are pending
                return nil
            default:
                break
            }
        }

        // Check if there are any started tools that haven't completed
        let pendingTools = startedTools.subtracting(completedTools)

        if !pendingTools.isEmpty {
            // Find the tool name for better context
            var toolName: String?
            for event in events.reversed() {
                if event.type == .toolExecutionStart,
                    let callId = event.data?.toolCallId,
                    pendingTools.contains(callId)
                {
                    toolName = event.data?.toolName
                    break
                }
            }

            let reason =
                toolName.map { "Tool '\($0)' waiting for approval" }
                ?? "Tool waiting for approval"

            return SessionState(
                status: .waitingForApproval,
                reason: reason,
                timestamp: events.last?.timestamp
            )
        }

        return nil
    }
}
