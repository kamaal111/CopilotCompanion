//
//  CopilotSession.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation

/// Represents a Copilot session with its state and metadata
struct CopilotSession: Sendable, Equatable, Identifiable {
    let id: String
    let type: SessionType
    let path: URL
    let eventsPath: URL?
    let eventCount: Int
    let state: SessionState
    let workspace: WorkspaceInfo?
    let lastModified: Date

    init(
        id: String,
        type: SessionType,
        path: URL,
        eventsPath: URL? = nil,
        eventCount: Int,
        state: SessionState,
        workspace: WorkspaceInfo? = nil,
        lastModified: Date
    ) {
        self.id = id
        self.type = type
        self.path = path
        self.eventsPath = eventsPath
        self.eventCount = eventCount
        self.state = state
        self.workspace = workspace
        self.lastModified = lastModified
    }

    /// Returns a display-friendly project name
    var projectName: String {
        workspace?.projectName ?? "Unknown"
    }

    /// Returns a truncated session ID for display
    var shortId: String {
        if id.count > 36 {
            return String(id.prefix(36)) + "..."
        }
        return id
    }
}

/// The type of session storage
enum SessionType: String, Sendable, Equatable {
    /// Folder-based session with events.jsonl inside
    case folder
    /// Simple .jsonl file session
    case jsonl
}
