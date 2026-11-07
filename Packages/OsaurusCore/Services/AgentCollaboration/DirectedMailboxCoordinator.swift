//
//  DirectedMailboxCoordinator.swift
//  osaurus
//
//  ADR-Nuo-002 mailbox 的生产共享入口。`DirectedMailboxService` 是唯一写路径，
//  本类只是把它接到 UI 与模型工具上：MainActor 上缓存 allowlist 供同步门控查询，
//  async 代理转发 send/reply/inbox。服务初始化失败时降级为不可用状态，
//  工具返回 `mailbox_unavailable`，UI 显示错误行，不 crash。
//

import Combine
import Foundation

@MainActor
public final class DirectedMailboxCoordinator: ObservableObject {
    public static let shared = DirectedMailboxCoordinator()

    /// 最近一次 allowlist 快照。`mailboxVisible(agentId:)` 的同步数据源；
    /// 启动时从 service 拉取，UI 每次增删后刷新。
    @Published public private(set) var allowlist: [DirectedMailboxEdge] = []

    /// 服务初始化失败（如目录不可写、磁盘快照损坏）时非 nil；UI 据此显示错误行。
    @Published public private(set) var loadError: String?

    private var service: DirectedMailboxService?

    /// Set by `MailboxWakeService.install`. The coordinator stays the single
    /// write path; the wake runs behind a landed envelope and never blocks the
    /// sending tool.
    public typealias WakeHandler = @MainActor (
        _ delivery: DirectedMailboxDelivery,
        _ sender: AgentCollaborationParticipant,
        _ recipient: AgentCollaborationParticipant
    ) async -> Void

    private var wakeHandler: WakeHandler?

    private init() {
        do {
            let service = try DirectedMailboxService(
                directory: OsaurusPaths.directedMailboxFile().deletingLastPathComponent()
            )
            self.service = service
        } catch {
            self.service = nil
            self.loadError = String(describing: error)
            return
        }
        let service = self.service
        Task { @MainActor [weak self] in
            guard let self, let service else { return }
            self.allowlist = await service.allowlist()
        }
    }

    /// Test seam: suites bind a coordinator to a service rooted in a temp
    /// directory so they never touch the user-level mailbox file.
    init(service: DirectedMailboxService) {
        self.service = service
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.allowlist = await service.allowlist()
        }
    }

    // MARK: - 门控（SystemPromptComposer 同步调用）

    /// 该 agent 是否应看到 `osaurus_mailbox`：`local:<uuid>` 出现在缓存
    /// allowlist 任一端即可。Orchestrator 直达任意目标，不走此判定。
    public func mailboxVisible(agentId: UUID) -> Bool {
        let participantId = Self.participantId(for: agentId)
        return allowlist.contains { $0.from == participantId || $0.to == participantId }
    }

    /// Pure formatting — safe to call from any isolation domain.
    public nonisolated static func participantId(for agentId: UUID) -> String {
        "local:\(agentId.uuidString.lowercased())"
    }

    /// Installs the automatic recipient wake. nil restores delivery-only
    /// behavior, which is the shape every pre-wake build had.
    public func setWakeHandler(_ handler: WakeHandler?) {
        wakeHandler = handler
    }

    // MARK: - UI 编辑

    public func addEdge(from: String, to: String) async {
        guard let service else { return }
        var edges = allowlist
        let edge = DirectedMailboxEdge(from: from, to: to)
        guard !edges.contains(edge) else { return }
        edges.append(edge)
        do {
            try await service.replaceAllowlist(edges)
            allowlist = await service.allowlist()
        } catch {
            loadError = String(describing: error)
        }
    }

    public func removeEdge(from: String, to: String) async {
        guard let service else { return }
        let edges = allowlist.filter { !($0.from == from && $0.to == to) }
        do {
            try await service.replaceAllowlist(edges)
            allowlist = await service.allowlist()
        } catch {
            loadError = String(describing: error)
        }
    }

    // MARK: - 工具代理

    /// 发送：无 `parentEnvelopeId` 时新开 run。成功后按一次 tool call 记账。
    /// token 记账不在本切片（无 tokenizer 上下文），见
    /// `docs/notes/implemented/2026-11-06-mailbox-settings-and-tool.md`。
    public func send(
        from sender: AgentCollaborationParticipant,
        to recipient: AgentCollaborationParticipant,
        text: String,
        summary: String?,
        parentEnvelopeId: UUID?
    ) async throws -> DirectedMailboxDelivery {
        guard let service else { throw DirectedMailboxCoordinatorError.unavailable }
        let runId: String
        if let parentEnvelopeId {
            guard let parent = await service.record(for: parentEnvelopeId) else {
                throw DirectedMailboxError.unknownReplyTarget(parentEnvelopeId)
            }
            runId = parent.runId
        } else {
            runId = try await service.openRun().id
        }
        let request = AgentCollaborationRequest(
            title: summary ?? String(text.prefix(80)),
            objective: text,
            contextSummary: summary
        )
        let delivery = try await service.send(
            .request(request),
            from: sender,
            to: recipient,
            runId: runId,
            parentEnvelopeId: parentEnvelopeId
        )
        _ = try await service.recordUsage(runId: runId, tokens: 0, toolCalls: 1)
        // Fire-and-forget: a turn can take minutes, and the sending tool must
        // return as soon as the envelope is durable. A wake that cannot run
        // (quota, busy recipient) leaves the message in the inbox, so the pull
        // path still works.
        if let wakeHandler {
            Task { @MainActor in
                await wakeHandler(delivery, sender, recipient)
            }
        }
        return delivery
    }

    /// 回复：runId 从被回信封的 record 推导，成功后同样按一次 tool call 记账。
    public func reply(
        from sender: AgentCollaborationParticipant,
        envelopeId: UUID,
        text: String
    ) async throws -> DirectedMailboxDelivery {
        guard let service else { throw DirectedMailboxCoordinatorError.unavailable }
        guard let parent = await service.record(for: envelopeId) else {
            throw DirectedMailboxError.unknownReplyTarget(envelopeId)
        }
        // 只能回上一跳的发件人——服务的 deliverReply 会再校验一次。
        let recipient = parent.envelope.sender
        let reply = AgentCollaborationReply(
            inReplyToEnvelopeId: envelopeId,
            status: .completed,
            message: text
        )
        let delivery = try await service.send(
            .reply(reply),
            from: sender,
            to: recipient,
            runId: parent.runId,
            parentEnvelopeId: envelopeId
        )
        _ = try await service.recordUsage(runId: parent.runId, tokens: 0, toolCalls: 1)
        return delivery
    }

    /// 读收件箱。非 orchestrator 只能读自己的。
    public func inbox(
        for participantId: String,
        requestedBy requesterId: String
    ) async throws -> [DirectedMailboxRecord] {
        guard let service else { throw DirectedMailboxCoordinatorError.unavailable }
        return try await service.inbox(for: participantId, requestedBy: requesterId)
    }

    public var isAvailable: Bool { service != nil }
}

public enum DirectedMailboxCoordinatorError: Error, Equatable, Sendable {
    case unavailable
}
