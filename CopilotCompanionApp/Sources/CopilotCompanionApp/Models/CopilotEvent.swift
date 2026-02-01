//
//  CopilotEvent.swift
//  CopilotCompanionApp
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation

/// Represents a single event from a Copilot session's events.jsonl file
struct CopilotEvent: Sendable, Equatable, Codable {
    let type: CopilotEventType
    let timestamp: Date?
    let data: CopilotEventData?

    enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case data
    }

    init(type: CopilotEventType, timestamp: Date? = nil, data: CopilotEventData? = nil) {
        self.type = type
        self.timestamp = timestamp
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(CopilotEventType.self, forKey: .type)
        self.data = try container.decodeIfPresent(CopilotEventData.self, forKey: .data)

        // Handle timestamp which can be ISO8601 string or number
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            self.timestamp = ISO8601DateFormatter().date(from: timestampString)
        } else if let timestampDouble = try? container.decode(Double.self, forKey: .timestamp) {
            self.timestamp = Date(timeIntervalSince1970: timestampDouble / 1000)
        } else {
            self.timestamp = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(data, forKey: .data)
        if let timestamp {
            try container.encode(ISO8601DateFormatter().string(from: timestamp), forKey: .timestamp)
        }
    }
}

/// The type of a Copilot event
enum CopilotEventType: String, Sendable, Equatable, Codable {
    case userMessage = "user.message"
    case assistantTurnStart = "assistant.turn_start"
    case assistantTurnEnd = "assistant.turn_end"
    case assistantMessage = "assistant.message"
    case toolExecutionStart = "tool.execution_start"
    case toolExecutionComplete = "tool.execution_complete"
    case abort = "abort"
    case sessionStart = "session.start"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = CopilotEventType(rawValue: rawValue) ?? .unknown
    }
}

/// Data associated with a Copilot event
struct CopilotEventData: Sendable, Equatable, Codable {
    let turnId: String?
    let content: String?
    let toolRequests: [CopilotToolRequest]?
    let toolCallId: String?
    let toolName: String?

    enum CodingKeys: String, CodingKey {
        case turnId
        case content
        case toolRequests
        case toolCallId
        case toolName
    }

    init(
        turnId: String? = nil,
        content: String? = nil,
        toolRequests: [CopilotToolRequest]? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil
    ) {
        self.turnId = turnId
        self.content = content
        self.toolRequests = toolRequests
        self.toolCallId = toolCallId
        self.toolName = toolName
    }
}

/// Represents a tool request within an assistant message
struct CopilotToolRequest: Sendable, Equatable, Codable {
    let id: String?
    let name: String?
    let status: String?

    init(id: String? = nil, name: String? = nil, status: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
    }
}
