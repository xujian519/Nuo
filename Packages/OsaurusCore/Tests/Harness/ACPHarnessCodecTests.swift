//
//  ACPHarnessCodecTests.swift
//  osaurusTests
//
//  Slice 5 (issue #19): the ACP codec's handshake and event mapping. These
//  tests drive the codec directly — no process, no model, no network.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite(.serialized)
struct ACPHarnessCodecTests {
    private func decode(_ json: String, with codec: ACPHarnessCodec) -> (events: [HarnessEvent], replies: [Data]) {
        codec.decode(line: Data(json.utf8))
    }

    private func replyJSON(_ replies: [Data], at index: Int = 0) throws -> [String: Any] {
        try #require(replies.indices.contains(index))
        return try #require(
            try JSONSerialization.jsonObject(with: replies[index]) as? [String: Any]
        )
    }

    @Test("Grok CLI is an ACP runtime with its stdio command")
    func grokRuntimeDefaults() {
        #expect(HarnessKind.grokCLI.defaultExecutable == "grok")
        #expect(HarnessKind.grokCLI.defaultArguments == ["agent", "stdio"])
        #expect(HarnessKind.acp.defaultExecutable.isEmpty)
        #expect(HarnessKind.acp.defaultArguments.isEmpty)
        #expect(HarnessRuntime(name: "Grok", kind: .grokCLI).resumesSessions == false)
    }

    @Test("the handshake authenticates when the agent names a default method")
    func handshakeWithAuth() throws {
        let codec = ACPHarnessCodec(runtimeName: "ACP", workingDirectory: "/tmp/work")
        let started = try codec.beginTurn(HarnessUserMessage(text: "hello"))
        let initialize = try replyJSON(started)
        #expect(initialize["method"] as? String == "initialize")

        let afterInitialize = decode(
            #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"_meta":{"defaultAuthMethodId":"cached_token"}}}"#,
            with: codec
        )
        let authenticate = try replyJSON(afterInitialize.replies)
        #expect(authenticate["method"] as? String == "authenticate")
        #expect((authenticate["params"] as? [String: Any])?["methodId"] as? String == "cached_token")

        let afterAuth = decode(#"{"jsonrpc":"2.0","id":2,"result":{}}"#, with: codec)
        let newSession = try replyJSON(afterAuth.replies)
        #expect(newSession["method"] as? String == "session/new")
        #expect((newSession["params"] as? [String: Any])?["cwd"] as? String == "/tmp/work")

        let afterNew = decode(
            #"{"jsonrpc":"2.0","id":3,"result":{"sessionId":"s-1"}}"#,
            with: codec
        )
        let prompt = try replyJSON(afterNew.replies)
        #expect(prompt["method"] as? String == "session/prompt")
        let params = try #require(prompt["params"] as? [String: Any])
        #expect(params["sessionId"] as? String == "s-1")
        let blocks = try #require(params["prompt"] as? [[String: Any]])
        #expect(blocks.first?["text"] as? String == "hello")
    }

    @Test("an ACP agent without a default auth method goes straight to session/new")
    func handshakeWithoutAuth() throws {
        let codec = ACPHarnessCodec(runtimeName: "ACP", workingDirectory: "/tmp")
        _ = try codec.beginTurn(HarnessUserMessage(text: "hi"))
        let afterInitialize = decode(
            #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}"#,
            with: codec
        )
        let newSession = try replyJSON(afterInitialize.replies)
        #expect(newSession["method"] as? String == "session/new")
    }

    @Test("session updates become text, reasoning, tool, and stats events")
    func updatesMapToEvents() throws {
        let codec = ACPHarnessCodec(runtimeName: "ACP", workingDirectory: "/tmp")
        _ = try codec.beginTurn(HarnessUserMessage(text: "hi"))
        _ = decode(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}"#, with: codec)
        _ = decode(#"{"jsonrpc":"2.0","id":2,"result":{"sessionId":"s"}}"#, with: codec)

        let text = decode(
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"pong"}}}}"#,
            with: codec
        )
        #expect(text.events == [.text("pong")])

        let thought = decode(
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"thinking"}}}}"#,
            with: codec
        )
        #expect(thought.events == [.reasoning("thinking")])

        let tool = decode(
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"tool_call","toolCallId":"t1","title":"Read file","status":"in_progress"}}}"#,
            with: codec
        )
        #expect(tool.events == [.toolStarted(callId: "t1", name: "Read file")])

        let finished = decode(
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"tool_call_update","toolCallId":"t1","title":"Read file","status":"completed"}}}"#,
            with: codec
        )
        #expect(finished.events == [.toolFinished(callId: "t1", name: "Read file", isError: false)])

        let stats = decode(
            #"{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"s","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"outputTokens":10,"apiDurationMs":2000}}}}"#,
            with: codec
        )
        #expect(
            stats.events == [.stats(outputTokens: 10, tokensPerSecond: 5, stopReason: "end_turn")]
        )
    }

    @Test("a prompt result completes the turn; an error classifies as a failure")
    func turnResults() throws {
        let codec = ACPHarnessCodec(runtimeName: "ACP", workingDirectory: "/tmp")
        _ = try codec.beginTurn(HarnessUserMessage(text: "hi"))
        _ = decode(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}"#, with: codec)
        _ = decode(#"{"jsonrpc":"2.0","id":2,"result":{"sessionId":"s"}}"#, with: codec)

        let done = decode(#"{"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}}"#, with: codec)
        #expect(done.events == [.turnCompleted])

        let failed = decode(
            #"{"jsonrpc":"2.0","id":4,"error":{"code":-32603,"message":"rate limit reached"}}"#,
            with: codec
        )
        guard case .turnFailed(let error) = failed.events.first else {
            Issue.record("expected a turn failure, got \(failed.events)")
            return
        }
        #expect(error == .rateLimited(runtime: "ACP", detail: "rate limit reached"))
    }

    @Test("a permission request surfaces a dialog and answers with the option id")
    func permissionDialog() throws {
        let codec = ACPHarnessCodec(runtimeName: "ACP", workingDirectory: "/tmp")
        let permission = decode(
            #"{"jsonrpc":"2.0","id":7,"method":"session/request_permission","params":{"sessionId":"s","toolCall":{"title":"Write file"},"options":[{"optionId":"allow-once","name":"Allow once","kind":"allow_once"},{"optionId":"reject","name":"Reject","kind":"reject_once"}]}}"#,
            with: codec
        )
        #expect(
            permission.events == [
                .dialog(
                    HarnessDialogRequest(
                        id: "acp-7",
                        title: "Write file",
                        kind: .select(options: ["Allow once", "Reject"])
                    )
                )
            ]
        )
        #expect(codec.pendingDialogIds == ["acp-7"])
        let response = try #require(codec.dialogResponse(id: "acp-7", response: .value("Allow once")))
        let root = try #require(try JSONSerialization.jsonObject(with: response) as? [String: Any])
        let result = try #require(root["result"] as? [String: Any])
        let outcome = try #require(result["outcome"] as? [String: Any])
        #expect(outcome["outcome"] as? String == "selected")
        #expect(outcome["optionId"] as? String == "allow-once")
        #expect(codec.pendingDialogIds.isEmpty)
    }

    @Test("an unsupported client request is answered so the agent cannot hang")
    func unsupportedRequestReplies() throws {
        let codec = ACPHarnessCodec(runtimeName: "ACP", workingDirectory: "/tmp")
        let decoded = decode(
            #"{"jsonrpc":"2.0","id":9,"method":"fs/read_text_file","params":{"path":"/x"}}"#,
            with: codec
        )
        let reply = try replyJSON(decoded.replies)
        let error = try #require(reply["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32601)
    }

    @Test("interrupt is an ACP cancel notification")
    func interrupt() throws {
        let codec = ACPHarnessCodec(runtimeName: "ACP", workingDirectory: "/tmp")
        _ = try codec.beginTurn(HarnessUserMessage(text: "hi"))
        #expect(codec.interruptRecords().isEmpty)

        _ = decode(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}"#, with: codec)
        _ = decode(#"{"jsonrpc":"2.0","id":2,"result":{"sessionId":"s"}}"#, with: codec)
        let record = try #require(codec.interruptRecords().first)
        let root = try #require(try JSONSerialization.jsonObject(with: record) as? [String: Any])
        #expect(root["method"] as? String == "session/cancel")
        #expect((root["params"] as? [String: Any])?["sessionId"] as? String == "s")
    }

    @Test("declarative config accepts the new kinds")
    func declarativeKinds() {
        #expect(ConfigHarness.kind(forKey: "acp") == .acp)
        #expect(ConfigHarness.kind(forKey: "grok_cli") == .grokCLI)
        #expect(ConfigHarness.key(for: .acp) == "acp")
        #expect(ConfigHarness.key(for: .grokCLI) == "grok_cli")
    }
}
