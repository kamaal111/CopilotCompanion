//
//  WorkspaceInfo.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation

/// Information about a Copilot session's workspace from workspace.yaml
struct WorkspaceInfo: Sendable, Equatable {
    let repository: String?
    let cwd: String?
    let summary: String?

    init(repository: String? = nil, cwd: String? = nil, summary: String? = nil) {
        self.repository = repository
        self.cwd = cwd
        self.summary = summary
    }

    /// Returns a display-friendly project name
    var projectName: String {
        if let repository, !repository.isEmpty {
            return repository
        }
        if let cwd, !cwd.isEmpty {
            return (cwd as NSString).lastPathComponent
        }
        return "Unknown"
    }
}
