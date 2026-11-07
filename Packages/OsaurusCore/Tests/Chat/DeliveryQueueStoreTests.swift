//
//  DeliveryQueueStoreTests.swift
//  osaurusTests
//
//  Slice 2 (issue #16): the durable delivery ledger records admission,
//  survives a relaunch, and turns rows left active by a dead process into
//  `interrupted` instead of pretending they are still live.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite(.serialized)
struct DeliveryQueueStoreTests {
    @Test("a queued row survives a new store instance")
    func roundTrip() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let record = makeRecord(status: .queued)

        try await fixture.store.enqueue(record)
        let reloaded = try DeliveryQueueStore(directory: fixture.directory)
        let pending = await reloaded.pending()

        #expect(pending.count == 1)
        #expect(pending.first?.id == record.id)
        #expect(pending.first?.prompt == record.prompt)
        #expect(pending.first?.mailboxWake == record.mailboxWake)
    }

    @Test("starting records an attempt and a terminal state clears pending")
    func lifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let record = makeRecord(status: .queued)
        try await fixture.store.enqueue(record)

        try await fixture.store.markStarting(id: record.id)
        let started = await fixture.store.record(id: record.id)
        #expect(started?.status == .starting)
        #expect(started?.attempts == 1)
        #expect(started?.startedAt != nil)

        try await fixture.store.markRunning(id: record.id)
        #expect(await fixture.store.record(id: record.id)?.status == .running)

        try await fixture.store.markFinished(
            id: record.id,
            status: .failed,
            error: "provider refused"
        )
        let finished = await fixture.store.record(id: record.id)
        #expect(finished?.status == .failed)
        #expect(finished?.error == "provider refused")
        #expect(finished?.finishedAt != nil)
        #expect(await fixture.store.pending().isEmpty)
    }

    @Test("launch recovery interrupts every active row")
    func launchRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let queued = makeRecord(status: .queued, createdAt: Date(timeIntervalSince1970: 1))
        let running = makeRecord(status: .running, createdAt: Date(timeIntervalSince1970: 2))
        let done = makeRecord(status: .completed, createdAt: Date(timeIntervalSince1970: 3))
        for record in [queued, running, done] {
            try await fixture.store.enqueue(record)
        }

        let recovered = try await fixture.store.markInterruptedOnLaunch()
        #expect(Set(recovered.map(\.id)) == Set([queued.id, running.id]))
        #expect(await fixture.store.record(id: queued.id)?.status == .interrupted)
        #expect(await fixture.store.record(id: running.id)?.status == .interrupted)
        #expect(await fixture.store.record(id: done.id)?.status == .completed)
        #expect(await fixture.store.pending().isEmpty)

        // A second launch has nothing left to interrupt.
        let second = try await fixture.store.markInterruptedOnLaunch()
        #expect(second.isEmpty)
    }

    @Test("re-enqueueing the same id replaces the row")
    func idempotentEnqueue() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var record = makeRecord(status: .queued)
        try await fixture.store.enqueue(record)
        record.title = "updated"
        try await fixture.store.enqueue(record)

        let all = await fixture.store.all()
        #expect(all.count == 1)
        #expect(all.first?.title == "updated")
    }

    @Test("terminal rows are bounded while active rows are kept")
    func terminalRetentionBound() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let base = Date(timeIntervalSince1970: 1_000)
        for offset in 0 ... (DeliveryQueueSchema.terminalRetentionLimit + 4) {
            var record = makeRecord(
                status: .completed,
                createdAt: base.addingTimeInterval(Double(offset))
            )
            record.finishedAt = base.addingTimeInterval(Double(offset))
            try await fixture.store.enqueue(record)
        }
        let active = makeRecord(status: .running, createdAt: base.addingTimeInterval(10_000))
        try await fixture.store.enqueue(active)

        let all = await fixture.store.all()
        let terminal = all.filter { !$0.status.isActive }
        #expect(terminal.count == DeliveryQueueSchema.terminalRetentionLimit)
        #expect(all.contains { $0.id == active.id })
    }

    @Test("editing a prompt only rewrites a row that has not started")
    func updatePromptOnlyWhileQueued() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let record = makeRecord(status: .queued)
        try await fixture.store.enqueue(record)

        let edited = try await fixture.store.updatePrompt(id: record.id, prompt: "edited")
        #expect(edited)
        #expect(await fixture.store.record(id: record.id)?.prompt == "edited")

        try await fixture.store.markStarting(id: record.id)
        let late = try await fixture.store.updatePrompt(id: record.id, prompt: "too late")
        #expect(!late)
        #expect(await fixture.store.record(id: record.id)?.prompt == "edited")
    }

    @Test("only rows whose stored fields rebuild the same run are resumable")
    func resumablePolicy() {
        var local = makeRecord(status: .interrupted)
        #expect(local.isResumable)

        local.status = .running
        #expect(!local.isResumable)

        var delegation = makeRecord(status: .interrupted)
        delegation.source = .delegation
        #expect(!delegation.isResumable)

        var workspace = makeRecord(status: .interrupted)
        workspace.source = .workspace
        #expect(!workspace.isResumable)

        var anonymous = makeRecord(status: .interrupted)
        anonymous.agentId = nil
        #expect(!anonymous.isResumable)
    }

    @Test("a plugin origin survives the round trip")
    func pluginOriginRoundTrip() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var record = makeRecord(status: .queued)
        record.source = .plugin
        record.sourcePluginId = "com.example.demo"
        try await fixture.store.enqueue(record)

        let reloaded = try DeliveryQueueStore(directory: fixture.directory)
        let stored = await reloaded.record(id: record.id)
        #expect(stored?.source == .plugin)
        #expect(stored?.sourcePluginId == "com.example.demo")
    }

    @Test("one idempotency key owns one row")
    func idempotencyKeyDeduplicates() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var first = makeRecord(status: .queued)
        first.idempotencyKey = "http-request-1"
        var second = makeRecord(status: .queued)
        second.idempotencyKey = "http-request-1"

        #expect(try await fixture.store.enqueue(first) == .inserted)
        let outcome = try await fixture.store.enqueue(second)
        guard case .duplicate(let existing) = outcome else {
            Issue.record("the second keyed enqueue was not refused: \(outcome)")
            return
        }
        #expect(existing.id == first.id)
        #expect(await fixture.store.all().count == 1)
        #expect(await fixture.store.delivery(idempotencyKey: "http-request-1")?.id == first.id)
    }

    @Test("a completed row still owns its key")
    func idempotencyKeyOutlivesTheRun() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var first = makeRecord(status: .queued)
        first.idempotencyKey = "retry-me"
        try await fixture.store.enqueue(first)
        try await fixture.store.markStarting(id: first.id)
        try await fixture.store.markFinished(id: first.id, status: .completed)

        var retry = makeRecord(status: .queued)
        retry.idempotencyKey = "retry-me"
        guard case .duplicate(let existing) = try await fixture.store.enqueue(retry) else {
            Issue.record("a completed row released its idempotency key")
            return
        }
        #expect(existing.status == .completed)
        #expect(await fixture.store.all().count == 1)
    }

    @Test("re-enqueueing the same id with its key replaces the row")
    func sameIdReplacesDespiteKey() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var record = makeRecord(status: .queued)
        record.idempotencyKey = "resumed"
        try await fixture.store.enqueue(record)

        try await fixture.store.markFinished(id: record.id, status: .cancelled, error: "resumed")
        let outcome = try await fixture.store.enqueue(record)
        #expect(outcome == .inserted)
        #expect(await fixture.store.all().count == 1)
        #expect(await fixture.store.record(id: record.id)?.status == .queued)
    }

    @Test("blank keys never claim a row")
    func blankIdempotencyKeysIgnored() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        for _ in 0 ..< 2 {
            var record = makeRecord(status: .queued)
            record.idempotencyKey = "   "
            try await fixture.store.enqueue(record)
        }
        #expect(await fixture.store.all().count == 2)
        #expect(await fixture.store.delivery(idempotencyKey: "  ") == nil)
    }

    // MARK: - Fixtures

    private func makeRecord(
        status: DeliveryStatus,
        createdAt: Date = Date()
    ) -> DeliveryRecord {
        DeliveryRecord(
            id: UUID(),
            agentId: UUID(),
            taskId: UUID(),
            source: .mailbox,
            title: "mailbox task",
            prompt: "do the work",
            externalSessionKey: "mailbox-\(UUID().uuidString)",
            mailboxWake: MailboxWakeContext(
                envelopeId: UUID(),
                runId: "run-1",
                senderParticipantId: "local:\(UUID().uuidString.lowercased())",
                recipientAgentId: UUID()
            ),
            status: status,
            createdAt: createdAt
        )
    }

    private struct Fixture {
        let directory: URL
        let store: DeliveryQueueStore

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "delivery-queue-\(UUID().uuidString)",
                isDirectory: true
            )
            store = try DeliveryQueueStore(directory: directory)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
