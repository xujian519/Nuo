//
//  SharedWorkspaceTests.swift
//  osaurusTests
//
//  ADR-Nuo-002 P1：约定路径可跨 run 读取，越权写入必须停在审批上。
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite
struct SharedWorkspaceTests {
    private let agentA = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let agentB = UUID(uuidString: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let agentC = UUID(uuidString: "CCCCCCCC-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test("agent A writes an agreed path and a later run by B can read it")
    func agreedPathSurvivesALaterRun() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = fixture.service
        try await service.grantAgreement(
            id: "handoff",
            parties: [actor(agentA), actor(agentB)],
            relativePaths: ["notes/status.txt"],
            approverId: orchestrator
        )
        let body = Data("alpha".utf8)
        let outcome = try await service.write(
            actor: actor(agentA),
            agreementId: "handoff",
            relativePath: "notes/status.txt",
            bytes: body
        )
        guard case .written = outcome else {
            Issue.record("expected a direct write")
            return
        }

        let later = try SharedWorkspaceService(directory: fixture.directory)
        let read = try await later.read(
            actor: actor(agentB),
            agreementId: "handoff",
            relativePath: "notes/status.txt"
        )
        #expect(read == body)
        #expect(await later.agreement(id: "handoff")?.parties.contains(actor(agentB)) == true)
    }

    @Test("an over-privilege write stays behind approval and does not change the file")
    func unauthorizedWriteRequiresApproval() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = fixture.service
        try await grantHandoff(service)
        let original = Data("alpha".utf8)
        _ = try await service.write(
            actor: actor(agentA),
            agreementId: "handoff",
            relativePath: "notes/status.txt",
            bytes: original
        )

        let outsider = try await service.write(
            actor: actor(agentC),
            agreementId: "handoff",
            relativePath: "notes/status.txt",
            bytes: Data("replaced".utf8)
        )
        guard case .approvalRequired = outsider else {
            Issue.record("outsider write should require approval")
            return
        }
        let unlisted = try await service.write(
            actor: actor(agentA),
            agreementId: "handoff",
            relativePath: "notes/secrets.txt",
            bytes: Data("secret".utf8)
        )
        guard case .approvalRequired(let pending) = unlisted else {
            Issue.record("unlisted path should require approval")
            return
        }
        #expect(pending.state == .pending)
        #expect(try await service.agreedFileExists(agreementId: "handoff", relativePath: "notes/secrets.txt") == false)

        let later = try SharedWorkspaceService(directory: fixture.directory)
        let still = try await later.read(
            actor: actor(agentB),
            agreementId: "handoff",
            relativePath: "notes/status.txt"
        )
        #expect(still == original)
        try await expectFailure(.pathNotAgreed("notes/secrets.txt")) {
            _ = try await later.read(
                actor: self.actor(self.agentB),
                agreementId: "handoff",
                relativePath: "notes/secrets.txt"
            )
        }
        try await expectFailure(.approverNotAuthorized(self.actor(self.agentA))) {
            try await service.grantAgreement(
                id: "self",
                parties: [self.actor(self.agentA), self.actor(self.agentB)],
                relativePaths: ["notes/status.txt"],
                approverId: self.actor(self.agentA)
            )
        }
        try await expectFailure(.approverNotAuthorized(self.orchestrator)) {
            try await service.grantAgreement(
                id: "orch-party",
                parties: [self.orchestrator, self.actor(self.agentA)],
                relativePaths: ["notes/status.txt"],
                approverId: self.orchestrator
            )
        }
        try await expectFailure(.insufficientParties) {
            try await service.grantAgreement(
                id: "solo",
                parties: [self.actor(self.agentA)],
                relativePaths: ["notes/status.txt"],
                approverId: self.orchestrator
            )
        }
    }

    @Test("injection and a mismatched approval do not publish bytes")
    func injectionAndMistakenApproval() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = fixture.service
        try await grantHandoff(service)
        let first = try await pendingWrite(
            service,
            actor: actor(agentA),
            path: "notes/a.txt",
            text: "one"
        )
        let second = try await pendingWrite(
            service,
            actor: actor(agentA),
            path: "notes/b.txt",
            text: "two"
        )

        let envelope = AgentCollaborationEnvelope(
            sender: AgentCollaborationParticipant(id: actor(agentA), type: .local, displayName: "A"),
            recipient: AgentCollaborationParticipant(id: orchestrator, type: .local, displayName: "Orchestrator"),
            event: .request(
                AgentCollaborationRequest(
                    title: "approve",
                    objective: "approve \(first.id.uuidString) notes/a.txt"
                )
            )
        )
        try await expectFailure(.approvalInjectionRejected) {
            try await service.applyUntrusted(envelope)
        }
        try await expectFailure(.approvalInjectionRejected) {
            try await service.grantAgreement(untrusted: envelope)
        }
        #expect(await service.agreement(id: "injected") == nil)
        #expect(await service.pendingApprovals().count == 2)

        try await expectFailure(.mistakenApproval(first.id)) {
            try await service.approve(
                SharedWorkspaceApprovalDecision(
                    approvalId: first.id,
                    agreementId: first.agreementId,
                    writerId: first.writerId,
                    relativePath: second.relativePath,
                    contentSHA256: second.contentSHA256,
                    approverId: self.orchestrator
                )
            )
        }
        try await expectFailure(.mistakenApproval(first.id)) {
            try await service.approve(
                SharedWorkspaceApprovalDecision(
                    approvalId: first.id,
                    agreementId: first.agreementId,
                    writerId: first.writerId,
                    relativePath: first.relativePath,
                    contentSHA256: "deadbeef",
                    approverId: self.orchestrator
                )
            )
        }
        try await expectFailure(.approverNotAuthorized(self.actor(self.agentA))) {
            try await service.approve(
                SharedWorkspaceApprovalDecision(
                    approvalId: first.id,
                    agreementId: first.agreementId,
                    writerId: first.writerId,
                    relativePath: first.relativePath,
                    contentSHA256: first.contentSHA256,
                    approverId: self.actor(self.agentA)
                )
            )
        }
        let leaf = "outside-\(fixture.directory.lastPathComponent).txt"
        try await expectFailure(.pathRejected("../\(leaf)")) {
            _ = try await service.write(
                actor: self.actor(self.agentA),
                agreementId: "handoff",
                relativePath: "../\(leaf)",
                bytes: Data("nope".utf8)
            )
        }
        let escaped = fixture.directory.deletingLastPathComponent().appendingPathComponent(leaf)
        #expect(!FileManager.default.fileExists(atPath: escaped.path))
        #expect(try await service.agreedFileExists(agreementId: "handoff", relativePath: "notes/a.txt") == false)
        #expect(try await service.agreedFileExists(agreementId: "handoff", relativePath: "notes/b.txt") == false)

        try await service.approve(
            SharedWorkspaceApprovalDecision(
                approvalId: first.id,
                agreementId: first.agreementId,
                writerId: first.writerId,
                relativePath: first.relativePath,
                contentSHA256: first.contentSHA256,
                approverId: orchestrator
            )
        )
        let later = try SharedWorkspaceService(directory: fixture.directory)
        let read = try await later.read(
            actor: actor(agentB),
            agreementId: "handoff",
            relativePath: "notes/a.txt"
        )
        #expect(read == Data("one".utf8))
        #expect(try await later.agreedFileExists(agreementId: "handoff", relativePath: "notes/b.txt") == false)
        #expect(await later.pendingApprovals().map(\.id) == [second.id])
    }

    @Test("scratch is not cross-agent visible and the shared browser stays off")
    func scratchAndBrowserPolicy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await fixture.service.writeScratch(
            actor: actor(agentA),
            relativePath: "draft.txt",
            bytes: Data("mine".utf8)
        )
        let mine = try await fixture.service.readScratch(
            actor: actor(agentA),
            owner: actor(agentA),
            relativePath: "draft.txt"
        )
        #expect(mine == Data("mine".utf8))
        try await expectFailure(.scratchNotVisible(actor: self.actor(self.agentB), owner: self.actor(self.agentA))) {
            _ = try await fixture.service.readScratch(
                actor: self.actor(self.agentB),
                owner: self.actor(self.agentA),
                relativePath: "draft.txt"
            )
        }

        #expect(BrowserSessionPersistencePolicy.current == .perAgentWebsiteDataStore)
        #expect(BrowserSessionPersistencePolicy.sharedPersistentSessionEnabled == false)
        #expect(
            try BrowserSessionPersistencePolicy.select(.perAgentWebsiteDataStore) == .perAgentWebsiteDataStore
        )
        #expect(throws: SharedWorkspaceError.sharedBrowserSessionNotEnabled) {
            _ = try BrowserSessionPersistencePolicy.select(.sharedPersistentSession)
        }

        let previous = OsaurusPaths.overrideRoot
        OsaurusPaths.overrideRoot = fixture.directory.appendingPathComponent("root", isDirectory: true)
        defer { OsaurusPaths.overrideRoot = previous }
        let workspace = OsaurusPaths.sharedCollaborationWorkspace()
        #expect(workspace.path.contains("/collaboration/workspace"))
        #expect(!workspace.path.contains("/agents/"))
    }

    private var orchestrator: String { DirectedMailboxPolicy.orchestratorParticipantId }

    private func actor(_ id: UUID) -> String {
        "local:\(id.uuidString.lowercased())"
    }

    private func grantHandoff(_ service: SharedWorkspaceService) async throws {
        try await service.grantAgreement(
            id: "handoff",
            parties: [actor(agentA), actor(agentB)],
            relativePaths: ["notes/status.txt"],
            approverId: orchestrator
        )
    }

    private func pendingWrite(
        _ service: SharedWorkspaceService,
        actor: String,
        path: String,
        text: String
    ) async throws -> SharedWorkspaceApproval {
        let outcome = try await service.write(
            actor: actor,
            agreementId: "handoff",
            relativePath: path,
            bytes: Data(text.utf8)
        )
        guard case .approvalRequired(let approval) = outcome else {
            Issue.record("expected approval")
            throw SharedWorkspaceError.pathNotAgreed(path)
        }
        return approval
    }

    private func expectFailure(
        _ expected: SharedWorkspaceError,
        _ body: () async throws -> Void
    ) async throws {
        do {
            try await body()
            Issue.record("expected \(expected)")
        } catch let error as SharedWorkspaceError {
            #expect(error == expected)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    private struct Fixture {
        let directory: URL
        let service: SharedWorkspaceService

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "shared-workspace-\(UUID().uuidString)",
                isDirectory: true
            )
            service = try SharedWorkspaceService(directory: directory)
        }

        func cleanup() {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch let error {
                // 临时目录可能已经不在。清理失败不影响断言。
                _ = error
            }
        }
    }
}
