//
//  DeliveryQueue.swift
//  osaurus
//
//  Durable form of the background chat queue (slice 2, issue #16). A record
//  is written before a dispatch is registered and updated as the task moves
//  through its lifecycle, so a relaunch can tell what was running, what was
//  waiting, and what never started.
//

import Foundation

public enum DeliveryQueueSchema {
    public static let current = "osaurus.delivery-queue.v1"
    public static let fileName = "deliveries.json"
    /// Terminal rows are history, not work. Keeping a bounded tail stops the
    /// file from growing with every schedule and mailbox tick.
    public static let terminalRetentionLimit = 500
}

public enum DeliveryStatus: String, Codable, Sendable, CaseIterable {
    /// Waiting for a free slot.
    case queued
    /// Admitted; the execution context is being prepared.
    case starting
    /// The chat turn is streaming.
    case running
    case completed
    case failed
    /// The process stopped while this row was active. Recovery marks it and
    /// leaves the restart decision to the user or a later policy.
    case interrupted
    case cancelled

    public var isActive: Bool {
        switch self {
        case .queued, .starting, .running: return true
        case .completed, .failed, .interrupted, .cancelled: return false
        }
    }
}

public struct DeliveryRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var agentId: UUID?
    /// The task lane this delivery belongs to. Today it equals `id`; side
    /// threads in a later slice give it a distinct value.
    public var taskId: UUID?
    public var source: SessionSource
    /// Plugin that originated the dispatch, when there is one. A resumed
    /// plugin run must route its events back to the same plugin.
    public var sourcePluginId: String?
    public var title: String?
    public var prompt: String
    public var externalSessionKey: String?
    public var mailboxWake: MailboxWakeContext?
    /// Caller-supplied de-duplication key. The store keeps at most one row per
    /// key for the life of the ledger.
    public var idempotencyKey: String?
    public var status: DeliveryStatus
    public var attempts: Int
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var error: String?

    public init(
        id: UUID,
        agentId: UUID?,
        taskId: UUID?,
        source: SessionSource,
        sourcePluginId: String? = nil,
        title: String?,
        prompt: String,
        externalSessionKey: String? = nil,
        mailboxWake: MailboxWakeContext? = nil,
        idempotencyKey: String? = nil,
        status: DeliveryStatus = .queued,
        attempts: Int = 0,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.taskId = taskId
        self.source = source
        self.sourcePluginId = sourcePluginId
        self.title = title
        self.prompt = prompt
        self.externalSessionKey = externalSessionKey
        self.mailboxWake = mailboxWake
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.attempts = attempts
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.error = error
    }

    /// Whether the stored fields reconstruct the same execution shape. A
    /// workspace row ran on a teammate's Mac, and a delegation row carried
    /// budget caps this record does not store; re-dispatching either would
    /// silently change the run. Both stay discardable.
    public var isResumable: Bool {
        guard status == .interrupted, agentId != nil else { return false }
        switch source {
        case .workspace, .delegation: return false
        default: return true
        }
    }
}

struct DeliveryQueueSnapshot: Codable {
    var schema: String
    var deliveries: [DeliveryRecord]
}
