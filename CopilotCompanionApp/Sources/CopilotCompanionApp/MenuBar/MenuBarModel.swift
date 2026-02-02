//
//  MenuBarModel.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/2/26.
//

import Foundation
import SwiftUI

@MainActor
final class MenuBarModel: ObservableObject {
    @Published var isWatching = false
    @Published var sessionsWaitingForUser: [CopilotSession] = []
    @Published var errorMessage: String?

    private var sessionWatcher: SessionWatcher?

    init(startWatchingOnInit: Bool = true) {
        if startWatchingOnInit {
            startWatching()
        }
    }

    func toggleWatching() {
        if isWatching {
            stopWatching()
        } else {
            startWatching()
        }
    }

    func startWatching() {
        guard !isWatching else { return }

        let fileManager = FileManager.default
        let copilotConfigDirectory = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".copilot")
            .appending(path: "session-state")

        if !fileManager.fileExists(atPath: copilotConfigDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: copilotConfigDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                errorMessage = "Failed to create directory: \(error.localizedDescription)"
                return
            }
        }

        let manager = SessionManager(sessionStateDirectory: copilotConfigDirectory)
        let folderWatcher = FolderWatcher(folderURL: copilotConfigDirectory)
        let watcher = SessionWatcher(sessionManager: manager, folderWatcher: folderWatcher)

        Task {
            do {
                try await watcher.startWatching { [weak self] sessions in
                    await MainActor.run {
                        self?.sessionsWaitingForUser = sessions
                    }
                }

                await MainActor.run {
                    self.sessionWatcher = watcher
                    self.isWatching = true
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.sessionWatcher = nil
                    self.isWatching = false
                    self.errorMessage = "Failed to start watching: \(error.localizedDescription)"
                }
            }
        }
    }

    func stopWatching() {
        Task { [weak self] in
            guard let self else { return }
            await sessionWatcher?.stopWatching()
            await MainActor.run {
                self.sessionWatcher = nil
                self.isWatching = false
                self.sessionsWaitingForUser = []
            }
        }
    }
}
