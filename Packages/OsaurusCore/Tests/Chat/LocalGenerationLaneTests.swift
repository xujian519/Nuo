//
//  LocalGenerationLaneTests.swift
//  osaurusTests
//
//  A headless dispatch and a chat window share one local generation slot.
//  `ChatSession.send` drops a send while another window holds it — correct for
//  the interactive caller, which shows a busy alert, and silently fatal for a
//  dispatched run: its task stayed registered, its delivery row stayed
//  `starting`, and no model ever loaded (issue #15).
//
//  These pin the two halves of the fix: the bounded wait before a start is
//  reported, and the explicit refusal that replaces the silent drop.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite(.serialized)
@MainActor
struct LocalGenerationLaneTests {
    @Test("a dispatcher start reports the busy slot instead of handing a prompt to a send that no-ops")
    func startRefusesWhenSlotBusy() async {
        let context = ExecutionContext(agentId: UUID())
        context.localModelBusyProbe = { true }

        let failure = await context.start(prompt: "hello")

        #expect(failure == ExecutionContext.localModelBusyMessage)
        #expect(context.chatSession.lastStreamError == ExecutionContext.localModelBusyMessage)
        #expect(context.chatSession.turns.isEmpty, "a refused start must not append a user turn")
    }

    @Test("a busy slot never starts the run: the bounded wait reports the busy text")
    func busyLaneRefuses() async throws {
        let fixture = try LaneFixture()
        defer {
            BackgroundTaskManager.localLaneWaitLimitForTesting = nil
            fixture.cleanup()
        }
        BackgroundTaskManager.localLaneWaitLimitForTesting = .milliseconds(120)

        let state = fixture.runningTask(title: "wake", slotBusy: true)
        let context = try #require(state.executionContext)

        let failure = await fixture.manager.awaitLocalModelLaneForTesting(context: context, state: state)

        #expect(failure == ExecutionContext.localModelBusyMessage)
        #expect(state.status.isActive, "a lane timeout is reported to the caller, not decided here")
        #expect(
            await fixture.store.record(id: state.id) == nil,
            "the wait must not write a start for a run it never begins"
        )
    }

    @Test("a free slot returns at once")
    func freeLaneReturnsImmediately() async throws {
        let fixture = try LaneFixture()
        defer { fixture.cleanup() }
        let state = fixture.runningTask(title: "wake", slotBusy: false)
        let context = try #require(state.executionContext)

        let failure = await fixture.manager.awaitLocalModelLaneForTesting(context: context, state: state)

        #expect(failure == nil)
    }

    @Test("a run parked on the slot is resumed as soon as the slot frees")
    func parkedRunResumesWhenSlotFrees() async throws {
        let fixture = try LaneFixture()
        defer { fixture.cleanup() }
        let state = fixture.runningTask(title: "wake", slotBusy: true)
        let context = try #require(state.executionContext)

        let wait = Task { @MainActor in
            await fixture.manager.awaitLocalModelLaneForTesting(context: context, state: state)
        }
        try await waitUntil { fixture.manager.isWaitingOnLocalLaneForTesting(state.id) }

        context.localModelBusyProbe = { false }
        let failure = await wait.value

        #expect(failure == nil, "the wake must proceed once the blocking turn ends")
    }

    @Test("the start watchdog re-arms instead of interrupting a run parked on the slot")
    func watchdogReArmsDuringLaneWait() async throws {
        let fixture = try LaneFixture()
        defer {
            BackgroundTaskManager.startWatchdogLimitForTesting = nil
            fixture.cleanup()
        }
        BackgroundTaskManager.startWatchdogLimitForTesting = .milliseconds(50)

        let state = fixture.runningTask(title: "wake", slotBusy: true)
        let context = try #require(state.executionContext)
        try await fixture.store.enqueue(
            DeliveryRecord(
                id: state.id,
                agentId: fixture.agentId,
                taskId: state.id,
                source: .mailbox,
                title: "wake",
                prompt: "wait for the slot",
                status: .queued,
                createdAt: Date()
            )
        )
        try await fixture.store.markStarting(id: state.id)
        fixture.manager.registerTaskForTesting(state)

        let wait = Task { @MainActor in
            await fixture.manager.awaitLocalModelLaneForTesting(context: context, state: state)
        }
        try await waitUntil { fixture.manager.isWaitingOnLocalLaneForTesting(state.id) }
        fixture.manager.armStartWatchdogForTesting(taskId: state.id, queue: fixture.store)

        // Two watchdog periods pass while the slot is busy. A user turn that
        // outlives the start watchdog is not a wedged start.
        try await Task.sleep(for: .milliseconds(300))
        #expect(await fixture.store.record(id: state.id)?.status == .starting)

        context.localModelBusyProbe = { false }
        _ = await wait.value
    }
}

@MainActor
private final class LaneFixture {    let agentId = UUID()
    let manager: BackgroundTaskManager
    let store: DeliveryQueueStore
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "local-lane-\(UUID().uuidString)",
            isDirectory: true
        )
        store = try DeliveryQueueStore(directory: directory)
        manager = BackgroundTaskManager.makeForTesting(deliveryQueue: store)
    }

    func runningTask(title: String, slotBusy: Bool) -> BackgroundTaskState {
        let context = ExecutionContext(agentId: agentId)
        context.localModelBusyProbe = { slotBusy }
        return BackgroundTaskState(
            id: UUID(),
            taskTitle: title,
            agentId: agentId,
            chatSession: context.chatSession,
            executionContext: context,
            status: .running,
            currentStep: "Running..."
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(3),
    _ predicate: @MainActor @escaping () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw NSError(domain: "LocalGenerationLaneTests", code: 1)
}
