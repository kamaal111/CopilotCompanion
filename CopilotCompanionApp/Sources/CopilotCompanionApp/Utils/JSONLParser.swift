//
//  JSONLParser.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation

/// Parser for JSONL (JSON Lines) files containing Copilot events
enum JSONLParser {
    /// Parse a JSONL file at the given URL and return an array of CopilotEvents
    /// - Parameter url: The URL of the JSONL file to parse
    /// - Returns: An array of successfully parsed CopilotEvent objects
    /// - Throws: If the file cannot be read
    static func parse(url: URL) throws -> [CopilotEvent] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content: content)
    }

    /// Parse JSONL content string and return an array of CopilotEvents
    /// - Parameter content: The JSONL content as a string
    /// - Returns: An array of successfully parsed CopilotEvent objects
    static func parse(content: String) -> [CopilotEvent] {
        let lines = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let decoder = JSONDecoder()
        var events: [CopilotEvent] = []

        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }

            do {
                let event = try decoder.decode(CopilotEvent.self, from: data)
                events.append(event)
            } catch {
                // Skip malformed lines, matching JS behavior
                continue
            }
        }

        return events
    }

    /// Check if the content appears to be valid JSONL format
    /// - Parameter content: The content to validate
    /// - Returns: true if at least one line can be parsed as JSON
    static func isValidJSONL(content: String) -> Bool {
        let lines = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            guard let data = trimmed.data(using: .utf8) else { continue }

            if (try? JSONSerialization.jsonObject(with: data)) != nil {
                return true
            }
        }

        return false
    }
}
