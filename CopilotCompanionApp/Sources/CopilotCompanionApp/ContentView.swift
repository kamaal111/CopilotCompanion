//
//  ContentView.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 1/31/26.
//

import SwiftUI

struct ContentView: View {
    @State private var watcher: FolderWatcher?
    @State private var isWatching = false
    @State private var changes: [FolderWatcherChange] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Copilot Folder Watcher")
                .font(.title)
                .padding()

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

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if changes.isEmpty {
                        Text("No changes detected yet")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                            HStack {
                                Image(systemName: iconForChangeType(change.type))
                                    .foregroundColor(colorForChangeType(change.type))
                                VStack(alignment: .leading) {
                                    Text(change.path.lastPathComponent)
                                        .font(.headline)
                                    Text(formatDate(change.timestamp))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, minHeight: 400)
        .padding()
    }

    private func toggleWatching() {
        if isWatching {
            stopWatching()
        } else {
            startWatching()
        }
    }

    private func startWatching() {
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

        let folderWatcher = FolderWatcher(folderURL: copilotConfigDirectory)

        Task {
            do {
                try await folderWatcher.startWatching { change in
                    await MainActor.run {
                        changes.insert(change, at: 0)
                        if changes.count > 50 {
                            changes.removeLast()
                        }
                    }
                }
                await MainActor.run {
                    self.watcher = folderWatcher
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
            await watcher?.stopWatching()
            await MainActor.run {
                self.watcher = nil
                self.isWatching = false
            }
        }
    }

    private func iconForChangeType(_ type: FolderWatcherChangeType) -> String {
        switch type {
        case .created: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.triangle.2.circlepath"
        }
    }

    private func colorForChangeType(_ type: FolderWatcherChangeType) -> Color {
        switch type {
        case .created: return .green
        case .modified: return .blue
        case .deleted: return .red
        case .renamed: return .orange
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
