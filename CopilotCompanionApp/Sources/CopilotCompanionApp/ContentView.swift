//
//  ContentView.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 1/31/26.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: MenuBarModel

    var body: some View {
        VStack(spacing: 16) {
            headerView

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }

            Button(action: model.toggleWatching) {
                Text(model.isWatching ? "Stop Watching" : "Start Watching")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)

            if model.isWatching {
                Text("Watching: ~/.copilot/session-state")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            sessionListView

            Divider()

            HStack {
                Spacer()
                Button("Quit CopilotCompanion") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(width: 360, height: 480)
        .padding()
    }

    private var headerView: some View {
        HStack {
            Text("🤖 Copilot Session Monitor")
                .font(.title)

            Spacer()

            if !model.sessionsWaitingForUser.isEmpty {
                HStack(spacing: 4) {
                    Text("🔔")
                    Text("\(model.sessionsWaitingForUser.count)")
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
                if model.sessionsWaitingForUser.isEmpty {
                    emptyStateView
                } else {
                    ForEach(model.sessionsWaitingForUser) { session in
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
            if model.isWatching {
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
        .environmentObject(MenuBarModel(startWatchingOnInit: false))
}
