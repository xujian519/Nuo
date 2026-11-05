//
//  DirectedMailbox.swift
//  osaurus
//
//  ADR-Nuo-002 P0。定向邮箱复用协作信封，不另起一套线协议。
//  信封正文不可信；bot 域记忆只指向已有的 agentId 分区。
//

import Foundation

public enum DirectedMailboxSchema {
    public static let current = "osaurus.directed-mailbox.v1"
    public static let fileName = "mailbox.json"
    /// 与子 Agent dispatch、host.dispatch 都不是同一条传输。
    public static let transport = "directed-mailbox"
}

public enum DirectedMailboxPolicy {
    /// 与 `Agent.agentCollaborationParticipant` 使用同一套 id 格式。
    public static let orchestratorParticipantId = "local:\(Agent.defaultId.uuidString.lowercased())"
}

public enum DirectedMailboxError: Error, Equatable, Sendable {
    case unauthorizedEdge(from: String, to: String)
    case spawnNotAuthorized(caller: String, target: String)
    case cycle(path: [String], attempted: String)
    case depthExceeded(depth: Int, limit: Int)
    case tokenCapExceeded(used: Int, limit: Int)
    case toolCapExceeded(used: Int, limit: Int)
    case subtaskCapExceeded(used: Int, limit: Int)
    case missingRecipient
    case unknownRun(String)
    case unknownReplyTarget(UUID)
    case senderNotAtFrontier(sender: String, expected: String)
    case untrustedEnvelopeRejected(String)
    case crossAgentMemoryDenied(reader: UUID, owner: UUID)
    case parallelMemoryStoreForbidden(String)
}

public struct DirectedMailboxEdge: Codable, Sendable, Equatable, Hashable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// 一次协作 run 的准入上限。深度硬顶是 2：调用方写更大的值也会被夹住。
public struct CollaborationRunLimits: Codable, Sendable, Equatable {
    public var maxTokens: Int
    public var maxToolCalls: Int
    public var maxSubtasks: Int
    public var maxDepth: Int

    public static let depthCeiling = 2

    public static let `default` = CollaborationRunLimits(
        maxTokens: 8_000,
        maxToolCalls: 16,
        maxSubtasks: 4,
        maxDepth: depthCeiling
    )

    public init(maxTokens: Int, maxToolCalls: Int, maxSubtasks: Int, maxDepth: Int) {
        self.maxTokens = max(0, maxTokens)
        self.maxToolCalls = max(0, maxToolCalls)
        self.maxSubtasks = max(0, maxSubtasks)
        self.maxDepth = min(max(0, maxDepth), Self.depthCeiling)
    }

    private enum CodingKeys: String, CodingKey {
        case maxTokens
        case maxToolCalls
        case maxSubtasks
        case maxDepth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxTokens: try container.decode(Int.self, forKey: .maxTokens),
            maxToolCalls: try container.decode(Int.self, forKey: .maxToolCalls),
            maxSubtasks: try container.decode(Int.self, forKey: .maxSubtasks),
            maxDepth: try container.decode(Int.self, forKey: .maxDepth)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(maxToolCalls, forKey: .maxToolCalls)
        try container.encode(maxSubtasks, forKey: .maxSubtasks)
        try container.encode(maxDepth, forKey: .maxDepth)
    }
}

public struct CollaborationRunState: Codable, Sendable, Equatable {
    public var id: String
    public var tokensUsed: Int
    public var toolCallsUsed: Int
    public var subtasksUsed: Int
    public var limits: CollaborationRunLimits

    public init(
        id: String,
        tokensUsed: Int,
        toolCallsUsed: Int,
        subtasksUsed: Int,
        limits: CollaborationRunLimits
    ) {
        self.id = id
        self.tokensUsed = tokensUsed
        self.toolCallsUsed = toolCallsUsed
        self.subtasksUsed = subtasksUsed
        self.limits = limits
    }
}

public struct DirectedMailboxRecord: Codable, Sendable, Equatable, Identifiable {
    public var envelope: AgentCollaborationEnvelope
    public var runId: String
    /// 磁盘上的 false 也不能把正文变成可执行指令。
    public var contentUntrusted: Bool

    public var id: UUID { envelope.id }

    public init(envelope: AgentCollaborationEnvelope, runId: String) {
        self.envelope = envelope
        self.runId = runId
        self.contentUntrusted = true
    }

    private enum CodingKeys: String, CodingKey {
        case envelope
        case runId
        case contentUntrusted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.envelope = try container.decode(AgentCollaborationEnvelope.self, forKey: .envelope)
        self.runId = try container.decode(String.self, forKey: .runId)
        self.contentUntrusted = true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(envelope, forKey: .envelope)
        try container.encode(runId, forKey: .runId)
        try container.encode(true, forKey: .contentUntrusted)
    }

    public func untrustedText() -> UntrustedMailboxText {
        switch envelope.event {
        case .capabilities(let capabilities):
            return UntrustedMailboxText(text: capabilities.names.joined(separator: ","))
        case .request(let request):
            return UntrustedMailboxText(text: request.objective)
        case .handoffRequest(let handoff):
            return UntrustedMailboxText(text: handoff.summary)
        case .reply(let reply):
            return UntrustedMailboxText(text: reply.message ?? "")
        case .failure(let diagnostic):
            return UntrustedMailboxText(text: diagnostic.message)
        }
    }
}

public struct UntrustedMailboxText: Sendable, Equatable {
    public var text: String

    public var trusted: Bool { false }

    public init(text: String) {
        self.text = text
    }
}

public struct DirectedMailboxDelivery: Sendable, Equatable {
    public var record: DirectedMailboxRecord
    public var run: CollaborationRunState

    public init(record: DirectedMailboxRecord, run: CollaborationRunState) {
        self.record = record
        self.run = run
    }
}

/// 恢复目标 Agent 的授权。它不继承调用方的 dispatch 上下文，也不替代子 Agent。
public struct DirectedMailboxSpawnGrant: Sendable, Equatable {
    public var callerId: String
    public var targetId: String

    public var inheritsCallerDispatchContext: Bool { false }
    public var replacesSubagentDispatch: Bool { false }

    public init(callerId: String, targetId: String) {
        self.callerId = callerId
        self.targetId = targetId
    }
}

public enum MailboxMemoryLayer: Sendable, Equatable {
    /// 现有的共享记忆桶（空 agent id）。本路径不新建存储。
    case global
    /// 现有 `MemoryNamespace.agent` 与该 Agent 的 Agent DB。
    case botDomain(UUID)
}

public struct MailboxMemoryGrant: Sendable, Equatable {
    public var layer: MailboxMemoryLayer
    public var vectorPartitionKey: String
    public var agentDatabaseFile: URL?

    public init(layer: MailboxMemoryLayer, vectorPartitionKey: String, agentDatabaseFile: URL?) {
        self.layer = layer
        self.vectorPartitionKey = vectorPartitionKey
        self.agentDatabaseFile = agentDatabaseFile
    }
}

public enum DirectedMailboxMemoryPartition {
    public static let globalKey = ""

    /// 只接受已有的全局桶或某个 Agent 的规范分区键。
    /// 小写别名、project 分区、以及任何插件自建键都会被拒绝。
    public static func requireExisting(partitionKey: String) throws -> MailboxMemoryLayer {
        if partitionKey.isEmpty {
            return .global
        }
        guard let namespace = MemoryNamespace(key: partitionKey) else {
            throw DirectedMailboxError.parallelMemoryStoreForbidden(partitionKey)
        }
        switch namespace {
        case .agent(let id):
            let canonical = MemoryNamespace.agent(id).key
            guard partitionKey == canonical else {
                throw DirectedMailboxError.parallelMemoryStoreForbidden(partitionKey)
            }
            return .botDomain(id)
        case .project:
            throw DirectedMailboxError.parallelMemoryStoreForbidden(partitionKey)
        }
    }
}
