//
//  MailboxWake.swift
//  osaurus
//
//  ADR-Nuo-002 follow-up: a directed-mailbox `send` wakes the recipient once.
//  The wake context travels with the dispatch so the run can be attributed to
//  the envelope that caused it, and so recovery work in slice 2 can tell a
//  mailbox turn apart from a schedule or channel turn.
//

import Foundation

/// Provenance for one automatic mailbox turn.
public struct MailboxWakeContext: Sendable, Equatable, Codable {
    /// The envelope that caused the wake.
    public var envelopeId: UUID
    /// The collaboration run the envelope belongs to.
    public var runId: String
    /// `local:<uuid>` of the agent that sent the message.
    public var senderParticipantId: String
    /// The agent that runs this turn.
    public var recipientAgentId: UUID

    public init(
        envelopeId: UUID,
        runId: String,
        senderParticipantId: String,
        recipientAgentId: UUID
    ) {
        self.envelopeId = envelopeId
        self.runId = runId
        self.senderParticipantId = senderParticipantId
        self.recipientAgentId = recipientAgentId
    }
}

public enum MailboxWakePolicy {
    /// One agent may be woken this many times per rolling hour. A bot that
    /// messages in a loop spends its own quota, not the machine's.
    public static let maxPerAgentPerHour = 6
    /// A local model runs one turn at a time. More than one mailbox turn would
    /// make two lanes fight over the resident model and thrash the handoff.
    public static let maxConcurrentTurns = 1
    /// A reply body is a digest, not a transcript. Keep it inside the
    /// collaboration token budget's neighborhood.
    public static let replyTextLimit = 8_000
    /// The body is quoted in the prompt; cap it so a large envelope cannot
    /// crowd out the recipient agent's own instructions.
    public static let promptBodyLimit = 6_000
}

public enum MailboxWakeSkipReason: String, Sendable, Equatable {
    case notARequest
    case notLocalRecipient
    case quotaExceeded
    case turnInFlight
    case dispatchRefused
    case noResult
}

/// The wake path reports skips instead of throwing: a mailbox send must still
/// succeed when the recipient cannot run right now.
public struct MailboxWakeOutcome: Sendable, Equatable {
    public var delivered: Bool
    public var skip: MailboxWakeSkipReason?

    public static let delivered = MailboxWakeOutcome(delivered: true)
    public static func skipped(_ reason: MailboxWakeSkipReason) -> MailboxWakeOutcome {
        MailboxWakeOutcome(delivered: false, skip: reason)
    }
}
