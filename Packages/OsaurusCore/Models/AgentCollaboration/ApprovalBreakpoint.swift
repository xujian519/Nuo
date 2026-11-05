//
//  ApprovalBreakpoint.swift
//  osaurus
//
//  ADR-Nuo-002 P2。把已有的 clarify / `.ask` 暂停写成可恢复的检查点。
//  批准绑定工具名和参数哈希，不接受信封里的自由文本。
//

import CryptoKit
import Foundation

public enum ApprovalBreakpointSchema {
    public static let current = "osaurus.approval-breakpoint.v1"
    public static let indexFileName = "breakpoints.json"
    public static let defaultTimeout: TimeInterval = 86_400
    public static let defaultBacklogLimit = 32
}

public enum ApprovalInterruptKind: String, Codable, Sendable, Equatable {
    /// 现有工具权限 `.ask`。副作用必须等恢复之后。
    case ask
    /// 现有 `clarify` 工具。暂停本身不产生写入。
    case clarify
}

public enum ApprovalBreakpointError: Error, Equatable, Sendable {
    case suspended(runId: String, stepIndex: Int)
    case pendingInterrupt(runId: String, stepIndex: Int)
    case mistakenApproval(runId: String)
    case approvalTimedOut(runId: String)
    case approvalBacklogFull
    case unknownRun(String)
    case nothingPending(String)
    case resumeNotAuthorized(String)
    case alreadyAuthorized(String)
    case stepMismatch(expected: Int, got: Int)
    case envelopeRejected
    case invalidArguments(String)
}

public struct ApprovalCheckpointStep: Codable, Sendable, Equatable {
    public var index: Int
    public var toolName: String
    public var parameterHash: String
    public var outputRef: String

    public init(index: Int, toolName: String, parameterHash: String, outputRef: String) {
        self.index = index
        self.toolName = toolName
        self.parameterHash = parameterHash
        self.outputRef = outputRef
    }
}

public struct ApprovalInterrupt: Codable, Sendable, Equatable {
    public var stepIndex: Int
    public var kind: ApprovalInterruptKind
    public var toolName: String
    public var parameterHash: String
    public var requestedAt: Date
    public var deadline: Date
    /// 批准只放行恢复。置位时副作用还没有提交。
    public var resumeAuthorized: Bool

    public init(
        stepIndex: Int,
        kind: ApprovalInterruptKind,
        toolName: String,
        parameterHash: String,
        requestedAt: Date,
        deadline: Date,
        resumeAuthorized: Bool
    ) {
        self.stepIndex = stepIndex
        self.kind = kind
        self.toolName = toolName
        self.parameterHash = parameterHash
        self.requestedAt = requestedAt
        self.deadline = deadline
        self.resumeAuthorized = resumeAuthorized
    }
}

public struct ApprovalCheckpoint: Codable, Sendable, Equatable, Identifiable {
    public var runId: String
    public var nextStepIndex: Int
    public var completed: [ApprovalCheckpointStep]
    public var pending: ApprovalInterrupt?

    public var id: String { runId }

    public init(
        runId: String,
        nextStepIndex: Int = 0,
        completed: [ApprovalCheckpointStep] = [],
        pending: ApprovalInterrupt? = nil
    ) {
        self.runId = runId
        self.nextStepIndex = nextStepIndex
        self.completed = completed
        self.pending = pending
    }
}

/// 绑在 `ChatExecutionContext` 上。没有绑定时，clarify 和 `.ask` 保持原样。
public struct ApprovalBreakpointContext: Sendable {
    public var service: ApprovalBreakpointService
    public var runId: String

    public init(service: ApprovalBreakpointService, runId: String) {
        self.service = service
        self.runId = runId
    }
}

public enum ApprovalParameterHash {
    /// 参数哈希只覆盖规范化后的 JSON，不含工具名。工具名单独比对。
    public static func hex(argumentsJSON: String) throws -> String {
        let canonical = try canonicalize(argumentsJSON)
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func canonicalize(_ argumentsJSON: String) throws -> String {
        guard let data = argumentsJSON.data(using: .utf8) else {
            throw ApprovalBreakpointError.invalidArguments(argumentsJSON)
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ApprovalBreakpointError.invalidArguments(argumentsJSON)
        }
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ApprovalBreakpointError.invalidArguments(argumentsJSON)
        }
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let text = String(data: canonical, encoding: .utf8) else {
            throw ApprovalBreakpointError.invalidArguments(argumentsJSON)
        }
        return text
    }
}
