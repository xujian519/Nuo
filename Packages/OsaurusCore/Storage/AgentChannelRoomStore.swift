//
//  AgentChannelRoomStore.swift
//  osaurus
//
//  Durable room task ownership for Agent Channels. One actor owns the file;
//  every action is a validated state transition, and the write replaces the
//  file atomically. The file lives beside the channel configuration, not in
//  the message database: it is small, human-inspectable state, and losing the
//  database must not lose who owns a room.
//

import Foundation

public enum AgentChannelRoomSchema {
    public static let current = "osaurus.agent-channel-rooms.v1"
    public static let fileName = "rooms.json"
}

public enum AgentChannelRoomStoreError: Error, Equatable, LocalizedError {
    case unsupportedSchema(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            return "Unsupported Agent Channel room schema: \(schema)"
        }
    }
}

struct AgentChannelRoomSnapshot: Codable {
    var schema: String
    var rooms: [AgentChannelRoomRecord]
}

public actor AgentChannelRoomStore {
    public nonisolated let fileURL: URL
    private var records: [String: AgentChannelRoomRecord]

    public nonisolated static func production() -> AgentChannelRoomStore? {
        try? AgentChannelRoomStore(directory: OsaurusPaths.agentChannels())
    }

    public init(directory: URL) throws {
        self.fileURL = directory.appendingPathComponent(
            AgentChannelRoomSchema.fileName,
            isDirectory: false
        )
        self.records = try Self.read(fileURL)
    }

    // MARK: - Reads

    public func room(connectionId: String, roomId: String) -> AgentChannelRoomRecord? {
        records[Self.key(connectionId, roomId)]
    }

    public func all() -> [AgentChannelRoomRecord] {
        records.values.sorted {
            ($0.connectionId, $0.roomId) < ($1.connectionId, $1.roomId)
        }
    }

    public func rooms(connectionId: String) -> [AgentChannelRoomRecord] {
        let normalized = Self.normalized(connectionId)
        return all().filter { $0.connectionId == normalized }
    }

    // MARK: - Inbound claim

    /// Attaches an inbound message to the room's owner. The first message
    /// assigns `proposedAgentId`; later messages keep that owner, so one room
    /// has one answering agent until an explicit reassign. Refuses a stopped
    /// or archived room.
    @discardableResult
    public func claim(
        connectionId: String,
        roomId: String,
        proposedAgentId: UUID,
        taskId: UUID?,
        externalSessionKey: String?,
        at date: Date = Date()
    ) throws -> (record: AgentChannelRoomRecord, assignedOwner: Bool) {
        let key = Self.key(connectionId, roomId)
        if var record = records[key] {
            guard record.status.acceptsMessages else {
                throw AgentChannelRoomError.unavailable(record.status)
            }
            var changed = false
            let assignedOwner = record.ownerAgentId == nil
            if assignedOwner {
                record.ownerAgentId = proposedAgentId
                record.status = .assigned
                changed = true
            }
            if let taskId, record.taskId != taskId {
                record.taskId = taskId
                changed = true
            }
            if let externalSessionKey, record.externalSessionKey != externalSessionKey {
                record.externalSessionKey = externalSessionKey
                changed = true
            }
            if record.status == .idle {
                record.status = .assigned
                changed = true
            }
            if changed {
                record.updatedAt = date
                records[key] = record
                try persist()
            }
            return (record, assignedOwner)
        }

        let record = AgentChannelRoomRecord(
            connectionId: Self.normalized(connectionId),
            roomId: Self.normalized(roomId),
            ownerAgentId: proposedAgentId,
            taskId: taskId,
            externalSessionKey: externalSessionKey,
            status: .assigned,
            createdAt: date,
            updatedAt: date
        )
        records[key] = record
        try persist()
        return (record, true)
    }

    // MARK: - Explicit assignment

    /// Manual assignment. Unlike `claim`, this refuses a room that already
    /// has live work: two members pressing Assign at once produce one winner
    /// and one typed conflict.
    @discardableResult
    public func assign(
        connectionId: String,
        roomId: String,
        agentId: UUID,
        at date: Date = Date()
    ) throws -> AgentChannelRoomRecord {
        let key = Self.key(connectionId, roomId)
        var record = records[key]
            ?? AgentChannelRoomRecord(
                connectionId: Self.normalized(connectionId),
                roomId: Self.normalized(roomId),
                createdAt: date,
                updatedAt: date
            )
        if record.status == .archived {
            throw AgentChannelRoomError.unavailable(.archived)
        }
        if record.status.isLive {
            throw AgentChannelRoomError.conflict(current: record.status)
        }
        record.ownerAgentId = agentId
        record.taskId = nil
        record.externalSessionKey = nil
        record.status = .assigned
        record.updatedAt = date
        records[key] = record
        try persist()
        return record
    }

    /// Moves ownership without waiting for the current turn to end. The
    /// caller stops the old task; the next message runs on `agentId`.
    @discardableResult
    public func reassign(
        connectionId: String,
        roomId: String,
        agentId: UUID,
        at date: Date = Date()
    ) throws -> AgentChannelRoomRecord {
        let key = Self.key(connectionId, roomId)
        guard var record = records[key] else {
            throw AgentChannelRoomError.unknownRoom
        }
        if record.status == .archived {
            throw AgentChannelRoomError.unavailable(.archived)
        }
        record.ownerAgentId = agentId
        record.taskId = nil
        record.externalSessionKey = nil
        record.status = .assigned
        record.updatedAt = date
        records[key] = record
        try persist()
        return record
    }

    // MARK: - Turn lifecycle

    @discardableResult
    public func markRunning(
        connectionId: String,
        roomId: String,
        taskId: UUID,
        externalSessionKey: String? = nil,
        at date: Date = Date()
    ) throws -> AgentChannelRoomRecord? {
        try update(connectionId, roomId, date: date) { record in
            guard record.status.isLive else { return false }
            record.status = .running
            record.taskId = taskId
            if let externalSessionKey {
                record.externalSessionKey = externalSessionKey
            }
            return true
        }
    }

    @discardableResult
    public func markWaiting(
        connectionId: String,
        roomId: String,
        taskId: UUID,
        at date: Date = Date()
    ) throws -> AgentChannelRoomRecord? {
        try update(connectionId, roomId, date: date) { record in
            guard record.status.isLive else { return false }
            record.status = .waiting
            record.taskId = taskId
            return true
        }
    }

    /// A turn ended normally. The owner and task id stay so the next message
    /// continues the same conversation.
    @discardableResult
    public func finishTurn(
        connectionId: String,
        roomId: String,
        at date: Date = Date()
    ) throws -> AgentChannelRoomRecord? {
        try update(connectionId, roomId, date: date) { record in
            // `waiting` is a question to the room, not a finished turn; it
            // stays until the next message starts a running turn.
            guard record.status.isLive, record.status != .waiting else { return false }
            record.status = .idle
            return true
        }
    }

    @discardableResult
    public func stop(
        connectionId: String,
        roomId: String,
        at date: Date = Date()
    ) throws -> AgentChannelRoomRecord {
        let key = Self.key(connectionId, roomId)
        guard var record = records[key] else {
            throw AgentChannelRoomError.unknownRoom
        }
        if record.status == .archived {
            throw AgentChannelRoomError.unavailable(.archived)
        }
        if record.status == .stopped {
            return record
        }
        record.status = .stopped
        record.updatedAt = date
        records[key] = record
        try persist()
        return record
    }

    /// A stopped room becomes assignable again without losing the task id, so
    /// the next message continues the same conversation instead of starting
    /// a duplicate task.
    @discardableResult
    public func resume(
        connectionId: String,
        roomId: String,
        at date: Date = Date()
    ) throws -> AgentChannelRoomRecord {
        let key = Self.key(connectionId, roomId)
        guard var record = records[key] else {
            throw AgentChannelRoomError.unknownRoom
        }
        if record.status == .archived {
            throw AgentChannelRoomError.unavailable(.archived)
        }
        guard record.status == .stopped else {
            throw AgentChannelRoomError.conflict(current: record.status)
        }
        record.status = record.ownerAgentId == nil ? .idle : .assigned
        record.updatedAt = date
        records[key] = record
        try persist()
        return record
    }

    // MARK: - Archive

    @discardableResult
    public func archive(
        connectionId: String,
        roomId: String,
        at date: Date = Date()
    ) throws -> AgentChannelRoomRecord {
        let key = Self.key(connectionId, roomId)
        guard var record = records[key] else {
            throw AgentChannelRoomError.unknownRoom
        }
        if record.status == .archived { return record }
        record.statusBeforeArchive = record.status
        record.status = .archived
        record.archivedAt = date
        record.updatedAt = date
        records[key] = record
        try persist()
        return record
    }

    @discardableResult
    public func restore(
        connectionId: String,
        roomId: String,
        at date: Date = Date()
    ) throws -> AgentChannelRoomRecord {
        let key = Self.key(connectionId, roomId)
        guard var record = records[key] else {
            throw AgentChannelRoomError.unknownRoom
        }
        guard record.status == .archived else {
            throw AgentChannelRoomError.conflict(current: record.status)
        }
        record.status = record.statusBeforeArchive ?? .idle
        record.statusBeforeArchive = nil
        record.archivedAt = nil
        record.updatedAt = date
        records[key] = record
        try persist()
        return record
    }

    // MARK: - Persistence

    private func update(
        _ connectionId: String,
        _ roomId: String,
        date: Date,
        _ body: (inout AgentChannelRoomRecord) -> Bool
    ) throws -> AgentChannelRoomRecord? {
        let key = Self.key(connectionId, roomId)
        guard var record = records[key] else { return nil }
        guard body(&record) else { return record }
        record.updatedAt = date
        records[key] = record
        try persist()
        return record
    }

    private func persist() throws {
        let snapshot = AgentChannelRoomSnapshot(
            schema: AgentChannelRoomSchema.current,
            rooms: Array(records.values)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private static func read(_ url: URL) throws -> [String: AgentChannelRoomRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AgentChannelRoomSnapshot.self, from: data)
        guard snapshot.schema == AgentChannelRoomSchema.current else {
            throw AgentChannelRoomStoreError.unsupportedSchema(snapshot.schema)
        }
        return Dictionary(
            snapshot.rooms.map { (Self.key($0.connectionId, $0.roomId), $0) },
            uniquingKeysWith: { _, new in new }
        )
    }

    private static func normalized(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func key(_ connectionId: String, _ roomId: String) -> String {
        "\(normalized(connectionId))\u{1}\(normalized(roomId))"
    }
}
