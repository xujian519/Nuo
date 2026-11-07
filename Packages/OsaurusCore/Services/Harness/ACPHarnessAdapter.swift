//
//  ACPHarnessAdapter.swift
//  osaurus
//
//  Agent Client Protocol over stdio. One process per chat; the codec performs
//  the handshake (initialize → authenticate when the agent names a default
//  method → session/new), sends one `session/prompt` per turn, and maps
//  `session/update` notifications onto Osaurus events. Grok CLI speaks the
//  same protocol through `grok agent stdio`.
//

import Foundation

struct ACPHarnessAdapter: HarnessAdapter {
    let runtime: HarnessRuntime

    /// ACP agents bring their own tool loop. Osaurus does not hand them an MCP
    /// server, so the agent token carries no tool scope.
    func tokenToolScope(context: HarnessLaunchContext) -> Set<String>? {
        []
    }

    func tokenAllowsConfigWrites(context: HarnessLaunchContext) -> Bool {
        false
    }

    func launchPlan(context: HarnessLaunchContext, token: String?) throws -> HarnessLaunchPlan {
        var arguments = runtime.resolvedArguments(
            chatId: context.chatId,
            agentId: context.agentId,
            workingDirectory: context.workingDirectory
        )
        if let systemPrompt = context.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
            !systemPrompt.isEmpty,
            runtime.wantsSystemPromptFile,
            let file = try? HarnessScratch.writePrivateFile(
                named: "system-prompt-\(UUID().uuidString).md",
                contents: systemPrompt,
                in: HarnessScratch.privateDirectory(chatId: context.chatId)
            )
        {
            // Only protocols whose arguments opt into the placeholder get a
            // prompt file; ACP has no standard system-prompt field, so the
            // default leaves the agent's own instructions alone.
            arguments = runtime.resolvedArguments(
                chatId: context.chatId,
                agentId: context.agentId,
                workingDirectory: context.workingDirectory,
                systemPromptFile: file
            )
        }

        var environment = runtime.environment
        for (key, value) in HarnessEnvironment.contract(context: context, token: token) {
            environment[key] = value
        }

        return HarnessLaunchPlan(
            spec: HarnessProcess.LaunchSpec(
                executable: runtime.executable,
                arguments: arguments,
                environment: environment,
                removingEnvironment: HarnessEnvironment.alwaysRemoved,
                workingDirectory: context.workingDirectory,
                runtimeName: runtime.displayName
            )
        )
    }

    func makeCodec() -> HarnessCodec {
        ACPHarnessCodec(
            runtimeName: runtime.displayName,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
    }

    func makeCodec(context: HarnessLaunchContext) -> HarnessCodec {
        ACPHarnessCodec(
            runtimeName: runtime.displayName,
            workingDirectory: context.workingDirectory.path
        )
    }
}

final class ACPHarnessCodec: HarnessCodec {
    private enum Phase {
        case idle
        case initializing
        case authenticating
        case creatingSession
        case ready
    }

    private struct PendingPermission {
        let rpcId: Any
        let options: [(id: String, name: String)]
    }

    private let runtimeName: String
    private let workingDirectory: String
    private var phase: Phase = .idle
    private var sessionId: String?
    private var pendingMessage: HarnessUserMessage?
    private var dialogs: [String: PendingPermission] = [:]
    private var nextId = 1
    private var lastOutputTokens = 0

    init(runtimeName: String, workingDirectory: String) {
        self.runtimeName = runtimeName
        self.workingDirectory = workingDirectory
    }

    var pendingDialogIds: [String] { Array(dialogs.keys) }

    func beginTurn(_ message: HarnessUserMessage) throws -> [Data] {
        guard phase == .idle || phase == .ready else {
            throw HarnessError.turnFailed(
                runtime: runtimeName,
                detail: "The agent is still starting its ACP session."
            )
        }
        if let sessionId {
            return [try promptRecord(message, sessionId: sessionId)]
        }
        pendingMessage = message
        phase = .initializing
        return [
            try request(
                method: "initialize",
                params: [
                    "protocolVersion": 1,
                    "clientCapabilities": [
                        "fs": ["readTextFile": false, "writeTextFile": false],
                        "terminal": false,
                    ],
                ]
            )
        ]
    }

    func decode(line: Data) -> (events: [HarnessEvent], replies: [Data]) {
        guard let root = HarnessJSON.object(line) else { return ([], []) }

        if let method = root["method"] as? String {
            if let id = root["id"] {
                return handleClientRequest(id: id, method: method, params: root["params"] as? [String: Any])
            }
            return (handleNotification(method: method, params: root["params"] as? [String: Any]), [])
        }

        if let error = root["error"] as? [String: Any] {
            return handleError(error)
        }
        if let result = root["result"] as? [String: Any] {
            return handleResult(result)
        }
        return ([], [])
    }

    func interruptRecords() -> [Data] {
        guard let sessionId else { return [] }
        let record = try? HarnessJSON.encode([
            "jsonrpc": "2.0",
            "method": "session/cancel",
            "params": ["sessionId": sessionId],
        ])
        return record.map { [$0] } ?? []
    }

    func dialogResponse(id: String, response: HarnessDialogResponse) -> Data? {
        guard let pending = dialogs.removeValue(forKey: id) else { return nil }
        let option: (id: String, name: String)?
        switch response {
        case .value(let name):
            option = pending.options.first { $0.name == name }
        case .confirmed(let accepted):
            option = accepted ? pending.options.first { $0.name.lowercased().contains("allow") } : nil
        case .cancelled:
            option = nil
        }
        let outcome: [String: Any]
        if let option {
            outcome = ["outcome": ["outcome": "selected", "optionId": option.id]]
        } else {
            outcome = ["outcome": ["outcome": "cancelled"]]
        }
        guard let data = try? HarnessJSON.encode(["jsonrpc": "2.0", "id": pending.rpcId, "result": outcome])
        else { return nil }
        return data
    }

    // MARK: - Handshake

    private func handleResult(_ result: [String: Any]) -> ([HarnessEvent], [Data]) {
        switch phase {
        case .initializing:
            let meta = result["_meta"] as? [String: Any]
            let method = meta?["defaultAuthMethodId"] as? String
            if let method, !method.isEmpty {
                phase = .authenticating
                return ([], [try? request(method: "authenticate", params: ["methodId": method])].compactMap { $0 })
            }
            return ([], [newSessionRecord()].compactMap { $0 })
        case .authenticating:
            return ([], [newSessionRecord()].compactMap { $0 })
        case .creatingSession:
            guard let id = result["sessionId"] as? String, !id.isEmpty else {
                phase = .idle
                return ([.turnFailed(.turnFailed(runtime: runtimeName, detail: "ACP session/new returned no session id."))], [])
            }
            sessionId = id
            phase = .ready
            guard let message = pendingMessage else { return ([], []) }
            pendingMessage = nil
            guard let record = try? promptRecord(message, sessionId: id) else {
                return ([.turnFailed(.turnFailed(runtime: runtimeName, detail: "Could not encode the prompt."))], [])
            }
            return ([], [record])
        case .ready, .idle:
            return ([.turnCompleted], [])
        }
    }

    private func newSessionRecord() -> Data? {
        phase = .creatingSession
        return try? request(
            method: "session/new",
            params: ["cwd": workingDirectory, "mcpServers": []]
        )
    }

    private func handleError(_ error: [String: Any]) -> ([HarnessEvent], [Data]) {
        let message = (error["message"] as? String) ?? L("The agent reported an unknown error.")
        let code = (error["code"] as? Int) ?? 0
        phase = .idle
        pendingMessage = nil
        let classified = HarnessError.classify(runtime: runtimeName, detail: message)
        if code == -32000, message.lowercased().contains("auth") {
            return ([.turnFailed(.notAuthenticated(runtime: runtimeName, detail: message))], [])
        }
        return ([.turnFailed(classified)], [])
    }

    // MARK: - Notifications

    private func handleNotification(method: String, params: [String: Any]?) -> [HarnessEvent] {
        guard method == "session/update" || method == "_x.ai/session_notification",
            let update = params?["update"] as? [String: Any],
            let kind = update["sessionUpdate"] as? String
        else { return [] }

        switch kind {
        case "agent_message_chunk":
            guard let text = Self.textContent(update["content"]) else { return [] }
            return [.text(text)]
        case "agent_thought_chunk":
            guard let text = Self.textContent(update["content"]) else { return [] }
            return [.reasoning(text)]
        case "tool_call":
            return toolEvents(update: update, isUpdate: false)
        case "tool_call_update":
            return toolEvents(update: update, isUpdate: true)
        case "turn_completed", "response_completed":
            return statsEvents(update)
        default:
            return []
        }
    }

    private func toolEvents(update: [String: Any], isUpdate: Bool) -> [HarnessEvent] {
        let callId = update["toolCallId"] as? String
        let name = (update["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (update["kind"] as? String)
            ?? "tool"
        let status = (update["status"] as? String)?.lowercased()
        if status == "completed" || status == "failed" {
            return [.toolFinished(callId: callId, name: name, isError: status == "failed")]
        }
        if isUpdate, status == nil {
            return []
        }
        return [.toolStarted(callId: callId, name: name)]
    }

    private func statsEvents(_ update: [String: Any]) -> [HarnessEvent] {
        let usage = update["usage"] as? [String: Any]
        let output = Self.intValue(usage?["outputTokens"]) ?? 0
        if output > 0 { lastOutputTokens = output }
        let seconds = (Self.intValue(usage?["apiDurationMs"]) ?? 0).mapSeconds
        let rate = seconds > 0 ? Double(lastOutputTokens) / seconds : 0
        let stop = (update["stop_reason"] as? String) ?? (update["stopReason"] as? String)
        return [.stats(outputTokens: lastOutputTokens, tokensPerSecond: rate, stopReason: stop)]
    }

    // MARK: - Client requests

    private func handleClientRequest(
        id: Any,
        method: String,
        params: [String: Any]?
    ) -> ([HarnessEvent], [Data]) {
        if method == "session/request_permission" {
            let options = (params?["options"] as? [[String: Any]]) ?? []
            let entries = options.compactMap { option -> (id: String, name: String)? in
                guard let optionId = option["optionId"] as? String else { return nil }
                let name = (option["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? optionId
                return (optionId, name)
            }
            let title = ((params?["toolCall"] as? [String: Any])?["title"] as? String)
                ?? L("Allow this tool?")
            let dialogId = "acp-\(String(describing: id))"
            dialogs[dialogId] = PendingPermission(rpcId: id, options: entries)
            return (
                [
                    .dialog(
                        HarnessDialogRequest(
                            id: dialogId,
                            title: title,
                            kind: .select(options: entries.map(\.name))
                        )
                    )
                ],
                []
            )
        }
        guard let data = try? HarnessJSON.encode([
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": -32601, "message": "Method not supported by Nuo: \(method)"],
        ]) else { return ([], []) }
        return ([], [data])
    }

    // MARK: - Records

    private func promptRecord(_ message: HarnessUserMessage, sessionId: String) throws -> Data {
        var blocks: [[String: Any]] = message.images.map {
            ["type": "image", "data": $0.data.base64EncodedString(), "mimeType": $0.mimeType]
        }
        blocks.append(["type": "text", "text": message.text])
        let id = nextId
        nextId += 1
        return try JSONSerialization.data(
            withJSONObject: [
                "jsonrpc": "2.0",
                "id": id,
                "method": "session/prompt",
                "params": ["sessionId": sessionId, "prompt": blocks],
            ],
            options: [.withoutEscapingSlashes]
        )
    }

    private func request(method: String, params: [String: Any]) throws -> Data {
        let id = nextId
        nextId += 1
        return try HarnessJSON.encode([
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ])
    }

    private static func textContent(_ value: Any?) -> String? {
        if let block = value as? [String: Any] {
            return block["text"] as? String
        }
        if let blocks = value as? [[String: Any]] {
            let text = blocks.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        return value as? String
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}

private extension Int {
    var mapSeconds: Double { Double(self) / 1000 }
}
