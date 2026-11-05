//
//  SharedWorkspace.swift
//  osaurus
//
//  ADR-Nuo-002 P1。共享工作区的目录约定、审批结果，以及浏览器会话策略。
//  未获批准的跨 Agent 写入不能变成已同意路径上的文件。
//

import Foundation

public enum SharedWorkspaceSchema {
    public static let current = "osaurus.shared-workspace.v1"
    public static let indexFileName = "index.json"
    public static let maxPayloadBytes = 1_048_576
}

/// 根目录下的三个子树。约定见 ADR-Nuo-002 附录。
public enum SharedWorkspaceLayout {
    /// 双方已同意的文件。只有名单里的精确相对路径可以出现在这里。
    public static let agreed = "agreed"
    /// 尚未批准的字节。读接口不会把这里当成已同意内容。
    public static let proposals = "proposals"
    /// 单个 Agent 的草稿。另一个 Agent 读不到。
    public static let scratch = "scratch"

    /// 拒绝绝对路径、`..`、空段和反斜杠。返回用 `/` 连接的规范相对路径。
    public static func canonicalize(relativePath: String) throws -> String {
        if relativePath.isEmpty
            || relativePath.contains("\0")
            || relativePath.contains("\\")
            || relativePath.hasPrefix("/")
            || relativePath.hasPrefix("~")
        {
            throw SharedWorkspaceError.pathRejected(relativePath)
        }
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.isEmpty || parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            throw SharedWorkspaceError.pathRejected(relativePath)
        }
        return parts.joined(separator: "/")
    }
}

public enum SharedWorkspaceError: Error, Equatable, Sendable {
    case pathRejected(String)
    case invalidAgreementId(String)
    case insufficientParties
    case unknownAgreement(String)
    case notAParty(actor: String, agreementId: String)
    case pathNotAgreed(String)
    case notFound(String)
    case scratchNotVisible(actor: String, owner: String)
    case payloadTooLarge(Int)
    case approverNotAuthorized(String)
    case approvalNotFound(UUID)
    case approvalNotPending(UUID)
    case mistakenApproval(UUID)
    case approvalInjectionRejected
    case sharedBrowserSessionNotEnabled
    case untrustedIndexRejected(String)
}

public struct SharedWorkspaceAgreement: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var parties: [String]
    public var relativePaths: [String]

    public init(id: String, parties: [String], relativePaths: [String]) {
        self.id = id
        self.parties = parties
        self.relativePaths = relativePaths
    }
}

public enum SharedWorkspaceApprovalState: String, Codable, Sendable, Equatable {
    case pending
    case approved
}

public struct SharedWorkspaceApproval: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var agreementId: String
    public var writerId: String
    public var relativePath: String
    public var contentSHA256: String
    public var byteCount: Int
    public var state: SharedWorkspaceApprovalState

    public init(
        id: UUID,
        agreementId: String,
        writerId: String,
        relativePath: String,
        contentSHA256: String,
        byteCount: Int,
        state: SharedWorkspaceApprovalState
    ) {
        self.id = id
        self.agreementId = agreementId
        self.writerId = writerId
        self.relativePath = relativePath
        self.contentSHA256 = contentSHA256
        self.byteCount = byteCount
        self.state = state
    }
}

public struct SharedWorkspaceApprovalDecision: Sendable, Equatable {
    public var approvalId: UUID
    public var agreementId: String
    public var writerId: String
    public var relativePath: String
    public var contentSHA256: String
    public var approverId: String

    public init(
        approvalId: UUID,
        agreementId: String,
        writerId: String,
        relativePath: String,
        contentSHA256: String,
        approverId: String
    ) {
        self.approvalId = approvalId
        self.agreementId = agreementId
        self.writerId = writerId
        self.relativePath = relativePath
        self.contentSHA256 = contentSHA256
        self.approverId = approverId
    }
}

public enum SharedWorkspaceWriteOutcome: Sendable, Equatable {
    case written
    case approvalRequired(SharedWorkspaceApproval)
}

/// 浏览器会话持久化。P1 只记录策略，不启动共享浏览器。
///
/// 现状是每个 Agent 一个 `WKWebsiteDataStore(forIdentifier:)`，见
/// `Browser/Runtime/BrowserSession.swift`。目录在 `browser-sessions.json`。
public enum BrowserSessionPersistenceStrategy: String, Codable, Sendable, Equatable {
    case perAgentWebsiteDataStore
    case sharedPersistentSession
}

public enum BrowserSessionPersistencePolicy {
    public static let current = BrowserSessionPersistenceStrategy.perAgentWebsiteDataStore
    /// 共享持久会话已评估，P1 不打开。常驻共享浏览器留到后续。
    public static let sharedPersistentSessionEnabled = false

    public static func select(
        _ strategy: BrowserSessionPersistenceStrategy
    ) throws -> BrowserSessionPersistenceStrategy {
        switch strategy {
        case .perAgentWebsiteDataStore:
            return .perAgentWebsiteDataStore
        case .sharedPersistentSession:
            throw SharedWorkspaceError.sharedBrowserSessionNotEnabled
        }
    }
}
