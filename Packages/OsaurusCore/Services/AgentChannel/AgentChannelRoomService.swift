//
//  AgentChannelRoomService.swift
//  osaurus
//
//  The single write path for room task ownership. Views call the actions;
//  the inbound relay claims a room and reports turn lifecycle; both go through
//  `AgentChannelRoomStore`, so a UI status row and the runtime can never
//  disagree about who owns a room or whether it is stopped.
//

import Foundation

@MainActor
public final class AgentChannelRoomService: ObservableObject {
    public static let shared = AgentChannelRoomService(
        store: AgentChannelRoomStore.production(),
        cancelTask: { BackgroundTaskManager.shared.cancelTask($0) },
        isTaskActive: { id in
            BackgroundTaskManager.shared.backgroundTasks[id]?.status.isActive == true
        },
        audit: { connectionId, roomId, action, detail in
            AgentChannelRoomService.recordAudit(
                connectionId: connectionId,
                roomId: roomId,
                action: action,
                detail: detail
            )
        }
    )

    @Published public private(set) var rooms: [AgentChannelRoomRecord] = []
    @Published public private(set) var loadError: String?

    private let store: AgentChannelRoomStore?
    private let cancelTask: @MainActor (UUID) -> Void
    private let isTaskActive: @MainActor (UUID) -> Bool
    private let audit: @MainActor (String, String, String, String) -> Void

    public init(
        store: AgentChannelRoomStore?,
        cancelTask: @escaping @MainActor (UUID) -> Void,
        isTaskActive: @escaping @MainActor (UUID) -> Bool,
        audit: @escaping @MainActor (String, String, String, String) -> Void
    ) {
        self.store = store
        self.cancelTask = cancelTask
        self.isTaskActive = isTaskActive
        self.audit = audit
        if store == nil {
            loadError = "The room task store is unavailable."
        }
    }

    // MARK: - Reads

    public func task(connectionId: String, roomId: String) -> AgentChannelRoomRecord? {
        let connection = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let room = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        return rooms.first { $0.connectionId == connection && $0.roomId == room }
    }

    /// Whether an inbound message may start a turn. An unknown room has no
    /// assignment yet and is open; a stopped or archived room is not.
    public func acceptsMessages(connectionId: String, roomId: String) -> Bool {
        task(connectionId: connectionId, roomId: roomId)?.status.acceptsMessages ?? true
    }

    public func load() async {
        guard let store else { return }
        rooms = await store.all()
    }

    // MARK: - Inbound

    /// Attaches an inbound message to the room owner, assigning the first
    /// resolved agent when the room has none. Returns the effective record.
    @discardableResult
    public func claim(
        connectionId: String,
        roomId: String,
        proposedAgentId: UUID,
        externalSessionKey: String? = nil
    ) async throws -> AgentChannelRoomRecord {
        guard let store else { throw AgentChannelRoomError.unknownRoom }
        do {
            let result = try await store.claim(
                connectionId: connectionId,
                roomId: roomId,
                proposedAgentId: proposedAgentId,
                taskId: nil,
                externalSessionKey: externalSessionKey
            )
            await refresh()
            if result.assignedOwner {
                audit(connectionId, roomId, "room.assign", "agent=\(proposedAgentId.uuidString)")
            }
            return result.record
        } catch {
            await refresh()
            throw error
        }
    }

    @discardableResult
    public func markRunning(
        connectionId: String,
        roomId: String,
        taskId: UUID,
        externalSessionKey: String? = nil
    ) async -> AgentChannelRoomRecord? {
        guard let store else { return nil }
        let record = try? await store.markRunning(
            connectionId: connectionId,
            roomId: roomId,
            taskId: taskId,
            externalSessionKey: externalSessionKey
        )
        await refresh()
        return record
    }

    @discardableResult
    public func markWaiting(
        connectionId: String,
        roomId: String,
        taskId: UUID
    ) async -> AgentChannelRoomRecord? {
        guard let store else { return nil }
        let record = try? await store.markWaiting(
            connectionId: connectionId,
            roomId: roomId,
            taskId: taskId
        )
        await refresh()
        return record
    }

    @discardableResult
    public func finishTurn(connectionId: String, roomId: String) async -> AgentChannelRoomRecord? {
        guard let store else { return nil }
        let record = try? await store.finishTurn(connectionId: connectionId, roomId: roomId)
        await refresh()
        return record
    }

    // MARK: - Actions

    @discardableResult
    public func assign(
        connectionId: String,
        roomId: String,
        agentId: UUID,
        requestedBy: UUID? = nil
    ) async throws -> AgentChannelRoomRecord {
        guard let store else { throw AgentChannelRoomError.unknownRoom }
        let existing = await store.room(connectionId: connectionId, roomId: roomId)
        try authorize(existing, requestedBy: requestedBy)
        do {
            let record = try await store.assign(
                connectionId: connectionId,
                roomId: roomId,
                agentId: agentId
            )
            await refresh()
            audit(connectionId, roomId, "room.assign", "agent=\(agentId.uuidString)")
            return record
        } catch {
            await refresh()
            throw error
        }
    }

    @discardableResult
    public func stop(
        connectionId: String,
        roomId: String,
        requestedBy: UUID? = nil
    ) async throws -> AgentChannelRoomRecord {
        guard let store else { throw AgentChannelRoomError.unknownRoom }
        let existing = await store.room(connectionId: connectionId, roomId: roomId)
        try authorize(existing, requestedBy: requestedBy)
        if let taskId = existing?.taskId, isTaskActive(taskId) {
            cancelTask(taskId)
        }
        do {
            let record = try await store.stop(connectionId: connectionId, roomId: roomId)
            await refresh()
            audit(connectionId, roomId, "room.stop", "status=\(record.status.rawValue)")
            return record
        } catch {
            await refresh()
            throw error
        }
    }

    @discardableResult
    public func resume(
        connectionId: String,
        roomId: String,
        requestedBy: UUID? = nil
    ) async throws -> AgentChannelRoomRecord {
        guard let store else { throw AgentChannelRoomError.unknownRoom }
        let existing = await store.room(connectionId: connectionId, roomId: roomId)
        try authorize(existing, requestedBy: requestedBy)
        do {
            let record = try await store.resume(connectionId: connectionId, roomId: roomId)
            await refresh()
            audit(connectionId, roomId, "room.resume", "status=\(record.status.rawValue)")
            return record
        } catch {
            await refresh()
            throw error
        }
    }

    @discardableResult
    public func reassign(
        connectionId: String,
        roomId: String,
        agentId: UUID,
        requestedBy: UUID? = nil
    ) async throws -> AgentChannelRoomRecord {
        guard let store else { throw AgentChannelRoomError.unknownRoom }
        let existing = await store.room(connectionId: connectionId, roomId: roomId)
        try authorize(existing, requestedBy: requestedBy)
        if let taskId = existing?.taskId, isTaskActive(taskId) {
            cancelTask(taskId)
        }
        do {
            let record = try await store.reassign(
                connectionId: connectionId,
                roomId: roomId,
                agentId: agentId
            )
            await refresh()
            audit(connectionId, roomId, "room.reassign", "agent=\(agentId.uuidString)")
            return record
        } catch {
            await refresh()
            throw error
        }
    }

    @discardableResult
    public func archive(
        connectionId: String,
        roomId: String,
        requestedBy: UUID? = nil
    ) async throws -> AgentChannelRoomRecord {
        guard let store else { throw AgentChannelRoomError.unknownRoom }
        let existing = await store.room(connectionId: connectionId, roomId: roomId)
        try authorize(existing, requestedBy: requestedBy)
        if let taskId = existing?.taskId, isTaskActive(taskId) {
            cancelTask(taskId)
        }
        do {
            let record = try await store.archive(connectionId: connectionId, roomId: roomId)
            await refresh()
            audit(connectionId, roomId, "room.archive", "status=archived")
            return record
        } catch {
            await refresh()
            throw error
        }
    }

    @discardableResult
    public func restore(
        connectionId: String,
        roomId: String,
        requestedBy: UUID? = nil
    ) async throws -> AgentChannelRoomRecord {
        guard let store else { throw AgentChannelRoomError.unknownRoom }
        let existing = await store.room(connectionId: connectionId, roomId: roomId)
        try authorize(existing, requestedBy: requestedBy)
        do {
            let record = try await store.restore(connectionId: connectionId, roomId: roomId)
            await refresh()
            audit(connectionId, roomId, "room.restore", "status=\(record.status.rawValue)")
            return record
        } catch {
            await refresh()
            throw error
        }
    }

    // MARK: - Helpers

    private func refresh() async {
        guard let store else { return }
        rooms = await store.all()
    }

    /// The local user and the Orchestrator may always act; another agent may
    /// only act on a room it owns.
    private func authorize(_ record: AgentChannelRoomRecord?, requestedBy: UUID?) throws {
        guard let requestedBy else { return }
        if requestedBy == Agent.defaultId { return }
        if let owner = record?.ownerAgentId, owner != requestedBy {
            throw AgentChannelRoomError.notOwner(owner: owner)
        }
    }

    /// Channel audit rows are best effort: ownership changes must succeed even
    /// when the message database is unavailable.
    private nonisolated static func recordAudit(
        connectionId: String,
        roomId: String,
        action: String,
        detail: String
    ) {
        Task.detached(priority: .utility) {
            do {
                try AgentChannelMessageStore.shared.openIfNeeded()
                let record = AgentChannelAuditRecord(
                    connectionId: connectionId,
                    roomId: roomId,
                    direction: .system,
                    action: action,
                    status: .accepted,
                    authorizationDecision: "room",
                    redactedSummary: detail,
                    metadataJSON: "{\"detail\":\"\(detail)\"}"
                )
                _ = try AgentChannelMessageStore.shared.recordAuditEvent(record)
            } catch {
                // The room file already has the transition; a missing audit
                // row is reported by the channel health surface, not here.
            }
        }
    }
}
