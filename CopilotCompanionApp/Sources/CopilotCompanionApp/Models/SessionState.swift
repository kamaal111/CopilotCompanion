//
//  SessionState.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation

/// Represents the analyzed state of a Copilot session
struct SessionState: Sendable, Equatable {
    let status: SessionStatus
    let reason: String
    let turnId: String?
    let lastMessage: String?
    let timestamp: Date?

    init(
        status: SessionStatus,
        reason: String,
        turnId: String? = nil,
        lastMessage: String? = nil,
        timestamp: Date? = nil
    ) {
        self.status = status
        self.reason = reason
        self.turnId = turnId
        self.lastMessage = lastMessage
        self.timestamp = timestamp
    }
}

/// The status of a Copilot session
enum SessionStatus: String, Sendable, Equatable, CaseIterable {
    /// Agent completed turn and is waiting for user response
    case waitingForUser = "waiting_for_user"
    /// Tool is waiting for user approval
    case waitingForApproval = "waiting_for_approval"
    /// Agent is actively processing/working
    case processing
    /// User sent a message and is waiting for the agent
    case userWaiting = "user_waiting"
    /// Turn ended, agent is ready for more input
    case ready
    /// No events in the session
    case empty
    /// Unable to determine state
    case unknown

    var displayName: String {
        switch self {
        case .waitingForUser: return "Waiting for User"
        case .waitingForApproval: return "Waiting for Approval"
        case .processing: return "Processing"
        case .userWaiting: return "User Waiting"
        case .ready: return "Ready"
        case .empty: return "Empty"
        case .unknown: return "Unknown"
        }
    }

    var emoji: String {
        switch self {
        case .waitingForUser: return "🔔"
        case .waitingForApproval: return "⚠️"
        case .processing: return "⚙️"
        case .userWaiting: return "⏳"
        case .ready: return "✅"
        case .empty: return "📭"
        case .unknown: return "❓"
        }
    }
}
