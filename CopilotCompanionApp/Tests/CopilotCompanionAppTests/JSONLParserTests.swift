//
//  JSONLParserTests.swift
//  CopilotCompanionAppTests
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation
import Testing

@testable import CopilotCompanionApp

@Suite("JSONLParser tests")
struct JSONLParserTests {
    // MARK: - Valid Content Tests

    @Test
    func `parses valid JSONL with single event`() {
        let content = """
            {"type":"user.message","timestamp":"2026-02-01T10:00:00Z"}
            """

        let events = JSONLParser.parse(content: content)

        #expect(events.count == 1)
        #expect(events[0].type == .userMessage)
    }

    @Test
    func `parses valid JSONL with multiple events`() {
        let content = """
            {"type":"user.message","timestamp":"2026-02-01T10:00:00Z"}
            {"type":"assistant.turn_start","data":{"turnId":"turn-123"}}
            {"type":"assistant.message","data":{"content":"Hello!"}}
            {"type":"assistant.turn_end"}
            """

        let events = JSONLParser.parse(content: content)

        #expect(events.count == 4)
        #expect(events[0].type == .userMessage)
        #expect(events[1].type == .assistantTurnStart)
        #expect(events[1].data?.turnId == "turn-123")
        #expect(events[2].type == .assistantMessage)
        #expect(events[2].data?.content == "Hello!")
        #expect(events[3].type == .assistantTurnEnd)
    }

    @Test
    func `parses event with tool requests`() {
        let content = """
            {"type":"assistant.message","data":{"content":"Working...","toolRequests":[{"id":"req-1","name":"read_file","status":"pending"}]}}
            """

        let events = JSONLParser.parse(content: content)

        #expect(events.count == 1)
        #expect(events[0].data?.toolRequests?.count == 1)
        #expect(events[0].data?.toolRequests?[0].id == "req-1")
        #expect(events[0].data?.toolRequests?[0].name == "read_file")
    }

    // MARK: - Invalid Content Tests

    @Test
    func `skips malformed JSON lines`() {
        let content = """
            {"type":"user.message"}
            {invalid json here}
            {"type":"assistant.turn_end"}
            """

        let events = JSONLParser.parse(content: content)

        #expect(events.count == 2)
        #expect(events[0].type == .userMessage)
        #expect(events[1].type == .assistantTurnEnd)
    }

    @Test
    func `handles empty content`() {
        let content = ""

        let events = JSONLParser.parse(content: content)

        #expect(events.isEmpty)
    }

    @Test
    func `handles content with only whitespace and newlines`() {
        let content = """


               
            """

        let events = JSONLParser.parse(content: content)

        #expect(events.isEmpty)
    }

    @Test
    func `handles content with empty lines between valid events`() {
        let content = """
            {"type":"user.message"}

            {"type":"assistant.turn_end"}

            """

        let events = JSONLParser.parse(content: content)

        #expect(events.count == 2)
    }

    @Test
    func `handles unknown event types gracefully`() {
        let content = """
            {"type":"some.unknown.type"}
            {"type":"user.message"}
            """

        let events = JSONLParser.parse(content: content)

        #expect(events.count == 2)
        #expect(events[0].type == .unknown)
        #expect(events[1].type == .userMessage)
    }

    // MARK: - File Reading Tests

    @Test
    func `parses JSONL file from disk`() throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let content = """
            {"type":"user.message"}
            {"type":"assistant.turn_end"}
            """

        let fileURL = testDir.appendingPathComponent("events.jsonl")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let events = try JSONLParser.parse(url: fileURL)

        #expect(events.count == 2)
    }

    @Test
    func `throws error for non-existent file`() {
        let nonExistentURL = URL(fileURLWithPath: "/non/existent/path.jsonl")

        #expect(throws: Error.self) {
            _ = try JSONLParser.parse(url: nonExistentURL)
        }
    }

    // MARK: - Validation Tests

    @Test
    func `validates valid JSONL content`() {
        let content = """
            {"type":"user.message"}
            """

        #expect(JSONLParser.isValidJSONL(content: content))
    }

    @Test
    func `invalidates completely malformed content`() {
        let content = "not json at all"

        #expect(!JSONLParser.isValidJSONL(content: content))
    }

    @Test
    func `validates content with some valid and some invalid lines`() {
        let content = """
            invalid line
            {"type":"user.message"}
            """

        #expect(JSONLParser.isValidJSONL(content: content))
    }

    // MARK: - Timestamp Parsing Tests

    @Test
    func `parses ISO8601 timestamp string`() {
        let content = """
            {"type":"user.message","timestamp":"2026-02-01T10:30:00Z"}
            """

        let events = JSONLParser.parse(content: content)

        #expect(events.count == 1)
        #expect(events[0].timestamp != nil)
    }

    @Test
    func `parses numeric timestamp`() {
        let content = """
            {"type":"user.message","timestamp":1738405800000}
            """

        let events = JSONLParser.parse(content: content)

        #expect(events.count == 1)
        #expect(events[0].timestamp != nil)
    }

    @Test
    func `handles missing timestamp`() {
        let content = """
            {"type":"user.message"}
            """

        let events = JSONLParser.parse(content: content)

        #expect(events.count == 1)
        #expect(events[0].timestamp == nil)
    }

}
