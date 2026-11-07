//
//  DeliveryQueueControlsTests.swift
//  osaurusTests
//
//  Slice 2 (issue #16): a queued delivery can be edited before it starts,
//  reordered within its agent's lane, or cancelled. The ledger is the source
//  of truth for the prompt; the live FIFO decides promotion order.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite(.serialized)
@MainActor
struct DeliveryQueueControlsTests {
    private let agent = UUID()

    @Test("an edit rewrites the queued row and its pending start")
    func editQueuedPrompt() async throws {
        let fixture = try QueueFixture(agentId: agent)
        defer { fixture.cleanup() }
        fixture.fillAgentCap()
        let queued = fixture.queueOneTask(title: "queued")
        try await fixture.enqueue(queued, prompt: "old text")

        let edited = await fixture.manager.editQueuedDelivery(id: queued.id, prompt: "  new text  ")

        #expect(edited)
        #expect(await fixture.store.record(id: queued.id)?.prompt == "new text")
        #expect(fixture.manager.queuedPromptOverrideForTesting(queued.id) == "new text")
        #expect(fixture.manager.queuedDeliveries.first?.prompt == "new text")
    }

    @Test("a started or empty edit is refused")
    func editRefusals() async throws {
        let fixture = try QueueFixture(agentId: agent)
        defer { fixture.cleanup() }
        fixture.fillAgentCap()
        let running = try #require(fixture.fillers.first)
        try await fixture.enqueue(running, prompt: "old text")

        #expect(await fixture.manager.editQueuedDelivery(id: running.id, prompt: "x") == false)
        #expect(await fixture.store.record(id: running.id)?.prompt == "old text")

        let queued = fixture.queueOneTask(title: "queued")
        #expect(await fixture.manager.editQueuedDelivery(id: queued.id, prompt: "   ") == false)
    }

    @Test("a queued delivery moves within its agent lane")
    func reorderQueued() async throws {
        let fixture = try QueueFixture(agentId: agent)
        defer { fixture.cleanup() }
        fixture.fillAgentCap()
        let probeA = StartProbe()
        let probeB = StartProbe()
        let taskA = fixture.queueOneTask(title: "A", start: probeA.makeStart())
        let taskB = fixture.queueOneTask(title: "B", start: probeB.makeStart())

        #expect(fixture.manager.queuedDeliveryIDs == [taskA.id, taskB.id])
        #expect(await fixture.manager.moveQueuedDelivery(id: taskA.id, up: false))
        #expect(fixture.manager.queuedDeliveryIDs == [taskB.id, taskA.id])
        // The head cannot move up, and the tail cannot move down.
        #expect(await fixture.manager.moveQueuedDelivery(id: taskB.id, up: true) == false)
        #expect(await fixture.manager.moveQueuedDelivery(id: taskA.id, up: false) == false)

        // Free one slot: the moved delivery runs first.
        fixture.releaseOneFiller()
        try await waitUntil { probeB.started }
        #expect(probeA.started == false)
    }

    @Test("cancel removes the queued row from the ledger and the list")
    func cancelQueued() async throws {
        let fixture = try QueueFixture(agentId: agent)
        defer { fixture.cleanup() }
        fixture.fillAgentCap()
        let queued = fixture.queueOneTask(title: "queued")
        try await fixture.enqueue(queued, prompt: "do the work")
        await fixture.manager.refreshDeliveries()
        #expect(fixture.manager.queuedDeliveries.count == 1)

        await fixture.manager.cancelDelivery(queued.id)

        #expect(fixture.manager.queuedDeliveries.isEmpty)
        #expect(fixture.manager.queuedDeliveryIDs.isEmpty)
        #expect(await fixture.store.record(id: queued.id)?.status == .cancelled)
    }

    @Test("a used idempotency key resolves to its ledger row")
    func idempotencyLookup() async throws {
        let fixture = try QueueFixture(agentId: agent)
        defer { fixture.cleanup() }
        let state = fixture.queueOneTask(title: "once")
        try await fixture.store.enqueue(
            DeliveryRecord(
                id: state.id,
                agentId: agent,
                taskId: state.id,
                source: .http,
                title: "once",
                prompt: "do it once",
                idempotencyKey: "request-1",
                status: .queued,
                createdAt: Date()
            )
        )

        let replay = DispatchRequest(
            prompt: "do it once",
            agentId: agent,
            showToast: false,
            source: .http,
            idempotencyKey: "request-1"
        )
        #expect(await fixture.manager.existingDelivery(for: replay)?.id == state.id)

        let fresh = DispatchRequest(
            prompt: "another",
            agentId: agent,
            showToast: false,
            source: .http,
            idempotencyKey: "request-2"
        )
        #expect(await fixture.manager.existingDelivery(for: fresh) == nil)
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ predicate: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "DeliveryQueueControlsTests", code: 1)
    }
}

// MARK: - Fixture

@MainActor
private final class QueueFixture {
    let agentId: UUID
    let manager: BackgroundTaskManager
    let store: DeliveryQueueStore
    private(set) var fillers: [BackgroundTaskState] = []
    private var queuedStates: [BackgroundTaskState] = []
    private let directory: URL

    init(agentId: UUID) throws {
        self.agentId = agentId
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "delivery-controls-\(UUID().uuidString)",
            isDirectory: true
        )
        store = try DeliveryQueueStore(directory: directory)
        manager = BackgroundTaskManager.makeForTesting(deliveryQueue: store)
    }

    /// Fill the per-agent cap (5) so the next admission stays queued.
    func fillAgentCap() {
        for index in 0 ..< 5 {
            let state = makeState(title: "filler-\(index)", status: .running)
            manager.registerTaskForTesting(state)
            fillers.append(state)
        }
    }

    func releaseOneFiller() {
        guard let filler = fillers.first else { return }
        manager.finalizeTask(filler.id)
    }

    @discardableResult
    func queueOneTask(
        title: String,
        start: @escaping @MainActor () async -> Void = {}
    ) -> BackgroundTaskState {
        let state = makeState(title: title, status: .queued)
        manager.admitTaskForTesting(state, start: start)
        queuedStates.append(state)
        return state
    }

    func enqueue(_ state: BackgroundTaskState, prompt: String) async throws {
        try await store.enqueue(
            DeliveryRecord(
                id: state.id,
                agentId: agentId,
                taskId: state.id,
                source: .schedule,
                title: state.taskTitle,
                prompt: prompt,
                status: .queued,
                createdAt: Date()
            )
        )
    }

    func cleanup() {
        fillers.forEach { manager.finalizeTask($0.id) }
        queuedStates.forEach { manager.finalizeTask($0.id) }
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeState(title: String, status: BackgroundTaskStatus) -> BackgroundTaskState {
        let context = ExecutionContext(agentId: agentId)
        return BackgroundTaskState(
            id: UUID(),
            taskTitle: title,
            agentId: agentId,
            chatSession: context.chatSession,
            executionContext: context,
            status: status,
            currentStep: status == .running ? "Running..." : nil
        )
    }
}

@MainActor
private final class StartProbe {
    private(set) var started = false
    func makeStart() -> @MainActor () async -> Void {
        { self.started = true }
    }
}
