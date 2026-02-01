//
//  SessionWatcher.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation

/// Manages watching for new Copilot sessions that need user attention
actor SessionWatcher {
    private let sessionManager: SessionManager
    private let folderWatcher: FolderWatcher
    private var watchStartTime: Date?
    private var refreshTask: Task<Void, Never>?
    private var isActive = false

    init(sessionManager: SessionManager, folderWatcher: FolderWatcher) {
        self.sessionManager = sessionManager
        self.folderWatcher = folderWatcher
    }

    /// Start watching for new sessions that need user attention
    /// - Parameter onChange: Callback invoked when sessions change
    func startWatching(onChange: @escaping @Sendable ([CopilotSession]) async -> Void) async throws {
        guard !isActive else { return }

        // Record when we started - only report sessions modified AFTER this time
        let startTime = Date()
        self.watchStartTime = startTime
        self.isActive = true

        // Start file system watching
        try await folderWatcher.startWatching { [weak self] _ in
            guard let self else { return }
            await self.scheduleRefresh(onChange: onChange)
        }
    }

    /// Stop watching for session changes
    func stopWatching() async {
        guard isActive else { return }

        refreshTask?.cancel()
        await folderWatcher.stopWatching()
        self.isActive = false
        self.watchStartTime = nil
        self.refreshTask = nil
    }

    /// Get currently waiting sessions (filtered by start time)
    func getWaitingSessions() async -> [CopilotSession] {
        guard let startTime = watchStartTime else {
            return []
        }

        let allWaitingSessions = await sessionManager.getSessionsWaitingForUser()

        // Only return sessions modified AFTER we started watching
        return allWaitingSessions.filter { session in
            session.lastModified >= startTime
        }
    }

    /// Check if currently watching
    func isWatching() -> Bool {
        isActive
    }

    // MARK: - Private Methods

    private func scheduleRefresh(onChange: @escaping @Sendable ([CopilotSession]) async -> Void) async {
        // Cancel any pending refresh
        refreshTask?.cancel()

        // Schedule a new refresh after a short delay to debounce rapid file changes
        let task = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let sessions = await self.getWaitingSessions()
            await onChange(sessions)
        }

        self.refreshTask = task
    }
}
