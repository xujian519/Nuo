//
//  DirectedMailboxService.swift
//  osaurus
//
//  持久化的定向邮箱。发送、收件和 spawn/resume 都走这里。
//  不实现 `AgentCollaborationTransport`：那个 send 没有准入，接上它就会绕过本闸门。
//  不调用子 Agent spawn，也不改 host.dispatch 的调用方上下文。
//

import Foundation

public actor DirectedMailboxService {
    public nonisolated let orchestratorId: String
    public nonisolated let fileURL: URL

    private var snapshot: Snapshot

    public init(
        directory: URL,
        orchestratorId: String = DirectedMailboxPolicy.orchestratorParticipantId
    ) throws {
        self.orchestratorId = orchestratorId
        self.fileURL = directory.appendingPathComponent(DirectedMailboxSchema.fileName, isDirectory: false)
        let loaded = try Self.read(self.fileURL)
        self.snapshot = loaded
        // init 不在 actor 隔离域里，冷启动写盘只能走静态方法。
        if !FileManager.default.fileExists(atPath: self.fileURL.path) {
            try Self.write(loaded, to: self.fileURL)
        }
    }

    @discardableResult
    public func openRun(
        id: String = UUID().uuidString,
        limits: CollaborationRunLimits = .default
    ) throws -> CollaborationRunState {
        if let existing = snapshot.runs.first(where: { $0.id == id }) {
            return existing
        }
        let created = CollaborationRunState(
            id: id,
            tokensUsed: 0,
            toolCallsUsed: 0,
            subtasksUsed: 0,
            limits: limits
        )
        snapshot.runs.append(created)
        try persist()
        return created
    }

    public func recordUsage(runId: String, tokens: Int, toolCalls: Int) throws -> CollaborationRunState {
        guard let index = snapshot.runs.firstIndex(where: { $0.id == runId }) else {
            throw DirectedMailboxError.unknownRun(runId)
        }
        var run = snapshot.runs[index]
        let nextTokens = run.tokensUsed + max(0, tokens)
        let nextTools = run.toolCallsUsed + max(0, toolCalls)
        if nextTokens > run.limits.maxTokens {
            throw DirectedMailboxError.tokenCapExceeded(used: nextTokens, limit: run.limits.maxTokens)
        }
        if nextTools > run.limits.maxToolCalls {
            throw DirectedMailboxError.toolCapExceeded(used: nextTools, limit: run.limits.maxToolCalls)
        }
        run.tokensUsed = nextTokens
        run.toolCallsUsed = nextTools
        snapshot.runs[index] = run
        try persist()
        return run
    }

    public func replaceAllowlist(_ edges: [DirectedMailboxEdge]) throws {
        snapshot.allowlist = Self.sorted(edges)
        try persist()
    }

    public func allowlist() -> [DirectedMailboxEdge] {
        snapshot.allowlist
    }

    public func authorizeSpawnResume(callerId: String, targetId: String) throws -> DirectedMailboxSpawnGrant {
        try authorizeEdge(
            from: callerId,
            to: targetId,
            denial: .spawnNotAuthorized(caller: callerId, target: targetId)
        )
        return DirectedMailboxSpawnGrant(callerId: callerId, targetId: targetId)
    }

    /// 只读自己的收件箱。Orchestrator 可以读任意收件箱，因为它持有这条邮箱。
    public func inbox(for participantId: String, requestedBy: String) throws -> [DirectedMailboxRecord] {
        if requestedBy != participantId && requestedBy != orchestratorId {
            throw DirectedMailboxError.unauthorizedEdge(from: requestedBy, to: participantId)
        }
        return snapshot.records
            .filter { $0.envelope.recipient?.id == participantId }
            .sorted { lhs, rhs in
                if lhs.envelope.createdAt == rhs.envelope.createdAt {
                    return lhs.envelope.id.uuidString < rhs.envelope.id.uuidString
                }
                return lhs.envelope.createdAt < rhs.envelope.createdAt
            }
    }

    @discardableResult
    public func send(
        _ event: AgentCollaborationEvent,
        from sender: AgentCollaborationParticipant,
        to recipient: AgentCollaborationParticipant,
        runId: String,
        parentEnvelopeId: UUID? = nil,
        correlationId: String? = nil,
        createdAt: Date = Date()
    ) throws -> DirectedMailboxDelivery {
        if case .reply(let reply) = event {
            if let parentEnvelopeId, parentEnvelopeId != reply.inReplyToEnvelopeId {
                throw DirectedMailboxError.untrustedEnvelopeRejected("reply parent mismatch")
            }
            return try deliverReply(reply, from: sender, to: recipient, runId: runId, createdAt: createdAt)
        }
        return try deliverForward(
            event,
            from: sender,
            to: recipient,
            runId: runId,
            parentEnvelopeId: parentEnvelopeId,
            correlationId: correlationId,
            createdAt: createdAt
        )
    }

    /// 全局记忆保持共享桶。bot 域只返回该 Agent 自己的已有分区，不创建文件。
    public nonisolated func memoryGrant(reader: UUID, layer: MailboxMemoryLayer) throws -> MailboxMemoryGrant {
        switch layer {
        case .global:
            _ = try DirectedMailboxMemoryPartition.requireExisting(
                partitionKey: DirectedMailboxMemoryPartition.globalKey
            )
            return MailboxMemoryGrant(
                layer: .global,
                vectorPartitionKey: DirectedMailboxMemoryPartition.globalKey,
                agentDatabaseFile: nil
            )
        case .botDomain(let owner):
            guard reader == owner else {
                throw DirectedMailboxError.crossAgentMemoryDenied(reader: reader, owner: owner)
            }
            let key = MemoryNamespace.agent(owner).key
            _ = try DirectedMailboxMemoryPartition.requireExisting(partitionKey: key)
            return MailboxMemoryGrant(
                layer: .botDomain(owner),
                vectorPartitionKey: key,
                agentDatabaseFile: OsaurusPaths.agentDatabaseFile(for: owner)
            )
        }
    }

    private func deliverReply(
        _ reply: AgentCollaborationReply,
        from sender: AgentCollaborationParticipant,
        to recipient: AgentCollaborationParticipant,
        runId: String,
        createdAt: Date
    ) throws -> DirectedMailboxDelivery {
        guard let run = snapshot.runs.first(where: { $0.id == runId }) else {
            throw DirectedMailboxError.unknownRun(runId)
        }
        guard let parent = record(id: reply.inReplyToEnvelopeId), parent.runId == runId else {
            throw DirectedMailboxError.unknownReplyTarget(reply.inReplyToEnvelopeId)
        }
        guard let parentRecipient = parent.envelope.recipient?.id else {
            throw DirectedMailboxError.missingRecipient
        }
        // 回信只允许回到上一封的发件人，不能借回复打开一条新边。
        guard parentRecipient == sender.id, parent.envelope.sender.id == recipient.id else {
            throw DirectedMailboxError.unauthorizedEdge(from: sender.id, to: recipient.id)
        }
        let envelope = AgentCollaborationEnvelope(
            correlationId: parent.envelope.correlationId,
            createdAt: createdAt,
            sender: sender,
            recipient: recipient,
            provenance: AgentCollaborationProvenance(
                origin: parent.envelope.provenance.origin,
                sessionId: runId,
                parentEnvelopeId: parent.envelope.id,
                transport: DirectedMailboxSchema.transport,
                hops: parent.envelope.provenance.hops + [sender.id]
            ),
            event: .reply(reply)
        )
        let stored = DirectedMailboxRecord(envelope: envelope, runId: runId)
        var updated = snapshot
        updated.records.append(stored)
        try Self.write(updated, to: fileURL)
        snapshot = updated
        return DirectedMailboxDelivery(record: stored, run: run)
    }

    private func deliverForward(
        _ event: AgentCollaborationEvent,
        from sender: AgentCollaborationParticipant,
        to recipient: AgentCollaborationParticipant,
        runId: String,
        parentEnvelopeId: UUID?,
        correlationId: String?,
        createdAt: Date
    ) throws -> DirectedMailboxDelivery {
        guard let index = snapshot.runs.firstIndex(where: { $0.id == runId }) else {
            throw DirectedMailboxError.unknownRun(runId)
        }
        if sender.id.isEmpty || recipient.id.isEmpty {
            throw DirectedMailboxError.missingRecipient
        }
        if parentEnvelopeId == nil, let expected = latestHolder(runId: runId) {
            throw DirectedMailboxError.senderNotAtFrontier(sender: sender.id, expected: expected)
        }
        let chain = try frontier(parentId: parentEnvelopeId, runId: runId)
        if let holder = chain.holder, holder != sender.id {
            throw DirectedMailboxError.senderNotAtFrontier(sender: sender.id, expected: holder)
        }
        try authorizeEdge(
            from: sender.id,
            to: recipient.id,
            denial: .unauthorizedEdge(from: sender.id, to: recipient.id)
        )
        let run = snapshot.runs[index]
        let nextDepth = chain.forwardDepth + 1
        if nextDepth > run.limits.maxDepth {
            throw DirectedMailboxError.depthExceeded(depth: nextDepth, limit: run.limits.maxDepth)
        }
        if recipient.id == sender.id || chain.visited.contains(recipient.id) {
            throw DirectedMailboxError.cycle(path: chain.visited, attempted: recipient.id)
        }
        if run.tokensUsed >= run.limits.maxTokens {
            throw DirectedMailboxError.tokenCapExceeded(used: run.tokensUsed, limit: run.limits.maxTokens)
        }
        if run.toolCallsUsed >= run.limits.maxToolCalls {
            throw DirectedMailboxError.toolCapExceeded(used: run.toolCallsUsed, limit: run.limits.maxToolCalls)
        }
        let nextSubtasks = run.subtasksUsed + 1
        if nextSubtasks > run.limits.maxSubtasks {
            throw DirectedMailboxError.subtaskCapExceeded(used: nextSubtasks, limit: run.limits.maxSubtasks)
        }

        let parent = parentEnvelopeId.flatMap { record(id: $0) }
        let envelope = AgentCollaborationEnvelope(
            correlationId: parent?.envelope.correlationId ?? correlationId ?? UUID().uuidString,
            createdAt: createdAt,
            sender: sender,
            recipient: recipient,
            provenance: AgentCollaborationProvenance(
                origin: parent?.envelope.provenance.origin ?? sender,
                sessionId: runId,
                parentEnvelopeId: parent?.envelope.id,
                transport: DirectedMailboxSchema.transport,
                hops: (parent?.envelope.provenance.hops ?? []) + [sender.id]
            ),
            event: event
        )
        let stored = DirectedMailboxRecord(envelope: envelope, runId: runId)
        var updatedRun = run
        updatedRun.subtasksUsed = nextSubtasks
        var updated = snapshot
        updated.runs[index] = updatedRun
        updated.records.append(stored)
        try Self.write(updated, to: fileURL)
        snapshot = updated
        return DirectedMailboxDelivery(record: stored, run: updatedRun)
    }

    private func authorizeEdge(from: String, to: String, denial: DirectedMailboxError) throws {
        if from == orchestratorId {
            return
        }
        guard snapshot.allowlist.contains(DirectedMailboxEdge(from: from, to: to)) else {
            throw denial
        }
    }

    private func latestHolder(runId: String) -> String? {
        guard let latest = snapshot.records.last(where: { $0.runId == runId }) else {
            return nil
        }
        return latest.envelope.recipient?.id ?? latest.envelope.sender.id
    }

    private func record(id: UUID) -> DirectedMailboxRecord? {
        snapshot.records.first { $0.envelope.id == id }
    }

    /// 按信封 id 查记录。工具与 coordinator 用它推导 runId；只读，不绕过任何准入。
    public func record(for envelopeId: UUID) -> DirectedMailboxRecord? {
        record(id: envelopeId)
    }

    private struct Frontier {
        var visited: [String]
        var holder: String?
        var forwardDepth: Int
    }

    /// 深度只数前向信封。回复把持有者交回去，但不增加深度。
    private func frontier(parentId: UUID?, runId: String) throws -> Frontier {
        guard let parentId else {
            return Frontier(visited: [], holder: nil, forwardDepth: 0)
        }
        var cursor: UUID? = parentId
        var seen: Set<UUID> = []
        var visited: [String] = []
        var forwardDepth = 0
        var holder: String?
        var isImmediate = true
        while let id = cursor {
            if seen.count >= 32 || !seen.insert(id).inserted {
                throw DirectedMailboxError.cycle(path: visited, attempted: id.uuidString)
            }
            guard let parent = record(id: id), parent.runId == runId else {
                throw DirectedMailboxError.unknownReplyTarget(id)
            }
            guard let recipientId = parent.envelope.recipient?.id else {
                throw DirectedMailboxError.missingRecipient
            }
            if isImmediate {
                holder = recipientId
                isImmediate = false
            }
            if !visited.contains(parent.envelope.sender.id) {
                visited.append(parent.envelope.sender.id)
            }
            if !visited.contains(recipientId) {
                visited.append(recipientId)
            }
            if !isReply(parent.envelope.event) {
                forwardDepth += 1
            }
            cursor = parent.envelope.provenance.parentEnvelopeId
        }
        return Frontier(visited: visited, holder: holder, forwardDepth: forwardDepth)
    }

    private func isReply(_ event: AgentCollaborationEvent) -> Bool {
        if case .reply = event {
            return true
        }
        return false
    }

    private func persist() throws {
        try Self.write(snapshot, to: fileURL)
    }

    private static func write(_ snapshot: Snapshot, to fileURL: URL) throws {
        let encoder = JSONEncoder.osaurusCanonical()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func read(_ fileURL: URL) throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Snapshot.self, from: data)
        try validate(decoded)
        return decoded
    }

    private static func validate(_ snapshot: Snapshot) throws {
        guard snapshot.schema == DirectedMailboxSchema.current else {
            throw DirectedMailboxError.untrustedEnvelopeRejected(snapshot.schema)
        }
        var runIds: Set<String> = []
        for run in snapshot.runs {
            guard runIds.insert(run.id).inserted else {
                throw DirectedMailboxError.untrustedEnvelopeRejected("duplicate run")
            }
        }
        var envelopeIds: Set<UUID> = []
        for record in snapshot.records {
            guard record.envelope.schema == AgentCollaborationProtocolContract.schema else {
                throw DirectedMailboxError.untrustedEnvelopeRejected(record.envelope.schema)
            }
            guard envelopeIds.insert(record.envelope.id).inserted else {
                throw DirectedMailboxError.untrustedEnvelopeRejected("duplicate envelope")
            }
            guard runIds.contains(record.runId) else {
                throw DirectedMailboxError.unknownRun(record.runId)
            }
        }
    }

    private static func sorted(_ edges: [DirectedMailboxEdge]) -> [DirectedMailboxEdge] {
        var unique: Set<DirectedMailboxEdge> = []
        for edge in edges where !edge.from.isEmpty && !edge.to.isEmpty {
            unique.insert(edge)
        }
        return unique.sorted { lhs, rhs in
            if lhs.from == rhs.from {
                return lhs.to < rhs.to
            }
            return lhs.from < rhs.from
        }
    }

    private struct Snapshot: Codable, Equatable {
        var schema: String
        var allowlist: [DirectedMailboxEdge]
        var runs: [CollaborationRunState]
        var records: [DirectedMailboxRecord]

        static let empty = Snapshot(
            schema: DirectedMailboxSchema.current,
            allowlist: [],
            runs: [],
            records: []
        )
    }
}
