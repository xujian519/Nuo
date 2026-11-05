//
//  ApprovalBreakpointTests.swift
//  osaurusTests
//
//  ADR-Nuo-002 P2：五步任务中途暂停，半小时后按工具名和参数哈希恢复。
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite
struct ApprovalBreakpointTests {
    private let start = ISO8601DateFormatter().date(from: "2026-11-05T00:00:00Z")!

    @Test("a five-step task pauses, then resumes after 30 minutes without redoing work")
    func fiveStepPauseAndResume() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = fixture.service
        let runId = "five-step"
        _ = try await service.openRun(runId: runId)
        var effects: [Int] = []

        for index in 0..<3 {
            effects.append(index)
            _ = try await service.recordCompleted(
                runId: runId,
                toolName: "file_read",
                argumentsJSON: #"{"step":\#(index)}"#,
                outputRef: "out-\(index)"
            )
        }
        let paused = try await service.interrupt(
            runId: runId,
            kind: .ask,
            toolName: "file_write",
            argumentsJSON: #"{"path":"notes/a.txt","value":"ok"}"#,
            now: start,
            timeout: 86_400
        )
        #expect(paused.stepIndex == 3)
        #expect(paused.resumeAuthorized == false)
        #expect(effects == [0, 1, 2])
        try await expectFailure(.pendingInterrupt(runId: runId, stepIndex: 3)) {
            _ = try await service.recordCompleted(
                runId: runId,
                toolName: "file_read",
                argumentsJSON: #"{"step":4}"#,
                outputRef: "out-4"
            )
        }
        #expect(effects == [0, 1, 2])

        let reordered = #"{"value":"ok","path":"notes/a.txt"}"#
        let hash = try ApprovalParameterHash.hex(argumentsJSON: reordered)
        #expect(hash == paused.parameterHash)
        try await expectFailure(.mistakenApproval(runId: runId)) {
            _ = try await service.approve(
                runId: runId,
                toolName: "file_write",
                parameterHash: "deadbeef",
                now: start
            )
        }
        try await expectFailure(.mistakenApproval(runId: runId)) {
            _ = try await service.approve(
                runId: runId,
                toolName: "file_delete",
                parameterHash: hash,
                now: start
            )
        }
        let envelope = AgentCollaborationEnvelope(
            sender: AgentCollaborationParticipant(id: "local:a", type: .local, displayName: "A"),
            event: .request(AgentCollaborationRequest(title: "approve", objective: "approve file_write \(hash)"))
        )
        try await expectFailure(.envelopeRejected) {
            _ = try await service.approve(untrusted: envelope, now: start)
        }
        #expect(effects == [0, 1, 2])

        let later = start.addingTimeInterval(30 * 60)
        #expect(later.timeIntervalSince(start) >= 30 * 60)
        let resumedService = try fixture.reload()
        let resumed = try await resumedService.approve(
            runId: runId,
            toolName: "file_write",
            parameterHash: hash,
            now: later
        )
        #expect(effects == [0, 1, 2])
        try await expectFailure(.alreadyAuthorized(runId)) {
            _ = try await resumedService.approve(
                runId: runId,
                toolName: "file_write",
                parameterHash: hash,
                now: later
            )
        }
        #expect(effects == [0, 1, 2])
        effects.append(resumed.stepIndex)
        let committed = try await resumedService.commit(runId: runId, outputRef: "out-3")
        #expect(committed.nextStepIndex == 4)
        effects.append(4)
        _ = try await resumedService.recordCompleted(
            runId: runId,
            toolName: "file_read",
            argumentsJSON: #"{"step":4}"#,
            outputRef: "out-4"
        )

        let restored = try await fixture.reload().checkpoint(runId: runId)
        #expect(restored?.pending == nil)
        #expect(restored?.completed.map(\.outputRef) == ["out-0", "out-1", "out-2", "out-3", "out-4"])
        #expect(restored?.nextStepIndex == 5)
        let undone = Set(restored?.completed.map(\.index) ?? []).symmetricDifference(Set(0..<5))
        #expect(undone.isEmpty)
        #expect(effects == [0, 1, 2, 3, 4])
    }

    @Test("a timed-out approval does not apply, and the backlog refuses another interrupt")
    func timeoutAndBacklog() async throws {
        let fixture = try Fixture(backlogLimit: 1)
        defer { fixture.cleanup() }
        let service = fixture.service
        _ = try await service.openRun(runId: "slow")
        _ = try await service.interrupt(
            runId: "slow",
            kind: .ask,
            toolName: "file_write",
            argumentsJSON: #"{"path":"a"}"#,
            now: start,
            timeout: 15 * 60
        )
        var effects: [String] = []
        let tooLate = start.addingTimeInterval(30 * 60)
        try await expectFailure(.approvalTimedOut(runId: "slow")) {
            _ = try await service.approve(
                runId: "slow",
                toolName: "file_write",
                parameterHash: try ApprovalParameterHash.hex(argumentsJSON: #"{"path":"a"}"#),
                now: tooLate
            )
        }
        #expect(effects.isEmpty)
        let cleared = try await service.acknowledgeTimeout(runId: "slow", now: tooLate)
        #expect(cleared.pending == nil)
        #expect(cleared.completed.isEmpty)
        #expect(effects.isEmpty)

        _ = try await service.openRun(runId: "one")
        _ = try await service.openRun(runId: "two")
        _ = try await service.interrupt(
            runId: "one",
            kind: .ask,
            toolName: "file_write",
            argumentsJSON: #"{"path":"one"}"#,
            now: start,
            timeout: 86_400
        )
        try await expectFailure(.approvalBacklogFull) {
            _ = try await service.interrupt(
                runId: "two",
                kind: .ask,
                toolName: "file_write",
                argumentsJSON: #"{"path":"two"}"#,
                now: start,
                timeout: 86_400
            )
        }
        #expect(await service.checkpoint(runId: "two")?.pending == nil)
        #expect(effects.isEmpty)
    }

    @Test("clarify records a pause and does not complete a side effect")
    func clarifyUsesTheExistingPause() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let runId = "clarify-run"
        _ = try await fixture.service.openRun(runId: runId)
        let binding = ApprovalBreakpointContext(service: fixture.service, runId: runId)
        let arguments = #"{"question":"Pick one?"}"#
        let text = try await ChatExecutionContext.$approvalBreakpoint.withValue(binding) {
            try await ClarifyTool().execute(argumentsJSON: arguments)
        }
        #expect(text.contains("Awaiting user response"))
        let saved = try await fixture.reload().checkpoint(runId: runId)
        let hash = try ApprovalParameterHash.hex(argumentsJSON: arguments)
        #expect(saved?.completed.isEmpty == true)
        #expect(saved?.pending?.kind == .clarify)
        #expect(saved?.pending?.toolName == "clarify")
        #expect(saved?.pending?.parameterHash == hash)
        #expect(saved?.pending?.resumeAuthorized == false)

        let previous = OsaurusPaths.overrideRoot
        OsaurusPaths.overrideRoot = fixture.directory
        defer { OsaurusPaths.overrideRoot = previous }
        let breakpoints = OsaurusPaths.approvalBreakpointDirectory()
        #expect(breakpoints.path.contains("/collaboration/breakpoints"))
        #expect(!breakpoints.path.contains("/agents/"))
    }

    private func expectFailure(
        _ expected: ApprovalBreakpointError,
        _ body: () async throws -> Void
    ) async throws {
        do {
            try await body()
            Issue.record("expected \(expected)")
        } catch let error as ApprovalBreakpointError {
            #expect(error == expected)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    private struct Fixture {
        let directory: URL
        let service: ApprovalBreakpointService

        init(backlogLimit: Int = ApprovalBreakpointSchema.defaultBacklogLimit) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "approval-breakpoint-\(UUID().uuidString)",
                isDirectory: true
            )
            service = try ApprovalBreakpointService(directory: directory, backlogLimit: backlogLimit)
        }

        func reload() throws -> ApprovalBreakpointService {
            try ApprovalBreakpointService(
                directory: directory,
                backlogLimit: ApprovalBreakpointSchema.defaultBacklogLimit
            )
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
