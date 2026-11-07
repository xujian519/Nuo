//
//  AgentWorkspaceTests.swift
//  osaurusTests
//
//  Slice 3 (issue #17): a custom agent owns `~/.nuo/agents/<uuid>/workspace/`.
//  It is the fallback working root for host-folder runs, while a sandboxed
//  agent keeps its VM home. Agent creation materialises the directory, and
//  deleting the agent removes it with the rest of the agent directory.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite(.serialized)
@MainActor
struct AgentWorkspaceTests {
    private func makeAgent(sandbox: Bool) -> Agent {
        Agent(
            name: "Workspace-\(UUID().uuidString.prefix(6))",
            systemPrompt: "Test identity",
            agentAddress: "test-workspace-\(UUID().uuidString)",
            autonomousExec: AutonomousExecConfig(enabled: sandbox)
        )
    }

    @Test("the workspace path is the agent directory's workspace child")
    func pathShape() {
        let id = UUID()
        #expect(
            AgentWorkspace.directory(for: id)
                == OsaurusPaths.agentDirectory(for: id).appendingPathComponent(
                    "workspace",
                    isDirectory: true
                )
        )
    }

    @Test("ensure creates a writable directory once")
    func ensureCreates() throws {
        let id = UUID()
        defer { try? FileManager.default.removeItem(at: OsaurusPaths.agentDirectory(for: id)) }
        let first = try #require(AgentWorkspace.ensure(for: id))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(AgentWorkspace.ensure(for: id) == first)
    }

    @Test("agent creation materialises the workspace and delete removes it")
    func creationAndDeletion() async throws {
        try await ChatHistoryTestStorage.run {
            let agent = makeAgent(sandbox: false)
            AgentManager.shared.add(agent)
            let workspace = AgentWorkspace.directory(for: agent.id)
            #expect(FileManager.default.fileExists(atPath: workspace.path))

            let removed = await AgentManager.shared.delete(id: agent.id)
            #expect(removed.deleted)
            #expect(!FileManager.default.fileExists(atPath: workspace.path))
        }
    }

    @Test("a host-folder agent falls back to its workspace")
    func hostFolderFallback() async throws {
        try await ChatHistoryTestStorage.run {
            let agent = makeAgent(sandbox: false)
            AgentManager.shared.add(agent)
            defer { Task { _ = await AgentManager.shared.delete(id: agent.id) } }

            let folder = try #require(AgentWorkspace.defaultFolder(for: agent.id))
            #expect(folder.bookmark == nil)
            #expect(folder.path == AgentWorkspace.directory(for: agent.id).path)

            let request = DispatchRequest(prompt: "go", agentId: agent.id, source: .schedule)
            #expect(BackgroundTaskManager.resolveDispatchFolder(for: request)?.path == folder.path)
        }
    }

    @Test("a sandboxed agent keeps its VM home")
    func sandboxKeepsVMHome() async throws {
        try await ChatHistoryTestStorage.run {
            let agent = makeAgent(sandbox: true)
            AgentManager.shared.add(agent)
            defer { Task { _ = await AgentManager.shared.delete(id: agent.id) } }

            #expect(AgentWorkspace.defaultFolder(for: agent.id) == nil)
            let request = DispatchRequest(prompt: "go", agentId: agent.id, source: .schedule)
            #expect(BackgroundTaskManager.resolveDispatchFolder(for: request) == nil)
        }
    }

    @Test("the built-in Orchestrator has no implicit workspace")
    func defaultAgentHasNoImplicitWorkspace() {
        #expect(AgentWorkspace.defaultFolder(for: Agent.defaultId) == nil)
    }
}
