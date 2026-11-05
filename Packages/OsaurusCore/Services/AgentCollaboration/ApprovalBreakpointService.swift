//
//  ApprovalBreakpointService.swift
//  osaurus
//
//  多步任务在 clarify 或 `.ask` 处停下。检查点记下已完成步骤的输出引用。
//  恢复之前不提交待审批那一步的副作用。
//

import Foundation

public actor ApprovalBreakpointService {
    public nonisolated let directory: URL
    private let indexURL: URL
    private let backlogLimit: Int
    private var runs: [String: ApprovalCheckpoint] = [:]

    public init(directory: URL, backlogLimit: Int = ApprovalBreakpointSchema.defaultBacklogLimit) throws {
        self.directory = directory
        self.indexURL = directory.appendingPathComponent(ApprovalBreakpointSchema.indexFileName)
        self.backlogLimit = max(1, backlogLimit)
        self.runs = try Self.read(self.indexURL)
        if !FileManager.default.fileExists(atPath: self.indexURL.path) {
            try self.persist()
        }
    }

    public func openRun(runId: String) throws -> ApprovalCheckpoint {
        if let existing = runs[runId] {
            return existing
        }
        let created = ApprovalCheckpoint(runId: runId)
        runs[runId] = created
        try persist()
        return created
    }

    public func checkpoint(runId: String) -> ApprovalCheckpoint? {
        runs[runId]
    }

    /// 已经做过的步骤。有未恢复的中断时拒绝，避免提前做下一步。
    public func recordCompleted(
        runId: String,
        toolName: String,
        argumentsJSON: String,
        outputRef: String
    ) throws -> ApprovalCheckpoint {
        guard var run = runs[runId] else {
            throw ApprovalBreakpointError.unknownRun(runId)
        }
        if let pending = run.pending {
            throw ApprovalBreakpointError.pendingInterrupt(runId: runId, stepIndex: pending.stepIndex)
        }
        let hash = try ApprovalParameterHash.hex(argumentsJSON: argumentsJSON)
        let step = ApprovalCheckpointStep(
            index: run.nextStepIndex,
            toolName: toolName,
            parameterHash: hash,
            outputRef: outputRef
        )
        run.completed.append(step)
        run.nextStepIndex += 1
        runs[runId] = run
        try persist()
        return run
    }

    @discardableResult
    public func interrupt(
        runId: String,
        kind: ApprovalInterruptKind,
        toolName: String,
        argumentsJSON: String,
        now: Date,
        timeout: TimeInterval = ApprovalBreakpointSchema.defaultTimeout
    ) throws -> ApprovalInterrupt {
        guard var run = runs[runId] else {
            throw ApprovalBreakpointError.unknownRun(runId)
        }
        if let pending = run.pending {
            throw ApprovalBreakpointError.pendingInterrupt(runId: runId, stepIndex: pending.stepIndex)
        }
        try expire(now: now)
        let live = runs.values.filter { checkpoint in
            guard let pending = checkpoint.pending else { return false }
            return pending.deadline > now
        }.count
        if live >= backlogLimit {
            throw ApprovalBreakpointError.approvalBacklogFull
        }
        let hash = try ApprovalParameterHash.hex(argumentsJSON: argumentsJSON)
        let pending = ApprovalInterrupt(
            stepIndex: run.nextStepIndex,
            kind: kind,
            toolName: toolName,
            parameterHash: hash,
            requestedAt: now,
            deadline: now.addingTimeInterval(max(0, timeout)),
            resumeAuthorized: false
        )
        run.pending = pending
        runs[runId] = run
        try persist()
        return pending
    }

    /// 只核对工具名和参数哈希。通过后仍不写入副作用。
    @discardableResult
    public func approve(
        runId: String,
        toolName: String,
        parameterHash: String,
        now: Date
    ) throws -> ApprovalInterrupt {
        guard var run = runs[runId] else {
            throw ApprovalBreakpointError.unknownRun(runId)
        }
        guard var pending = run.pending else {
            throw ApprovalBreakpointError.nothingPending(runId)
        }
        if now >= pending.deadline {
            pending.resumeAuthorized = false
            run.pending = pending
            runs[runId] = run
            try persist()
            throw ApprovalBreakpointError.approvalTimedOut(runId)
        }
        guard pending.toolName == toolName, pending.parameterHash == parameterHash else {
            throw ApprovalBreakpointError.mistakenApproval(runId)
        }
        guard !pending.resumeAuthorized else {
            throw ApprovalBreakpointError.alreadyAuthorized(runId)
        }
        pending.resumeAuthorized = true
        run.pending = pending
        runs[runId] = run
        try persist()
        return pending
    }

    public func approve(untrusted envelope: AgentCollaborationEnvelope, now: Date) throws -> ApprovalInterrupt {
        _ = envelope
        _ = now
        throw ApprovalBreakpointError.envelopeRejected
    }

    /// 调用方已经执行完这一步的副作用之后才提交输出引用。
    public func commit(runId: String, outputRef: String) throws -> ApprovalCheckpoint {
        guard var run = runs[runId] else {
            throw ApprovalBreakpointError.unknownRun(runId)
        }
        guard let pending = run.pending else {
            throw ApprovalBreakpointError.nothingPending(runId)
        }
        guard pending.resumeAuthorized else {
            throw ApprovalBreakpointError.resumeNotAuthorized(runId)
        }
        run.completed.append(
            ApprovalCheckpointStep(
                index: pending.stepIndex,
                toolName: pending.toolName,
                parameterHash: pending.parameterHash,
                outputRef: outputRef
            )
        )
        run.nextStepIndex = pending.stepIndex + 1
        run.pending = nil
        runs[runId] = run
        try persist()
        return run
    }

    /// 超时的中断丢掉，不补做那一步。
    public func acknowledgeTimeout(runId: String, now: Date) throws -> ApprovalCheckpoint {
        guard var run = runs[runId] else {
            throw ApprovalBreakpointError.unknownRun(runId)
        }
        guard let pending = run.pending else {
            throw ApprovalBreakpointError.nothingPending(runId)
        }
        guard now >= pending.deadline else {
            throw ApprovalBreakpointError.pendingInterrupt(runId: runId, stepIndex: pending.stepIndex)
        }
        run.pending = nil
        runs[runId] = run
        try persist()
        return run
    }

    private func expire(now: Date) throws {
        var changed = false
        for key in Array(runs.keys) {
            guard var run = runs[key], let pending = run.pending, now >= pending.deadline else { continue }
            var expired = pending
            expired.resumeAuthorized = false
            run.pending = expired
            runs[key] = run
            changed = true
        }
        if changed {
            try persist()
        }
    }

    private func persist() throws {
        let ordered = runs.values.sorted { $0.runId < $1.runId }
        let snapshot = Snapshot(schema: ApprovalBreakpointSchema.current, runs: ordered)
        let encoder = JSONEncoder.osaurusCanonical()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: indexURL, options: .atomic)
    }

    private static func read(_ indexURL: URL) throws -> [String: ApprovalCheckpoint] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        guard snapshot.schema == ApprovalBreakpointSchema.current else {
            throw ApprovalBreakpointError.invalidArguments(snapshot.schema)
        }
        var runs: [String: ApprovalCheckpoint] = [:]
        for run in snapshot.runs {
            guard runs[run.runId] == nil else {
                throw ApprovalBreakpointError.invalidArguments(run.runId)
            }
            runs[run.runId] = run
        }
        return runs
    }

    private struct Snapshot: Codable, Equatable {
        var schema: String
        var runs: [ApprovalCheckpoint]
    }
}
