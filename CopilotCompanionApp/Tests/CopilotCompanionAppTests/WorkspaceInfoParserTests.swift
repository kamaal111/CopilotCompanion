//
//  WorkspaceInfoParserTests.swift
//  CopilotCompanionAppTests
//
//  Created by Kamaal M Farah on 2/1/26.
//

import Foundation
import Testing

@testable import CopilotCompanionApp

@Suite("WorkspaceInfoParser tests")
struct WorkspaceInfoParserTests {
    // MARK: - Valid Content Tests

    @Test
    func `parses workspace yaml with all fields`() {
        let content = """
            repository: kamaal111/CopilotCompanion
            cwd: /Users/kamaal/Projects/Swift/Apps/CopilotCompanion
            summary: A macOS app for monitoring Copilot sessions
            """

        let info = WorkspaceInfoParser.parse(content: content)

        #expect(info.repository == "kamaal111/CopilotCompanion")
        #expect(info.cwd == "/Users/kamaal/Projects/Swift/Apps/CopilotCompanion")
        #expect(info.summary == "A macOS app for monitoring Copilot sessions")
    }

    @Test
    func `parses workspace yaml with only repository`() {
        let content = """
            repository: my-org/my-repo
            """

        let info = WorkspaceInfoParser.parse(content: content)

        #expect(info.repository == "my-org/my-repo")
        #expect(info.cwd == nil)
        #expect(info.summary == nil)
    }

    @Test
    func `parses workspace yaml with only cwd`() {
        let content = """
            cwd: /some/path/to/project
            """

        let info = WorkspaceInfoParser.parse(content: content)

        #expect(info.repository == nil)
        #expect(info.cwd == "/some/path/to/project")
        #expect(info.summary == nil)
    }

    @Test
    func `parses workspace yaml with extra fields`() {
        let content = """
            repository: my-repo
            cwd: /my/path
            summary: My summary
            extraField: some value
            anotherField: another value
            """

        let info = WorkspaceInfoParser.parse(content: content)

        #expect(info.repository == "my-repo")
        #expect(info.cwd == "/my/path")
        #expect(info.summary == "My summary")
    }

    // MARK: - Edge Cases

    @Test
    func `handles empty content`() {
        let content = ""

        let info = WorkspaceInfoParser.parse(content: content)

        #expect(info.repository == nil)
        #expect(info.cwd == nil)
        #expect(info.summary == nil)
    }

    @Test
    func `handles content with only whitespace`() {
        let content = "   \n   \n   "

        let info = WorkspaceInfoParser.parse(content: content)

        #expect(info.repository == nil)
        #expect(info.cwd == nil)
        #expect(info.summary == nil)
    }

    @Test
    func `handles values with colons`() {
        let content = """
            cwd: /path/with:colon/and:more
            summary: Time: 10:30 AM
            """

        let info = WorkspaceInfoParser.parse(content: content)

        #expect(info.cwd == "/path/with:colon/and:more")
        #expect(info.summary == "Time: 10:30 AM")
    }

    @Test
    func `handles values with leading and trailing whitespace`() {
        let content = """
            repository:   my-repo   
            cwd:    /my/path    
            """

        let info = WorkspaceInfoParser.parse(content: content)

        #expect(info.repository == "my-repo")
        #expect(info.cwd == "/my/path")
    }

    @Test
    func `ignores lines without colons`() {
        let content = """
            repository: my-repo
            this line has no colon
            cwd: /my/path
            """

        let info = WorkspaceInfoParser.parse(content: content)

        #expect(info.repository == "my-repo")
        #expect(info.cwd == "/my/path")
    }

    @Test
    func `handles empty values`() {
        let content = """
            repository:
            cwd: /my/path
            """

        let info = WorkspaceInfoParser.parse(content: content)

        #expect(info.repository == "")
        #expect(info.cwd == "/my/path")
    }

    // MARK: - File Reading Tests

    @Test
    func `parses workspace yaml from file`() throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let content = """
            repository: test/repo
            cwd: /test/path
            """

        let fileURL = testDir.appendingPathComponent("workspace.yaml")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let info = WorkspaceInfoParser.parse(url: fileURL)

        #expect(info?.repository == "test/repo")
        #expect(info?.cwd == "/test/path")
    }

    @Test
    func `returns nil for non-existent file`() {
        let nonExistentURL = URL(fileURLWithPath: "/non/existent/workspace.yaml")

        let info = WorkspaceInfoParser.parse(url: nonExistentURL)

        #expect(info == nil)
    }

    @Test
    func `parses from session directory`() throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let content = """
            repository: session/repo
            summary: Session summary
            """

        let fileURL = testDir.appendingPathComponent("workspace.yaml")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let info = WorkspaceInfoParser.parse(sessionDirectory: testDir)

        #expect(info?.repository == "session/repo")
        #expect(info?.summary == "Session summary")
    }

    @Test
    func `returns nil for session directory without workspace yaml`() throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let info = WorkspaceInfoParser.parse(sessionDirectory: testDir)

        #expect(info == nil)
    }

    // MARK: - WorkspaceInfo projectName Tests

    @Test
    func `projectName returns repository when available`() {
        let info = WorkspaceInfo(repository: "my-org/my-repo", cwd: "/some/path")

        #expect(info.projectName == "my-org/my-repo")
    }

    @Test
    func `projectName returns last path component of cwd when no repository`() {
        let info = WorkspaceInfo(cwd: "/Users/kamaal/Projects/MyProject")

        #expect(info.projectName == "MyProject")
    }

    @Test
    func `projectName returns Unknown when no repository or cwd`() {
        let info = WorkspaceInfo()

        #expect(info.projectName == "Unknown")
    }

    @Test
    func `projectName returns Unknown for empty repository and cwd`() {
        let info = WorkspaceInfo(repository: "", cwd: "")

        #expect(info.projectName == "Unknown")
    }

}
