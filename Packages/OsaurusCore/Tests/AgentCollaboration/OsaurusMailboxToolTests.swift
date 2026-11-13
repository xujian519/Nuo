//
//  OsaurusMailboxToolTests.swift
//  osaurusTests
//
//  ADR-Nuo-002 mailbox 工具层：`osaurus_mailbox` 的参数校验、错误映射、
//  准入转发与 untrusted 契约。服务语义本身由 DirectedMailboxTests 覆盖，
//  这里只证明工具把它无损地暴露给模型：入参失败走 invalid_args，未知或
//  重名的显示名走 unknown_agent / ambiguous_agent，服务错误映射成带
//  error_code 的分类失败，成功路径真实落盘且 inbox 条目永远携带
//  untrusted 标记。
//
//  隔离方案：fixture 把 `OsaurusPaths.overrideRoot` 指到临时目录（agent 注册
//  不碰用户真实 store），`DirectedMailboxCoordinator(service:)` 测试缝把邮箱
//  绑到临时目录（不碰用户级 mailbox 文件），`@TaskLocal coordinatorOverrideForTests`
//  让工具解析到这个隔离 coordinator。
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite(.serialized)
struct OsaurusMailboxToolTests {

    // MARK: - 上下文与参数校验

    @Test("no chat session context makes the tool unavailable")
    func requiresChatContext() async throws {
        let dict = try await raw(OsaurusMailboxTool().execute(argumentsJSON: "{}"))
        #expect(dict["ok"] as? Bool == false)
        #expect(dict["kind"] as? String == "unavailable")
        #expect(dict["tool"] as? String == "osaurus_mailbox")
        #expect(dict["retryable"] as? Bool == false)
    }

    @Test("malformed arguments and unknown actions are invalid_args")
    func argumentValidation() async throws {
        // 参数解析在 caller/coordinator 解析之前，任何 UUID 都可作 caller。
        let caller = UUID()
        let notJSON = try await raw(
            ChatExecutionContext.$currentAgentId.withValue(caller) {
                try await OsaurusMailboxTool().execute(argumentsJSON: "not json")
            }
        )
        expectFailure(notJSON, kind: "invalid_args")

        let missingAction = try await runBare(caller: caller, arguments: ["text": "hi"])
        expectFailure(missingAction, kind: "invalid_args")

        let badAction = try await runBare(caller: caller, arguments: ["action": "delete"])
        expectFailure(badAction, kind: "invalid_args")
    }

    @Test("send validates target, text, and parent envelope id")
    func sendTargetValidation() async throws {
        try await withFixture { fixture in
            let badTo = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: ["action": "send", "to": "not-a-uuid", "text": "hi"]
            )
            expectFailure(
                badTo, kind: "not_found", errorCode: "unknown_agent", field: "to", retryable: false
            )

            let missing = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: ["action": "send", "to": UUID().uuidString, "text": "hi"]
            )
            expectFailure(missing, kind: "not_found", field: "to", retryable: false)

            let noText = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: ["action": "send", "to": fixture.agentB.id.uuidString]
            )
            expectFailure(noText, kind: "invalid_args", field: "text")

            let badParent = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: [
                    "action": "send",
                    "to": fixture.agentB.id.uuidString,
                    "text": "hi",
                    "parent_envelope_id": "xyz",
                ]
            )
            expectFailure(badParent, kind: "invalid_args", field: "parent_envelope_id")
        }
    }

    // MARK: - 准入与成功路径

    @Test("orchestrator send persists an untrusted envelope")
    func orchestratorSendPersists() async throws {
        try await withFixture { fixture in
            let dict = try await run(
                fixture, caller: Agent.defaultId,
                arguments: [
                    "action": "send",
                    "to": fixture.agentA.id.uuidString,
                    "text": "hello mailbox",
                    "summary": "greet",
                ]
            )
            #expect(dict["ok"] as? Bool == true)
            let result = try #require(dict["result"] as? [String: Any])
            let envelopeId = try #require(result["envelope_id"] as? String)
            #expect(UUID(uuidString: envelopeId) != nil)
            #expect(!(result["run_id"] as? String ?? "").isEmpty)
            #expect(result["from"] as? String == pid(Agent.defaultId))
            #expect(result["to"] as? String == pid(fixture.agentA.id))
            #expect(result["delivered"] as? Bool == true)

            // 交叉验证：服务真的落了盘，且 body 保持 untrusted。
            let inbox = try await fixture.service.inbox(
                for: pid(fixture.agentA.id), requestedBy: pid(fixture.agentA.id))
            #expect(inbox.count == 1)
            #expect(inbox[0].contentUntrusted)
            #expect(inbox[0].untrustedText().text == "hello mailbox")
            #expect(inbox[0].untrustedText().trusted == false)
        }
    }

    @Test("allowlisted agents exchange mail")
    func allowlistedSend() async throws {
        try await withFixture { fixture in
            await fixture.coordinator.addEdge(from: pid(fixture.agentA.id), to: pid(fixture.agentB.id))
            let dict = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: [
                    "action": "send",
                    "to": fixture.agentB.id.uuidString,
                    "text": "ping",
                ]
            )
            #expect(dict["ok"] as? Bool == true)
            let inbox = try await fixture.service.inbox(
                for: pid(fixture.agentB.id), requestedBy: pid(fixture.agentB.id))
            #expect(inbox.count == 1)
            #expect(inbox[0].untrustedText().text == "ping")
        }
    }

    @Test("a display name sends, and inbox accepts that name")
    func sendAndInboxByDisplayName() async throws {
        try await withFixture { fixture in
            let writer = Agent(name: "作家")
            await MainActor.run { AgentManager.shared.add(writer) }
            await fixture.coordinator.addEdge(
                from: pid(writer.id), to: pid(fixture.agentB.id))

            let sent = try await run(
                fixture, caller: writer.id,
                arguments: ["action": "send", "to": "mailbox b", "text": "by name"]
            )
            #expect(sent["ok"] as? Bool == true)

            let inbox = try await run(
                fixture, caller: Agent.defaultId,
                arguments: ["action": "inbox", "agent_id": "Mailbox B"]
            )
            #expect(inbox["ok"] as? Bool == true)
            let result = try #require(inbox["result"] as? [String: Any])
            #expect(result["count"] as? Int == 1)
            let entries = try #require(result["entries"] as? [[String: Any]])
            #expect(entries.first?["text"] as? String == "by name")
        }
    }

    @Test("an unknown display name does not deliver")
    func unknownDisplayName() async throws {
        try await withFixture { fixture in
            let dict = try await run(
                fixture, caller: Agent.defaultId,
                arguments: ["action": "send", "to": "没有这个人", "text": "hi"]
            )
            expectFailure(
                dict, kind: "not_found", errorCode: "unknown_agent", field: "to", retryable: false
            )
            #expect((dict["message"] as? String)?.contains("Mailbox A") == true)
            let inbox = try await fixture.service.inbox(
                for: pid(fixture.agentA.id), requestedBy: pid(fixture.agentA.id))
            #expect(inbox.isEmpty)
        }
    }

    @Test("a duplicated display name is refused without guessing")
    func ambiguousDisplayName() async throws {
        try await withFixture { fixture in
            let first = Agent(name: "作家")
            let second = Agent(name: "作家")
            await MainActor.run {
                AgentManager.shared.add(first)
                AgentManager.shared.add(second)
            }

            let dict = try await run(
                fixture, caller: Agent.defaultId,
                arguments: ["action": "send", "to": "作家", "text": "which one"]
            )
            expectFailure(
                dict, kind: "invalid_args", errorCode: "ambiguous_agent", field: "to"
            )
            let message = try #require(dict["message"] as? String)
            #expect(message.contains(first.id.uuidString))
            #expect(message.contains(second.id.uuidString))
            let inbox = try await fixture.service.inbox(
                for: pid(first.id), requestedBy: pid(Agent.defaultId))
            #expect(inbox.isEmpty)
        }
    }

    @Test("the orchestrator can send by name without an allowlist edge")
    func orchestratorSendsByName() async throws {
        try await withFixture { fixture in
            let dict = try await run(
                fixture, caller: Agent.defaultId,
                arguments: ["action": "send", "to": "Mailbox A", "text": "direct"]
            )
            #expect(dict["ok"] as? Bool == true)
            let inbox = try await fixture.service.inbox(
                for: pid(fixture.agentA.id), requestedBy: pid(fixture.agentA.id))
            #expect(inbox.count == 1)
            #expect(inbox[0].untrustedText().text == "direct")
        }
    }

    @Test("a resolved name still needs an allowlist edge")
    func nameWithoutEdgeIsUnauthorized() async throws {
        try await withFixture { fixture in
            let dict = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: ["action": "send", "to": "Mailbox C", "text": "side channel"]
            )
            expectFailure(
                dict, kind: "rejected", errorCode: "unauthorized_edge", retryable: false)
            #expect(dict["to"] as? String == pid(fixture.agentC.id))
        }
    }

    @Test("send without an allowlist edge is rejected with unauthorized_edge")
    func unauthorizedEdgeRejected() async throws {
        try await withFixture { fixture in
            let dict = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: [
                    "action": "send",
                    "to": fixture.agentC.id.uuidString,
                    "text": "side channel",
                ]
            )
            expectFailure(
                dict, kind: "rejected", errorCode: "unauthorized_edge", retryable: false)
            #expect(dict["from"] as? String == pid(fixture.agentA.id))
            #expect(dict["to"] as? String == pid(fixture.agentC.id))
        }
    }

    @Test("reply returns to the previous hop; unknown envelopes are not_found")
    func replyRoundTrip() async throws {
        try await withFixture { fixture in
            let sent = try await run(
                fixture, caller: Agent.defaultId,
                arguments: [
                    "action": "send",
                    "to": fixture.agentA.id.uuidString,
                    "text": "question",
                ]
            )
            let result = try #require(sent["result"] as? [String: Any])
            let envelopeId = try #require(result["envelope_id"] as? String)

            // reply 不需要 allowlist edge——只能回上一跳。
            let replied = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: ["action": "reply", "envelope_id": envelopeId, "text": "answer"]
            )
            #expect(replied["ok"] as? Bool == true)

            let orchestratorInbox = try await fixture.service.inbox(
                for: pid(Agent.defaultId), requestedBy: pid(Agent.defaultId))
            #expect(orchestratorInbox.count == 1)
            #expect(orchestratorInbox[0].untrustedText().text == "answer")
            guard case .reply = orchestratorInbox[0].envelope.event else {
                Issue.record("expected a reply envelope")
                return
            }

            let unknown = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: [
                    "action": "reply",
                    "envelope_id": UUID().uuidString,
                    "text": "nobody",
                ]
            )
            expectFailure(
                unknown, kind: "not_found", errorCode: "unknown_envelope",
                field: "envelope_id", retryable: false)
        }
    }

    // MARK: - inbox 契约

    @Test("inbox defaults to the caller and marks every entry untrusted")
    func inboxSelfContract() async throws {
        try await withFixture { fixture in
            _ = try await run(
                fixture, caller: Agent.defaultId,
                arguments: [
                    "action": "send",
                    "to": fixture.agentA.id.uuidString,
                    "text": "body-text",
                ]
            )
            let dict = try await run(
                fixture, caller: fixture.agentA.id, arguments: ["action": "inbox"])
            #expect(dict["ok"] as? Bool == true)
            let result = try #require(dict["result"] as? [String: Any])
            #expect(result["owner"] as? String == pid(fixture.agentA.id))
            #expect(result["count"] as? Int == 1)
            let entries = try #require(result["entries"] as? [[String: Any]])
            let entry = try #require(entries.first)
            #expect(UUID(uuidString: entry["envelope_id"] as? String ?? "") != nil)
            #expect(!(entry["run_id"] as? String ?? "").isEmpty)
            #expect(entry["from"] as? String == pid(Agent.defaultId))
            #expect(entry["kind"] as? String == "request")
            #expect(entry["text"] as? String == "body-text")
            #expect(entry["untrusted"] as? Bool == true)
            let warnings = try #require(dict["warnings"] as? [String])
            #expect(warnings.contains { $0.contains("untrusted") })
        }
    }

    @Test("cross-agent inbox reads are gated; only the orchestrator may pass")
    func inboxCrossReadGated() async throws {
        try await withFixture { fixture in
            _ = try await run(
                fixture, caller: Agent.defaultId,
                arguments: [
                    "action": "send",
                    "to": fixture.agentA.id.uuidString,
                    "text": "for a",
                ]
            )
            let denied = try await run(
                fixture, caller: fixture.agentB.id,
                arguments: ["action": "inbox", "agent_id": fixture.agentA.id.uuidString]
            )
            expectFailure(denied, kind: "rejected", errorCode: "unauthorized_edge", retryable: false)
            #expect(denied["from"] as? String == pid(fixture.agentB.id))
            #expect(denied["to"] as? String == pid(fixture.agentA.id))

            let granted = try await run(
                fixture, caller: Agent.defaultId,
                arguments: ["action": "inbox", "agent_id": fixture.agentA.id.uuidString]
            )
            #expect(granted["ok"] as? Bool == true)
            #expect((granted["result"] as? [String: Any])?["count"] as? Int == 1)

            let badOwner = try await run(
                fixture, caller: fixture.agentB.id,
                arguments: ["action": "inbox", "agent_id": "nope"]
            )
            expectFailure(
                badOwner, kind: "not_found", errorCode: "unknown_agent", field: "agent_id",
                retryable: false
            )
        }
    }

    // MARK: - 深度、环与预算

    @Test("cycles and depth above 2 are execution errors")
    func depthAndCycleEnforced() async throws {
        try await withFixture { fixture in
            await fixture.coordinator.addEdge(from: pid(fixture.agentA.id), to: pid(fixture.agentB.id))
            await fixture.coordinator.addEdge(from: pid(fixture.agentB.id), to: pid(fixture.agentC.id))
            await fixture.coordinator.addEdge(from: pid(fixture.agentA.id), to: pid(Agent.defaultId))

            let first = try await run(
                fixture, caller: Agent.defaultId,
                arguments: [
                    "action": "send",
                    "to": fixture.agentA.id.uuidString,
                    "text": "one",
                ]
            )
            let e1 = try #require((first["result"] as? [String: Any])?["envelope_id"] as? String)

            // orchestrator → A → orchestrator：recipient 已在路径上，是环。
            let cycle = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: [
                    "action": "send",
                    "to": Agent.defaultId.uuidString,
                    "text": "back",
                    "parent_envelope_id": e1,
                ]
            )
            expectFailure(cycle, kind: "execution_error", errorCode: "cycle")
            #expect(cycle["attempted"] as? String == pid(Agent.defaultId))

            let second = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: [
                    "action": "send",
                    "to": fixture.agentB.id.uuidString,
                    "text": "two",
                    "parent_envelope_id": e1,
                ]
            )
            #expect(second["ok"] as? Bool == true)
            let e2 = try #require((second["result"] as? [String: Any])?["envelope_id"] as? String)

            // 第三跳超过 maxDepth = 2。
            let tooDeep = try await run(
                fixture, caller: fixture.agentB.id,
                arguments: [
                    "action": "send",
                    "to": fixture.agentC.id.uuidString,
                    "text": "three",
                    "parent_envelope_id": e2,
                ]
            )
            expectFailure(tooDeep, kind: "execution_error", errorCode: "depth_exceeded")
            #expect(tooDeep["depth"] as? Int == 3)
            #expect(tooDeep["limit"] as? Int == 2)
        }
    }

    @Test("a run at its token cap refuses the next forward")
    func tokenCapEnforced() async throws {
        try await withFixture { fixture in
            await fixture.coordinator.addEdge(from: pid(fixture.agentA.id), to: pid(fixture.agentB.id))
            let first = try await run(
                fixture, caller: Agent.defaultId,
                arguments: [
                    "action": "send",
                    "to": fixture.agentA.id.uuidString,
                    "text": "budgeted",
                ]
            )
            let result = try #require(first["result"] as? [String: Any])
            let runId = try #require(result["run_id"] as? String)
            let envelopeId = try #require(result["envelope_id"] as? String)

            // 记满 token（相等不抛——recordUsage 只在超过时失败）。
            let cap = CollaborationRunLimits.default.maxTokens
            _ = try await fixture.service.recordUsage(runId: runId, tokens: cap, toolCalls: 0)

            // deliverForward 在 `tokensUsed >= maxTokens` 时拒绝。
            let over = try await run(
                fixture, caller: fixture.agentA.id,
                arguments: [
                    "action": "send",
                    "to": fixture.agentB.id.uuidString,
                    "text": "over budget",
                    "parent_envelope_id": envelopeId,
                ]
            )
            expectFailure(over, kind: "execution_error", errorCode: "token_cap")
            #expect(over["used"] as? Int == cap)
            #expect(over["limit"] as? Int == cap)
        }
    }

    // MARK: - Helpers

    private func pid(_ id: UUID) -> String {
        DirectedMailboxCoordinator.participantId(for: id)
    }

    /// 不经过 fixture 的调用：用于参数解析失败（工具在解析参数前不碰
    /// AgentManager / coordinator）。
    private func runBare(caller: UUID, arguments: [String: Any]) async throws -> [String: Any] {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
        let rawString = try await ChatExecutionContext.$currentAgentId.withValue(caller) {
            try await OsaurusMailboxTool().execute(argumentsJSON: json)
        }
        return try raw(rawString)
    }

    /// 经隔离 fixture 的完整调用：绑定调用方 agent 与测试 coordinator。
    private func run(
        _ fixture: ToolFixture,
        caller: UUID,
        arguments: [String: Any]
    ) async throws -> [String: Any] {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
        let rawString = try await ChatExecutionContext.$currentAgentId.withValue(caller) {
            try await OsaurusMailboxTool.$coordinatorOverrideForTests.withValue(fixture.coordinator) {
                try await fixture.tool.execute(argumentsJSON: json)
            }
        }
        return try raw(rawString)
    }

    private func raw(_ rawString: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(rawString.utf8))
        guard let dict = object as? [String: Any] else {
            Issue.record("tool output is not a JSON object: \(rawString)")
            return [:]
        }
        return dict
    }

    private func expectFailure(
        _ dict: [String: Any],
        kind: String,
        errorCode: String? = nil,
        field: String? = nil,
        retryable: Bool? = nil
    ) {
        #expect(dict["ok"] as? Bool == false)
        #expect(dict["kind"] as? String == kind)
        if let errorCode {
            #expect(dict["error_code"] as? String == errorCode)
        }
        if let field {
            #expect(dict["field"] as? String == field)
        }
        if let retryable {
            #expect(dict["retryable"] as? Bool == retryable)
        }
    }

    private func withFixture(_ body: (ToolFixture) async throws -> Void) async throws {
        let fixture = try await ToolFixture()
        do {
            try await body(fixture)
            await fixture.cleanup()
        } catch {
            await fixture.cleanup()
            throw error
        }
    }

    /// 隔离 fixture：agent 注册进临时 root 的 store，mailbox 服务与
    /// coordinator 都绑到临时目录，完全不碰用户级文件。
    @MainActor
    private final class ToolFixture {
        let root: URL
        let previousRoot: URL?
        let service: DirectedMailboxService
        let coordinator: DirectedMailboxCoordinator
        let tool = OsaurusMailboxTool()
        let agentA = Agent(name: "Mailbox A")
        let agentB = Agent(name: "Mailbox B")
        let agentC = Agent(name: "Mailbox C")

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "mailbox-tool-\(UUID().uuidString)",
                isDirectory: true
            )
            previousRoot = OsaurusPaths.overrideRoot
            OsaurusPaths.overrideRoot = root.appendingPathComponent("app-root", isDirectory: true)
            AgentManager.shared.refresh()
            AgentManager.shared.add(agentA)
            AgentManager.shared.add(agentB)
            AgentManager.shared.add(agentC)
            service = try DirectedMailboxService(
                directory: root.appendingPathComponent("mailbox", isDirectory: true))
            coordinator = DirectedMailboxCoordinator(service: service)
        }

        func cleanup() async {
            _ = await AgentManager.shared.delete(id: agentA.id)
            _ = await AgentManager.shared.delete(id: agentB.id)
            _ = await AgentManager.shared.delete(id: agentC.id)
            OsaurusPaths.overrideRoot = previousRoot
            try? FileManager.default.removeItem(at: root)
        }
    }
}
