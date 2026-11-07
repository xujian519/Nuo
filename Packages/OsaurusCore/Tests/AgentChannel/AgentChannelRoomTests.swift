//
//  AgentChannelRoomTests.swift
//  osaurusTests
//
//  Slice 4 (issue #18): room task ownership is durable, one room has one
//  owner, assignment is race-safe, and the lifecycle actions (Stop / Resume /
//  Reassign / Archive / Restore) are validated transitions.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite(.serialized)
struct AgentChannelRoomStoreTests {
    private func makeStore() throws -> (store: AgentChannelRoomStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "channel-rooms-\(UUID().uuidString)",
            isDirectory: true
        )
        return (try AgentChannelRoomStore(directory: directory), directory)
    }

    @Test("the first claim assigns; later claims keep the owner")
    func claimAssignsOnce() async throws {
        let fixture = try makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = try await fixture.store.claim(
            connectionId: "slack",
            roomId: "C1",
            proposedAgentId: UUID(),
            taskId: nil,
            externalSessionKey: nil
        )
        #expect(first.assignedOwner)
        let owner = try #require(first.record.ownerAgentId)

        let other = UUID()
        let second = try await fixture.store.claim(
            connectionId: "slack",
            roomId: "C1",
            proposedAgentId: other,
            taskId: nil,
            externalSessionKey: nil
        )
        #expect(!second.assignedOwner)
        #expect(second.record.ownerAgentId == owner)
        #expect(await fixture.store.all().count == 1)
    }

    @Test("two simultaneous assignments produce one winner and one conflict")
    func concurrentAssignment() async throws {
        let fixture = try makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let roomId = "C-race"
        let first = UUID()
        let second = UUID()

        async let a: Result<AgentChannelRoomRecord, AgentChannelRoomError> = {
            do {
                return .success(
                    try await fixture.store.assign(
                        connectionId: "slack",
                        roomId: roomId,
                        agentId: first
                    )
                )
            } catch let error as AgentChannelRoomError {
                return .failure(error)
            }
        }()
        async let b: Result<AgentChannelRoomRecord, AgentChannelRoomError> = {
            do {
                return .success(
                    try await fixture.store.assign(
                        connectionId: "slack",
                        roomId: roomId,
                        agentId: second
                    )
                )
            } catch let error as AgentChannelRoomError {
                return .failure(error)
            }
        }()
        let resultA = try await a
        let resultB = try await b
        let results = [resultA, resultB]
        let winners = results.filter { if case .success = $0 { return true } else { return false } }
        let losers = results.filter { if case .failure = $0 { return true } else { return false } }
        #expect(winners.count == 1)
        #expect(losers.count == 1)
        if case .failure(let error) = losers[0] {
            #expect(error == .conflict(current: .assigned))
        }
        let stored = await fixture.store.room(connectionId: "slack", roomId: roomId)
        let record = try #require(stored)
        #expect(record.status == .assigned)
        #expect(record.ownerAgentId == first || record.ownerAgentId == second)
    }

    @Test("a running turn moves the record through running and back to idle")
    func turnLifecycle() async throws {
        let fixture = try makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let agent = UUID()
        let taskId = UUID()
        try await fixture.store.claim(
            connectionId: "slack",
            roomId: "C2",
            proposedAgentId: agent,
            taskId: nil,
            externalSessionKey: "channel-1"
        )
        try await fixture.store.markRunning(
            connectionId: "slack",
            roomId: "C2",
            taskId: taskId,
            externalSessionKey: "channel-1"
        )
        let storedRecord = await fixture.store.room(connectionId: "slack", roomId: "C2")
        var record = try #require(storedRecord)
        #expect(record.status == .running)
        #expect(record.taskId == taskId)

        try await fixture.store.markWaiting(connectionId: "slack", roomId: "C2", taskId: taskId)
        let waitingRecord = await fixture.store.room(connectionId: "slack", roomId: "C2")
        record = try #require(waitingRecord)
        #expect(record.status == .waiting)

        // A waiting question is not a finished turn; finishTurn leaves it.
        try await fixture.store.finishTurn(connectionId: "slack", roomId: "C2")
        let stillWaiting = await fixture.store.room(connectionId: "slack", roomId: "C2")
        record = try #require(stillWaiting)
        #expect(record.status == .waiting)

        try await fixture.store.markRunning(connectionId: "slack", roomId: "C2", taskId: taskId)
        try await fixture.store.finishTurn(connectionId: "slack", roomId: "C2")
        let idleRecord = await fixture.store.room(connectionId: "slack", roomId: "C2")
        record = try #require(idleRecord)
        #expect(record.status == .idle)
        #expect(record.ownerAgentId == agent)
        #expect(record.taskId == taskId)
    }

    @Test("stop refuses messages and resume restores the same task")
    func stopAndResume() async throws {
        let fixture = try makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let agent = UUID()
        let taskId = UUID()
        try await fixture.store.claim(
            connectionId: "slack",
            roomId: "C3",
            proposedAgentId: agent,
            taskId: nil,
            externalSessionKey: nil
        )
        try await fixture.store.markRunning(connectionId: "slack", roomId: "C3", taskId: taskId)
        try await fixture.store.stop(connectionId: "slack", roomId: "C3")

        do {
            _ = try await fixture.store.claim(
                connectionId: "slack",
                roomId: "C3",
                proposedAgentId: agent,
                taskId: nil,
                externalSessionKey: nil
            )
            Issue.record("a stopped room accepted a new message")
        } catch let error as AgentChannelRoomError {
            #expect(error == .unavailable(.stopped))
        }

        let resumed = try await fixture.store.resume(connectionId: "slack", roomId: "C3")
        #expect(resumed.status == .assigned)
        #expect(resumed.ownerAgentId == agent)
        #expect(resumed.taskId == taskId)
    }

    @Test("archive refuses messages and restore returns the previous state")
    func archiveAndRestore() async throws {
        let fixture = try makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let agent = UUID()
        try await fixture.store.claim(
            connectionId: "slack",
            roomId: "C4",
            proposedAgentId: agent,
            taskId: nil,
            externalSessionKey: "channel-4"
        )
        try await fixture.store.markRunning(connectionId: "slack", roomId: "C4", taskId: UUID())
        let archived = try await fixture.store.archive(connectionId: "slack", roomId: "C4")
        #expect(archived.status == .archived)
        #expect(archived.statusBeforeArchive == .running)

        do {
            _ = try await fixture.store.claim(
                connectionId: "slack",
                roomId: "C4",
                proposedAgentId: agent,
                taskId: nil,
                externalSessionKey: nil
            )
            Issue.record("an archived room accepted a new message")
        } catch let error as AgentChannelRoomError {
            #expect(error == .unavailable(.archived))
        }

        let restored = try await fixture.store.restore(connectionId: "slack", roomId: "C4")
        #expect(restored.status == .running)
        #expect(restored.ownerAgentId == agent)
        #expect(restored.externalSessionKey == "channel-4")
        #expect(restored.archivedAt == nil)
    }

    @Test("reassign moves ownership and drops the old task lane")
    func reassign() async throws {
        let fixture = try makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = UUID()
        let second = UUID()
        try await fixture.store.claim(
            connectionId: "slack",
            roomId: "C5",
            proposedAgentId: first,
            taskId: nil,
            externalSessionKey: "channel-5"
        )
        try await fixture.store.markRunning(connectionId: "slack", roomId: "C5", taskId: UUID())
        let record = try await fixture.store.reassign(
            connectionId: "slack",
            roomId: "C5",
            agentId: second
        )
        #expect(record.ownerAgentId == second)
        #expect(record.taskId == nil)
        #expect(record.externalSessionKey == nil)
        #expect(record.status == .assigned)
    }

    @Test("ownership survives a new store instance")
    func persistence() async throws {
        let fixture = try makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let agent = UUID()
        try await fixture.store.claim(
            connectionId: "slack",
            roomId: "C6",
            proposedAgentId: agent,
            taskId: nil,
            externalSessionKey: "channel-6"
        )
        try await fixture.store.markRunning(connectionId: "slack", roomId: "C6", taskId: UUID())

        let reloaded = try AgentChannelRoomStore(directory: fixture.directory)
        let stored = await reloaded.room(connectionId: "slack", roomId: "C6")
        let record = try #require(stored)
        #expect(record.ownerAgentId == agent)
        #expect(record.status == .running)
        #expect(record.externalSessionKey == "channel-6")
    }
}

@Suite(.serialized)
@MainActor
struct AgentChannelRoomServiceTests {
    private func makeService() throws -> (
        service: AgentChannelRoomService,
        store: AgentChannelRoomStore,
        cancelled: RoomCallRecorder<UUID>,
        directory: URL
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "channel-room-service-\(UUID().uuidString)",
            isDirectory: true
        )
        let store = try AgentChannelRoomStore(directory: directory)
        let cancelled = RoomCallRecorder<UUID>()
        let service = AgentChannelRoomService(
            store: store,
            cancelTask: { cancelled.append($0) },
            isTaskActive: { _ in true },
            audit: { _, _, _, _ in }
        )
        return (service, store, cancelled, directory)
    }

    @Test("stop cancels the live task and keeps the row")
    func stopCancels() async throws {
        let fixture = try makeService()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let agent = UUID()
        let taskId = UUID()
        _ = try await fixture.service.claim(
            connectionId: "slack",
            roomId: "C1",
            proposedAgentId: agent
        )
        await fixture.service.markRunning(connectionId: "slack", roomId: "C1", taskId: taskId)

        let record = try await fixture.service.stop(connectionId: "slack", roomId: "C1")
        #expect(record.status == .stopped)
        #expect(fixture.cancelled.values == [taskId])
        #expect(fixture.service.acceptsMessages(connectionId: "slack", roomId: "C1") == false)

        let resumed = try await fixture.service.resume(connectionId: "slack", roomId: "C1")
        #expect(resumed.status == .assigned)
        #expect(fixture.service.acceptsMessages(connectionId: "slack", roomId: "C1"))
    }

    @Test("only the owner or the Orchestrator may act")
    func permission() async throws {
        let fixture = try makeService()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let owner = UUID()
        let stranger = UUID()
        _ = try await fixture.service.claim(
            connectionId: "slack",
            roomId: "C2",
            proposedAgentId: owner
        )

        do {
            _ = try await fixture.service.stop(
                connectionId: "slack",
                roomId: "C2",
                requestedBy: stranger
            )
            Issue.record("a stranger stopped the room")
        } catch let error as AgentChannelRoomError {
            #expect(error == .notOwner(owner: owner))
        }
        _ = try await fixture.service.stop(
            connectionId: "slack",
            roomId: "C2",
            requestedBy: Agent.defaultId
        )
        let record = try await fixture.service.resume(
            connectionId: "slack",
            roomId: "C2",
            requestedBy: owner
        )
        #expect(record.status == .assigned)
    }

    @Test("reassign cancels the old lane and moves the owner")
    func reassignCancels() async throws {
        let fixture = try makeService()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = UUID()
        let second = UUID()
        let taskId = UUID()
        _ = try await fixture.service.claim(
            connectionId: "slack",
            roomId: "C3",
            proposedAgentId: first
        )
        await fixture.service.markRunning(connectionId: "slack", roomId: "C3", taskId: taskId)

        let record = try await fixture.service.reassign(
            connectionId: "slack",
            roomId: "C3",
            agentId: second
        )
        #expect(record.ownerAgentId == second)
        #expect(fixture.cancelled.values == [taskId])
    }

    @Test("archive cancels and restore re-opens the room")
    func archiveCancels() async throws {
        let fixture = try makeService()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let taskId = UUID()
        _ = try await fixture.service.claim(
            connectionId: "slack",
            roomId: "C4",
            proposedAgentId: UUID()
        )
        await fixture.service.markRunning(connectionId: "slack", roomId: "C4", taskId: taskId)
        _ = try await fixture.service.archive(connectionId: "slack", roomId: "C4")
        #expect(fixture.cancelled.values == [taskId])
        #expect(!fixture.service.acceptsMessages(connectionId: "slack", roomId: "C4"))

        let restored = try await fixture.service.restore(connectionId: "slack", roomId: "C4")
        #expect(restored.status == .running)
        #expect(fixture.service.acceptsMessages(connectionId: "slack", roomId: "C4"))
    }
}

/// Minimal reference box so a @MainActor closure can record calls.
@MainActor
final class RoomCallRecorder<Value> {
    private(set) var values: [Value] = []
    func append(_ value: Value) { values.append(value) }
}
