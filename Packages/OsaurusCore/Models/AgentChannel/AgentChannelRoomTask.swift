//
//  AgentChannelRoomTask.swift
//  osaurus
//
//  Slice 4 (issue #18): a channel room owns at most one task and one agent.
//  The record is durable so a relaunch keeps who was answering and whether the
//  room is stopped or archived, and every mutation goes through the store's
//  state machine rather than a view writing a file.
//

import Foundation

public enum AgentChannelRoomStatus: String, Codable, Sendable, CaseIterable {
    case idle
    case assigned
    case running
    case waiting
    case stopped
    case archived

    /// A turn is in flight or about to start.
    public var isLive: Bool {
        switch self {
        case .assigned, .running, .waiting: return true
        case .idle, .stopped, .archived: return false
        }
    }

    /// Whether a new inbound message may start a turn.
    public var acceptsMessages: Bool {
        switch self {
        case .idle, .assigned, .running, .waiting: return true
        case .stopped, .archived: return false
        }
    }

    public var displayName: String {
        switch self {
        case .idle: return L("Idle")
        case .assigned: return L("Assigned")
        case .running: return L("Running")
        case .waiting: return L("Waiting")
        case .stopped: return L("Stopped")
        case .archived: return L("Archived")
        }
    }
}

public struct AgentChannelRoomRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(connectionId)\u{1}\(roomId)" }

    public var connectionId: String
    public var roomId: String
    /// The local agent that answers in this room. Nil until the first claim.
    public var ownerAgentId: UUID?
    /// The background task that currently owns the conversation lane. A
    /// resumed room keeps it so the next turn continues the same conversation.
    public var taskId: UUID?
    public var externalSessionKey: String?
    public var status: AgentChannelRoomStatus
    /// Restored by `restore`; `archive` keeps it so a room comes back in the
    /// state it left.
    public var statusBeforeArchive: AgentChannelRoomStatus?
    public var createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?

    public init(
        connectionId: String,
        roomId: String,
        ownerAgentId: UUID? = nil,
        taskId: UUID? = nil,
        externalSessionKey: String? = nil,
        status: AgentChannelRoomStatus = .idle,
        statusBeforeArchive: AgentChannelRoomStatus? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.connectionId = connectionId
        self.roomId = roomId
        self.ownerAgentId = ownerAgentId
        self.taskId = taskId
        self.externalSessionKey = externalSessionKey
        self.status = status
        self.statusBeforeArchive = statusBeforeArchive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }
}

public enum AgentChannelRoomError: Error, Equatable, LocalizedError {
    case unavailable(AgentChannelRoomStatus)
    /// A concurrent claim or a transition the record cannot make.
    case conflict(current: AgentChannelRoomStatus)
    case notOwner(owner: UUID?)
    case unknownRoom

    public var errorDescription: String? {
        switch self {
        case .unavailable(.archived):
            return "This room is archived."
        case .unavailable(.stopped):
            return "This room is stopped."
        case .unavailable(let status):
            return "This room is not accepting messages (\(status.rawValue))."
        case .conflict(let current):
            return "The room task is \(current.rawValue); that action is not available."
        case .notOwner(let owner):
            return "Only the room's task owner or the Orchestrator can do that"
                + (owner.map { " (owner: \($0.uuidString))" } ?? "")
                + "."
        case .unknownRoom:
            return "No task is assigned to this room."
        }
    }
}
