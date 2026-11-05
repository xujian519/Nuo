//
//  DirectedMailboxTests.swift
//  osaurusTests
//
//  ADR-Nuo-002 P0：持久化往返、准入、深度、预算和两层记忆。
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite
struct DirectedMailboxTests {
    private let agentA = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let agentB = UUID(uuidString: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let agentC = UUID(uuidString: "CCCCCCCC-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let createdAt = ISO8601DateFormatter().date(from: "2026-11-05T00:00:00Z")!

    @Test("two agents round-trip a persisted untrusted envelope")
    func roundTripPersists() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = fixture.service
        let run = try await service.openRun(id: "round-trip")
        let sent = try await service.send(
            request("ping from orchestrator"),
            from: orchestrator,
            to: participant(agentA, name: "A"),
            runId: run.id,
            correlationId: "corr-round",
            createdAt: createdAt
        )

        let reloaded = try DirectedMailboxService(directory: fixture.directory)
        let inbox = try await reloaded.inbox(
            for: participant(agentA, name: "A").id,
            requestedBy: participant(agentA, name: "A").id
        )
        #expect(inbox.count == 1)
        #expect(inbox[0].contentUntrusted)
        #expect(inbox[0].envelope.schema == AgentCollaborationProtocolContract.schema)
        #expect(inbox[0].envelope.provenance.transport == DirectedMailboxSchema.transport)
        #expect(inbox[0].untrustedText().text == "ping from orchestrator")
        #expect(inbox[0].untrustedText().trusted == false)

        let reply = try await reloaded.send(
            .reply(
                AgentCollaborationReply(
                    inReplyToEnvelopeId: sent.record.id,
                    status: .completed,
                    message: "pong"
                )
            ),
            from: participant(agentA, name: "A"),
            to: orchestrator,
            runId: run.id,
            createdAt: createdAt.addingTimeInterval(1)
        )
        let orchestratorInbox = try await reloaded.inbox(
            for: orchestrator.id,
            requestedBy: orchestrator.id
        )
        #expect(orchestratorInbox.count == 1)
        #expect(orchestratorInbox[0].envelope.correlationId == "corr-round")
        #expect(reply.record.envelope.correlationId == "corr-round")
        guard case .reply(let body) = orchestratorInbox[0].envelope.event else {
            Issue.record("expected reply")
            return
        }
        #expect(body.inReplyToEnvelopeId == sent.record.id)
        #expect(body.message == "pong")
        #expect(fixture.service.fileURL.lastPathComponent == DirectedMailboxSchema.fileName)

        let legacy = AgentCollaborationService()
        #expect(await legacy.allEnvelopes().isEmpty)
        #expect(DirectedMailboxPolicy.orchestratorParticipantId == Agent.default.agentCollaborationParticipant.id)
        let agentJSON = String(decoding: try JSONEncoder().encode(Agent.default), as: UTF8.self)
        #expect(!agentJSON.contains("directed-mailbox"))
    }

    @Test("unauthorized edges and spawns are rejected; an allowlist persists")
    func authorization() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = fixture.service
        _ = try await service.openRun(id: "auth")
        let a = participant(agentA, name: "A")
        let b = participant(agentB, name: "B")
        let c = participant(agentC, name: "C")

        try await expectFailure(.unauthorizedEdge(from: a.id, to: b.id)) {
            _ = try await service.send(self.request("side channel"), from: a, to: b, runId: "auth")
        }
        try await expectFailure(.spawnNotAuthorized(caller: a.id, target: b.id)) {
            _ = try await service.authorizeSpawnResume(callerId: a.id, targetId: b.id)
        }
        let orchestratorGrant = try await service.authorizeSpawnResume(
            callerId: orchestrator.id,
            targetId: a.id
        )
        #expect(orchestratorGrant.inheritsCallerDispatchContext == false)
        #expect(orchestratorGrant.replacesSubagentDispatch == false)
        #expect(try await service.inbox(for: a.id, requestedBy: a.id).isEmpty)

        try await service.replaceAllowlist([DirectedMailboxEdge(from: a.id, to: b.id)])
        let reloaded = try DirectedMailboxService(directory: fixture.directory)
        let granted = try await reloaded.authorizeSpawnResume(callerId: a.id, targetId: b.id)
        #expect(granted.targetId == b.id)
        #expect(granted.inheritsCallerDispatchContext == false)
        try await expectFailure(.spawnNotAuthorized(caller: a.id, target: c.id)) {
            _ = try await reloaded.authorizeSpawnResume(callerId: a.id, targetId: c.id)
        }
        #expect(await reloaded.allowlist() == [DirectedMailboxEdge(from: a.id, to: b.id)])

        let opened = try await service.send(
            request("owned by orchestrator"),
            from: orchestrator,
            to: a,
            runId: "auth",
            createdAt: createdAt
        )
        try await expectFailure(.unauthorizedEdge(from: a.id, to: b.id)) {
            _ = try await service.send(
                .reply(
                    AgentCollaborationReply(
                        inReplyToEnvelopeId: opened.record.id,
                        status: .accepted,
                        message: "not the sender"
                    )
                ),
                from: a,
                to: b,
                runId: "auth"
            )
        }
        try await expectFailure(.unauthorizedEdge(from: b.id, to: a.id)) {
            _ = try await service.inbox(for: a.id, requestedBy: b.id)
        }
        #expect(try await service.inbox(for: a.id, requestedBy: orchestrator.id).count == 1)
    }

    @Test("depth above 2, cycles, and a second root are rejected")
    func depthAndCycles() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = fixture.service
        _ = try await service.openRun(id: "chain")
        let a = participant(agentA, name: "A")
        let b = participant(agentB, name: "B")
        let c = participant(agentC, name: "C")
        try await service.replaceAllowlist([
            DirectedMailboxEdge(from: a.id, to: b.id),
            DirectedMailboxEdge(from: b.id, to: c.id),
            DirectedMailboxEdge(from: a.id, to: orchestrator.id),
        ])

        try await expectFailure(.cycle(path: [], attempted: orchestrator.id)) {
            _ = try await service.send(
                self.request("self"),
                from: self.orchestrator,
                to: self.orchestrator,
                runId: "chain"
            )
        }

        let first = try await service.send(
            request("one"),
            from: orchestrator,
            to: a,
            runId: "chain",
            createdAt: createdAt
        )
        try await expectFailure(.senderNotAtFrontier(sender: orchestrator.id, expected: a.id)) {
            _ = try await service.send(self.request("second root"), from: self.orchestrator, to: b, runId: "chain")
        }
        let second = try await service.send(
            request("two"),
            from: a,
            to: b,
            runId: "chain",
            parentEnvelopeId: first.record.id,
            createdAt: createdAt.addingTimeInterval(1)
        )
        try await expectFailure(.cycle(path: [orchestrator.id, a.id], attempted: orchestrator.id)) {
            _ = try await service.send(
                self.request("back"),
                from: a,
                to: self.orchestrator,
                runId: "chain",
                parentEnvelopeId: first.record.id
            )
        }
        try await expectFailure(.depthExceeded(depth: 3, limit: 2)) {
            _ = try await service.send(
                self.request("three"),
                from: b,
                to: c,
                runId: "chain",
                parentEnvelopeId: second.record.id
            )
        }

        let reloaded = try DirectedMailboxService(directory: fixture.directory)
        #expect(try await reloaded.inbox(for: c.id, requestedBy: c.id).isEmpty)
        #expect(try await reloaded.openRun(id: "chain").subtasksUsed == 2)
    }

    @Test("token, tool, and subtask caps stop the run; a reply still returns")
    func budgets() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = fixture.service
        let a = participant(agentA, name: "A")
        let b = participant(agentB, name: "B")
        let tight = CollaborationRunLimits(maxTokens: 10, maxToolCalls: 2, maxSubtasks: 1, maxDepth: 2)
        _ = try await service.openRun(id: "budget", limits: tight)
        try await service.replaceAllowlist([DirectedMailboxEdge(from: a.id, to: b.id)])

        let sent = try await service.send(
            request("budgeted"),
            from: orchestrator,
            to: a,
            runId: "budget",
            createdAt: createdAt
        )
        _ = try await service.recordUsage(runId: "budget", tokens: 10, toolCalls: 2)
        try await expectFailure(.tokenCapExceeded(used: 11, limit: 10)) {
            _ = try await service.recordUsage(runId: "budget", tokens: 1, toolCalls: 0)
        }
        try await expectFailure(.tokenCapExceeded(used: 10, limit: 10)) {
            _ = try await service.send(
                self.request("over budget"),
                from: a,
                to: b,
                runId: "budget",
                parentEnvelopeId: sent.record.id
            )
        }
        let reply = try await service.send(
            .reply(
                AgentCollaborationReply(
                    inReplyToEnvelopeId: sent.record.id,
                    status: .completed,
                    message: "done"
                )
            ),
            from: a,
            to: orchestrator,
            runId: "budget",
            createdAt: createdAt.addingTimeInterval(1)
        )
        #expect(reply.run.tokensUsed == 10)
        #expect(reply.run.subtasksUsed == 1)

        let reloaded = try DirectedMailboxService(directory: fixture.directory)
        let stored = try await reloaded.openRun(
            id: "budget",
            limits: CollaborationRunLimits(maxTokens: 1, maxToolCalls: 1, maxSubtasks: 1, maxDepth: 1)
        )
        #expect(stored.tokensUsed == 10)
        #expect(stored.toolCallsUsed == 2)
        #expect(stored.limits.maxTokens == 10)
        #expect(try await reloaded.inbox(for: orchestrator.id, requestedBy: orchestrator.id).count == 1)

        let blockedTools = try DirectedMailboxService(
            directory: fixture.directory.appendingPathComponent("tools", isDirectory: true)
        )
        _ = try await blockedTools.openRun(
            id: "tools",
            limits: CollaborationRunLimits(maxTokens: 100, maxToolCalls: 0, maxSubtasks: 4, maxDepth: 2)
        )
        try await expectFailure(.toolCapExceeded(used: 0, limit: 0)) {
            _ = try await blockedTools.send(
                self.request("no tools"),
                from: self.orchestrator,
                to: a,
                runId: "tools"
            )
        }
        #expect(try await blockedTools.inbox(for: a.id, requestedBy: a.id).isEmpty)

        _ = try await service.openRun(
            id: "subtasks",
            limits: CollaborationRunLimits(maxTokens: 100, maxToolCalls: 10, maxSubtasks: 1, maxDepth: 2)
        )
        let only = try await service.send(
            request("only subtask"),
            from: orchestrator,
            to: a,
            runId: "subtasks",
            createdAt: createdAt
        )
        try await expectFailure(.subtaskCapExceeded(used: 2, limit: 1)) {
            _ = try await service.send(
                self.request("extra"),
                from: a,
                to: b,
                runId: "subtasks",
                parentEnvelopeId: only.record.id
            )
        }
        #expect(try await service.openRun(id: "subtasks").subtasksUsed == 1)
    }

    @Test("bot-domain memory reuses the agent partition and global stays shared")
    func memoryLayers() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let previousRoot = OsaurusPaths.overrideRoot
        let root = fixture.directory.appendingPathComponent("app-root", isDirectory: true)
        OsaurusPaths.overrideRoot = root
        defer { OsaurusPaths.overrideRoot = previousRoot }

        let global = try fixture.service.memoryGrant(reader: agentA, layer: .global)
        #expect(global.vectorPartitionKey.isEmpty)
        #expect(global.agentDatabaseFile == nil)

        let own = try fixture.service.memoryGrant(reader: agentA, layer: .botDomain(agentA))
        #expect(own.vectorPartitionKey == MemoryNamespace.agent(agentA).key)
        #expect(own.agentDatabaseFile == OsaurusPaths.agentDatabaseFile(for: agentA))
        if let path = own.agentDatabaseFile?.path {
            #expect(!FileManager.default.fileExists(atPath: path))
        } else {
            Issue.record("bot domain grant missing agent database path")
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("plugin-bot-memory").path))
        let mailboxFile = OsaurusPaths.directedMailboxFile()
        #expect(mailboxFile.lastPathComponent == DirectedMailboxSchema.fileName)
        #expect(mailboxFile.path.contains("/collaboration/"))
        #expect(!mailboxFile.path.contains("/agents/"))

        #expect(throws: DirectedMailboxError.crossAgentMemoryDenied(reader: agentA, owner: agentB)) {
            try fixture.service.memoryGrant(reader: self.agentA, layer: .botDomain(self.agentB))
        }
        #expect(throws: DirectedMailboxError.parallelMemoryStoreForbidden("plugin-bot-memory")) {
            try DirectedMailboxMemoryPartition.requireExisting(partitionKey: "plugin-bot-memory")
        }
        let alias = agentA.uuidString.lowercased()
        #expect(alias != MemoryNamespace.agent(agentA).key)
        #expect(throws: DirectedMailboxError.parallelMemoryStoreForbidden(alias)) {
            try DirectedMailboxMemoryPartition.requireExisting(partitionKey: alias)
        }
        let project = MemoryNamespace.project(agentC).key
        #expect(throws: DirectedMailboxError.parallelMemoryStoreForbidden(project)) {
            try DirectedMailboxMemoryPartition.requireExisting(partitionKey: project)
        }
    }

    @Test("a tampered trust bit cannot stick, and depth cannot be raised on disk")
    func tamperAndCeiling() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = fixture.service
        _ = try await service.openRun(id: "tamper")
        _ = try await service.send(
            request("stored"),
            from: orchestrator,
            to: participant(agentA, name: "A"),
            runId: "tamper",
            createdAt: createdAt
        )

        var text = try String(contentsOf: service.fileURL, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"contentUntrusted\":true", with: "\"contentUntrusted\":false")
        try text.write(to: service.fileURL, atomically: true, encoding: .utf8)
        let coerced = try DirectedMailboxService(directory: fixture.directory)
        let mail = try await coerced.inbox(
            for: participant(agentA, name: "A").id,
            requestedBy: orchestrator.id
        )
        #expect(mail.count == 1)
        #expect(mail[0].contentUntrusted)

        text = try String(contentsOf: service.fileURL, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"maxDepth\":2", with: "\"maxDepth\":9")
        try text.write(to: service.fileURL, atomically: true, encoding: .utf8)
        let clamped = try DirectedMailboxService(directory: fixture.directory)
        #expect(try await clamped.openRun(id: "tamper").limits.maxDepth == CollaborationRunLimits.depthCeiling)

        text = try String(contentsOf: clamped.fileURL, encoding: .utf8)
        text = text.replacingOccurrences(
            of: AgentCollaborationProtocolContract.schema,
            with: "osaurus.agent-collaboration.v9"
        )
        try text.write(to: clamped.fileURL, atomically: true, encoding: .utf8)
        try await expectFailure(.untrustedEnvelopeRejected("osaurus.agent-collaboration.v9")) {
            _ = try DirectedMailboxService(directory: fixture.directory)
        }
    }

    private var orchestrator: AgentCollaborationParticipant {
        AgentCollaborationParticipant(
            id: DirectedMailboxPolicy.orchestratorParticipantId,
            type: .local,
            displayName: "Orchestrator"
        )
    }

    private func participant(_ id: UUID, name: String) -> AgentCollaborationParticipant {
        AgentCollaborationParticipant(
            id: "local:\(id.uuidString.lowercased())",
            type: .local,
            displayName: name
        )
    }

    private func request(_ objective: String) -> AgentCollaborationEvent {
        .request(AgentCollaborationRequest(title: "mailbox", objective: objective))
    }

    private func expectFailure(
        _ expected: DirectedMailboxError,
        _ body: () async throws -> Void
    ) async throws {
        do {
            try await body()
            Issue.record("expected \(expected)")
        } catch let error as DirectedMailboxError {
            #expect(error == expected)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    private struct Fixture {
        let directory: URL
        let service: DirectedMailboxService

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "directed-mailbox-\(UUID().uuidString)",
                isDirectory: true
            )
            service = try DirectedMailboxService(directory: directory)
        }

        func cleanup() {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch let error {
                // 目录可能已被删掉。清理失败不影响断言。
                _ = error
            }
        }
    }
}
