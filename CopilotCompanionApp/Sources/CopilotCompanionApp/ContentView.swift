//
//  ContentView.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 1/31/26.
//

import SwiftUI

struct ContentView: View {
    @State private var sessionWatcher: SessionWatcher?
    @State private var isWatching = false
    @State private var sessionsWaitingForUser: [CopilotSession] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            headerView

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }

            Button(action: toggleWatching) {
                Text(isWatching ? "Stop Watching" : "Start Watching")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)

            if isWatching {
                Text("Watching: ~/.copilot/session-state")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            sessionListView
        }
        .frame(minWidth: 500, minHeight: 400)
        .padding()
        .task {
            if !isWatching {
                startWatching()
            }
        }
    }

    private var headerView: some View {
        HStack {
            Text("🤖 Copilot Session Monitor")
                .font(.title)

            Spacer()

            if !sessionsWaitingForUser.isEmpty {
                HStack(spacing: 4) {
                    Text("🔔")
                    Text("\(sessionsWaitingForUser.count)")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(12)
            }
        }
        .padding()
    }

    private var sessionListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if sessionsWaitingForUser.isEmpty {
                    emptyStateView
                } else {
                    ForEach(sessionsWaitingForUser) { session in
                        sessionCard(for: session)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Text("✅")
                .font(.system(size: 48))
            Text("No sessions waiting for your input")
                .font(.headline)
                .foregroundColor(.secondary)
            if isWatching {
                Text("We'll update automatically when Copilot needs you")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func sessionCard(for session: CopilotSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.state.status.emoji)
                    .font(.title2)
                Text(session.projectName)
                    .font(.headline)
                Spacer()
                Text(formatDate(session.lastModified))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(session.shortId)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let summary = session.workspace?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            if let lastMessage = session.state.lastMessage, !lastMessage.isEmpty {
                Text("\"\(lastMessage)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .italic()
            }

            HStack {
                Label("\(session.eventCount) events", systemImage: "list.bullet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(session.state.reason)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func toggleWatching() {
        if isWatching {
            stopWatching()
        } else {
            startWatching()
        }
    }

    private func startWatching() {
        guard !isWatching else { return }
        let fileManager = FileManager.default
        let copilotConfigDirectory = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".copilot")
            .appending(path: "session-state")

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: copilotConfigDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: copilotConfigDirectory, withIntermediateDirectories: true)
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
                try await watcher.startWatching { sessions in
                    await MainActor.run {
                        self.sessionsWaitingForUser = sessions
                    }
                }

                await MainActor.run {
                    self.sessionWatcher = watcher
                    self.isWatching = true
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start watching: \(error.localizedDescription)"
                }
            }
        }
    }

    private func stopWatching() {
        Task {
            await sessionWatcher?.stopWatching()
            await MainActor.run {
                self.sessionWatcher = nil
                self.isWatching = false
                self.sessionsWaitingForUser = []
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
