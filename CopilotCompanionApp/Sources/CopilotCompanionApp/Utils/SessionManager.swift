//
//  SessionManager.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation

/// Manages discovery and state tracking of Copilot sessions
actor SessionManager {
    private let sessionStateDirectory: URL
    private let fileManager: FileManager

    /// Initialize with the default Copilot session state directory
    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.sessionStateDirectory =
            homeDirectory
            .appendingPathComponent(".copilot")
            .appendingPathComponent("session-state")
        self.fileManager = FileManager.default
    }

    /// Initialize with a custom session state directory (useful for testing)
    init(sessionStateDirectory: URL) {
        self.sessionStateDirectory = sessionStateDirectory
        self.fileManager = FileManager.default
    }

    /// Get all active sessions and their states, sorted by last modified (most recent first)
    /// - Returns: Array of CopilotSession objects
    func getActiveSessions() -> [CopilotSession] {
        var sessions: [CopilotSession] = []

        guard fileManager.fileExists(atPath: sessionStateDirectory.path) else {
            return sessions
        }

        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: sessionStateDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: []
            )
        else {
            return sessions
        }

        for entryURL in entries {
            let entryName = entryURL.lastPathComponent

            // Skip hidden files
            if entryName.hasPrefix(".") { continue }

            do {
                let resourceValues = try entryURL.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues.isDirectory ?? false

                if isDirectory {
                    // Check for folder-based sessions (with events.jsonl)
                    if let session = tryParseFolderSession(at: entryURL, name: entryName) {
                        sessions.append(session)
                    }
                } else if entryName.hasSuffix(".jsonl") {
                    // Check for simple JSONL sessions
                    if let session = tryParseJSONLSession(at: entryURL, name: entryName) {
                        sessions.append(session)
                    }
                }
            } catch {
                // Skip entries that can't be read
                continue
            }
        }

        // Sort by last modified (most recent first)
        sessions.sort { $0.lastModified > $1.lastModified }

        return sessions
    }

    /// Get sessions that are waiting for user input (either response or approval)
    /// - Returns: Array of CopilotSession objects with status .waitingForUser or .waitingForApproval
    func getSessionsWaitingForUser() -> [CopilotSession] {
        getActiveSessions().filter {
            $0.state.status == .waitingForUser || $0.state.status == .waitingForApproval
        }
    }

    /// Check if any session is waiting for user input (either response or approval)
    /// - Returns: true if at least one session has status .waitingForUser or .waitingForApproval
    func hasSessionWaitingForUser() -> Bool {
        getActiveSessions().contains {
            $0.state.status == .waitingForUser || $0.state.status == .waitingForApproval
        }
    }

    // MARK: - Private Methods

    private func tryParseFolderSession(at folderURL: URL, name: String) -> CopilotSession? {
        let eventsPath = folderURL.appendingPathComponent("events.jsonl")

        guard fileManager.fileExists(atPath: eventsPath.path) else {
            return nil
        }

        do {
            let events = try JSONLParser.parse(url: eventsPath)
            let state = SessionStateAnalyzer.analyze(events: events)
            let workspaceInfo = WorkspaceInfoParser.parse(sessionDirectory: folderURL)

            let attributes = try fileManager.attributesOfItem(atPath: eventsPath.path)
            let lastModified = (attributes[.modificationDate] as? Date) ?? Date.distantPast

            return CopilotSession(
                id: name,
                type: .folder,
                path: folderURL,
                eventsPath: eventsPath,
                eventCount: events.count,
                state: state,
                workspace: workspaceInfo,
                lastModified: lastModified
            )
        } catch {
            return nil
        }
    }

    private func tryParseJSONLSession(at fileURL: URL, name: String) -> CopilotSession? {
        do {
            let events = try JSONLParser.parse(url: fileURL)
            let state = SessionStateAnalyzer.analyze(events: events)

            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let lastModified = (attributes[.modificationDate] as? Date) ?? Date.distantPast

            // Remove .jsonl extension for the ID
            let sessionId =
                name.hasSuffix(".jsonl")
                ? String(name.dropLast(6))
                : name

            return CopilotSession(
                id: sessionId,
                type: .jsonl,
                path: fileURL,
                eventsPath: nil,
                eventCount: events.count,
                state: state,
                workspace: nil,
                lastModified: lastModified
            )
        } catch {
            return nil
        }
    }
}
