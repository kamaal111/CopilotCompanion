//
//  WorkspaceInfoParser.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation

/// Parser for workspace.yaml files in Copilot session directories
enum WorkspaceInfoParser {
    /// Parse a workspace.yaml file at the given URL
    /// - Parameter url: The URL of the workspace.yaml file
    /// - Returns: WorkspaceInfo if the file exists and can be parsed, nil otherwise
    static func parse(url: URL) -> WorkspaceInfo? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        return parse(content: content)
    }

    /// Parse a workspace.yaml file in the given session directory
    /// - Parameter sessionDirectory: The URL of the session directory
    /// - Returns: WorkspaceInfo if workspace.yaml exists and can be parsed, nil otherwise
    static func parse(sessionDirectory: URL) -> WorkspaceInfo? {
        let workspacePath = sessionDirectory.appendingPathComponent("workspace.yaml")
        return parse(url: workspacePath)
    }

    /// Parse workspace.yaml content string
    /// - Parameter content: The YAML content as a string
    /// - Returns: WorkspaceInfo parsed from the content
    static func parse(content: String) -> WorkspaceInfo {
        var info: [String: String] = [:]

        // Simple YAML parsing - matches the JS implementation
        // Only handles simple key: value pairs at the top level
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let trimmedLine = String(line)

            // Match pattern: key: value
            // Using simple string parsing instead of regex for efficiency
            guard let colonIndex = trimmedLine.firstIndex(of: ":") else { continue }

            let key = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            // Only accept word characters for keys (alphanumeric + underscore)
            let keyIsValid = key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            if keyIsValid && !key.isEmpty {
                info[key] = value
            }
        }

        return WorkspaceInfo(
            repository: info["repository"],
            cwd: info["cwd"],
            summary: info["summary"]
        )
    }
}
