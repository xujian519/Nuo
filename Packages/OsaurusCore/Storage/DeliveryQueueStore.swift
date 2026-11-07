//
//  DeliveryQueueStore.swift
//  osaurus
//
//  Crash-safe JSON store for the background delivery queue. One process owns
//  the file; an actor serialises every mutation, and each write replaces the
//  file atomically. The queue is a recovery ledger, not a second scheduler:
//  `BackgroundTaskManager` remains the executor.
//

import Foundation

public actor DeliveryQueueStore {
    /// The production store, or nil when the app data directory is not
    /// writable yet. A nil store disables the ledger; the in-memory queue and
    /// the executor keep working.
    public nonisolated static func production() -> DeliveryQueueStore? {
        try? DeliveryQueueStore(directory: OsaurusPaths.deliveryQueueDirectory())
    }

    public nonisolated let fileURL: URL
    private var deliveries: [DeliveryRecord]

    public init(directory: URL) throws {
        self.fileURL = directory.appendingPathComponent(DeliveryQueueSchema.fileName, isDirectory: false)
        self.deliveries = try Self.read(fileURL)
    }

    // MARK: - Writes

    /// Adds a queued row. Re-enqueueing the same id replaces the row, so a
    /// retried dispatch does not duplicate work. A different id carrying an
    /// idempotency key that already exists is refused; the caller sees the
    /// first row and must not start a second turn.
    @discardableResult
    public func enqueue(_ record: DeliveryRecord) throws -> DeliveryEnqueueOutcome {
        if let key = Self.normalizedKey(record.idempotencyKey),
            let existing = deliveries.first(where: { $0.idempotencyKey == key && $0.id != record.id })
        {
            return .duplicate(existing)
        }
        if let index = deliveries.firstIndex(where: { $0.id == record.id }) {
            deliveries[index] = record
        } else {
            deliveries.append(record)
        }
        try persist()
        return .inserted
    }

    public func markStarting(id: UUID, at date: Date = Date()) throws {
        try update(id: id) { record in
            guard record.status == .queued else { return }
            record.status = .starting
            record.startedAt = date
            record.attempts += 1
        }
    }

    /// The chat turn is streaming. Only `starting` advances here; a repeated
    /// streaming tick is a no-op.
    public func markRunning(id: UUID) throws {
        try update(id: id) { record in
            guard record.status == .starting else { return }
            record.status = .running
        }
    }

    public func markFinished(
        id: UUID,
        status: DeliveryStatus,
        error: String? = nil,
        at date: Date = Date()
    ) throws {
        guard !status.isActive else { return }
        try update(id: id) { record in
            record.status = status
            record.finishedAt = date
            record.error = error
        }
    }

    /// Rewrites the prompt of a row that has not started. Returns false when
    /// the row is missing or already started; a started row keeps the text
    /// that actually ran.
    @discardableResult
    public func updatePrompt(id: UUID, prompt: String) throws -> Bool {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
            deliveries[index].status == .queued
        else { return false }
        deliveries[index].prompt = prompt
        try persist()
        return true
    }

    /// Called once at launch. Every row that still claims to be active was
    /// running when the previous process stopped; it becomes `interrupted`
    /// so a later resume decision never mistakes it for live work.
    @discardableResult
    public func markInterruptedOnLaunch(at date: Date = Date()) throws -> [DeliveryRecord] {
        var recovered: [DeliveryRecord] = []
        for index in deliveries.indices where deliveries[index].status.isActive {
            deliveries[index].status = .interrupted
            deliveries[index].finishedAt = date
            recovered.append(deliveries[index])
        }
        if !recovered.isEmpty { try persist() }
        return recovered
    }

    /// Removes a row entirely. Used by tests and by an explicit discard.
    public func remove(id: UUID) throws {
        deliveries.removeAll { $0.id == id }
        try persist()
    }

    // MARK: - Reads

    public func record(id: UUID) -> DeliveryRecord? {
        deliveries.first { $0.id == id }
    }

    /// The row that claimed `key`, whether it is still active or already
    /// terminal. A retry must not start a second turn for a delivery whose
    /// effect already happened.
    public func delivery(idempotencyKey: String) -> DeliveryRecord? {
        guard let key = Self.normalizedKey(idempotencyKey) else { return nil }
        return deliveries.first { $0.idempotencyKey == key }
    }

    public func all() -> [DeliveryRecord] {
        deliveries
    }

    public func pending() -> [DeliveryRecord] {
        deliveries
            .filter { $0.status.isActive }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Persistence

    static func normalizedKey(_ key: String?) -> String? {
        guard let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private func update(id: UUID, _ body: (inout DeliveryRecord) -> Void) throws {
        guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
        body(&deliveries[index])
        try persist()
    }

    private func persist() throws {
        try Self.trimTerminalRows(&deliveries)
        let snapshot = DeliveryQueueSnapshot(
            schema: DeliveryQueueSchema.current,
            deliveries: deliveries
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private static func read(_ url: URL) throws -> [DeliveryRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(DeliveryQueueSnapshot.self, from: data)
        guard snapshot.schema == DeliveryQueueSchema.current else {
            throw DeliveryQueueError.unsupportedSchema(snapshot.schema)
        }
        return snapshot.deliveries
    }

    /// Keep every active row and the newest terminal rows. The bound is on
    /// the file, not on what the Activity UI can show.
    private static func trimTerminalRows(_ rows: inout [DeliveryRecord]) {
        let terminal = rows.enumerated()
            .filter { !$0.element.status.isActive }
            .sorted { lhs, rhs in
                (lhs.element.finishedAt ?? lhs.element.createdAt)
                    > (rhs.element.finishedAt ?? rhs.element.createdAt)
            }
        let excess = terminal.dropFirst(DeliveryQueueSchema.terminalRetentionLimit)
        guard !excess.isEmpty else { return }
        let dropIds = Set(excess.map { $0.element.id })
        rows.removeAll { dropIds.contains($0.id) }
    }
}

public enum DeliveryEnqueueOutcome: Sendable, Equatable {
    case inserted
    /// Another row already owns this idempotency key.
    case duplicate(DeliveryRecord)

    public var insertedRow: Bool {
        if case .inserted = self { return true }
        return false
    }
}

public enum DeliveryQueueError: Error, Equatable, LocalizedError {    case unsupportedSchema(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            return "Unsupported delivery queue schema: \(schema)"
        }
    }
}
