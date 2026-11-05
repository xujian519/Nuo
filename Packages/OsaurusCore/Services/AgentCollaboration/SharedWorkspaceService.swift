//
//  SharedWorkspaceService.swift
//  osaurus
//
//  跨 Agent 可见的文件只经过这里。未授权的写入停在审批单上，不会先落成已同意文件。
//  邮箱正文不可信，不能用来批准或创建约定。
//

import CryptoKit
import Foundation

public actor SharedWorkspaceService {
    public nonisolated let root: URL
    public nonisolated let orchestratorId: String

    private let indexURL: URL
    private var snapshot: Snapshot

    public init(
        directory: URL,
        orchestratorId: String = DirectedMailboxPolicy.orchestratorParticipantId
    ) throws {
        self.root = directory
        self.orchestratorId = orchestratorId
        self.indexURL = directory.appendingPathComponent(SharedWorkspaceSchema.indexFileName)
        let loaded = try Self.read(self.indexURL)
        self.snapshot = loaded
        if !FileManager.default.fileExists(atPath: self.indexURL.path) {
            try Self.writeIndex(loaded, root: self.root, indexURL: self.indexURL)
        }
    }

    /// 显式约定。调用方必须是 Orchestrator。邮箱信封不能走这个入口。
    public func grantAgreement(
        id: String,
        parties: [String],
        relativePaths: [String],
        approverId: String
    ) throws {
        guard approverId == orchestratorId else {
            throw SharedWorkspaceError.approverNotAuthorized(approverId)
        }
        // 批准人不能同时是约定的一方，否则等于自己给自己放行。
        guard !parties.contains(approverId) else {
            throw SharedWorkspaceError.approverNotAuthorized(approverId)
        }
        let agreement = try Self.makeAgreement(id: id, parties: parties, relativePaths: relativePaths)
        var updated = snapshot
        if let index = updated.agreements.firstIndex(where: { $0.id == agreement.id }) {
            updated.agreements[index] = agreement
        } else {
            updated.agreements.append(agreement)
        }
        try writeIndex(updated)
        snapshot = updated
    }

    /// 信封里的“请批准”不是批准。这个入口永远拒绝。
    public func grantAgreement(untrusted envelope: AgentCollaborationEnvelope) throws {
        _ = envelope
        throw SharedWorkspaceError.approvalInjectionRejected
    }

    public func agreement(id: String) -> SharedWorkspaceAgreement? {
        snapshot.agreements.first { $0.id == id }
    }

    public func pendingApprovals() -> [SharedWorkspaceApproval] {
        snapshot.approvals.filter { $0.state == .pending }
    }

    @discardableResult
    public func write(
        actor: String,
        agreementId: String,
        relativePath: String,
        bytes: Data
    ) throws -> SharedWorkspaceWriteOutcome {
        try Self.rejectOversized(bytes)
        let path = try SharedWorkspaceLayout.canonicalize(relativePath: relativePath)
        guard let agreement = snapshot.agreements.first(where: { $0.id == agreementId }) else {
            throw SharedWorkspaceError.unknownAgreement(agreementId)
        }
        let isParty = agreement.parties.contains(actor)
        let isAgreed = agreement.relativePaths.contains(path)
        if isParty && isAgreed {
            try writeAgreed(agreementId: agreementId, relativePath: path, bytes: bytes)
            return .written
        }
        let approval = SharedWorkspaceApproval(
            id: UUID(),
            agreementId: agreementId,
            writerId: actor,
            relativePath: path,
            contentSHA256: Self.sha256Hex(bytes),
            byteCount: bytes.count,
            state: .pending
        )
        var updated = snapshot
        updated.approvals.append(approval)
        try writeProposal(approval.id, bytes: bytes)
        try writeIndex(updated)
        snapshot = updated
        return .approvalRequired(approval)
    }

    public func read(actor: String, agreementId: String, relativePath: String) throws -> Data {
        let path = try SharedWorkspaceLayout.canonicalize(relativePath: relativePath)
        guard let agreement = snapshot.agreements.first(where: { $0.id == agreementId }) else {
            throw SharedWorkspaceError.unknownAgreement(agreementId)
        }
        guard agreement.parties.contains(actor) else {
            throw SharedWorkspaceError.notAParty(actor: actor, agreementId: agreementId)
        }
        guard agreement.relativePaths.contains(path) else {
            throw SharedWorkspaceError.pathNotAgreed(path)
        }
        let file = try agreedFile(agreementId: agreementId, relativePath: path)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw SharedWorkspaceError.notFound(path)
        }
        return try Data(contentsOf: file)
    }

    /// 字段必须和待审批单完全一致。对不上就不动文件，单据保持 pending。
    public func approve(_ decision: SharedWorkspaceApprovalDecision) throws {
        guard decision.approverId == orchestratorId else {
            throw SharedWorkspaceError.approverNotAuthorized(decision.approverId)
        }
        guard decision.approverId != decision.writerId else {
            throw SharedWorkspaceError.mistakenApproval(decision.approvalId)
        }
        guard let index = snapshot.approvals.firstIndex(where: { $0.id == decision.approvalId }) else {
            throw SharedWorkspaceError.approvalNotFound(decision.approvalId)
        }
        let approval = snapshot.approvals[index]
        guard approval.state == .pending else {
            throw SharedWorkspaceError.approvalNotPending(approval.id)
        }
        let path = try SharedWorkspaceLayout.canonicalize(relativePath: decision.relativePath)
        guard approval.agreementId == decision.agreementId,
            approval.writerId == decision.writerId,
            approval.relativePath == path,
            approval.contentSHA256 == decision.contentSHA256
        else {
            throw SharedWorkspaceError.mistakenApproval(decision.approvalId)
        }
        let proposal = try proposalFile(approval.id)
        let bytes = try Data(contentsOf: proposal)
        guard Self.sha256Hex(bytes) == approval.contentSHA256 else {
            throw SharedWorkspaceError.mistakenApproval(decision.approvalId)
        }
        guard var agreement = snapshot.agreements.first(where: { $0.id == approval.agreementId }) else {
            throw SharedWorkspaceError.unknownAgreement(approval.agreementId)
        }
        try writeAgreed(agreementId: agreement.id, relativePath: path, bytes: bytes)
        var updated = snapshot
        if !agreement.relativePaths.contains(path) {
            agreement.relativePaths.append(path)
            agreement.relativePaths.sort()
            if let agreementIndex = updated.agreements.firstIndex(where: { $0.id == agreement.id }) {
                updated.agreements[agreementIndex] = agreement
            }
        }
        updated.approvals[index].state = .approved
        try writeIndex(updated)
        snapshot = updated
        do {
            try FileManager.default.removeItem(at: proposal)
        } catch let error {
            // 约定文件已经写入。提案删不掉时，read() 仍然不会读 proposals/。
            _ = error
        }
    }

    public func applyUntrusted(_ envelope: AgentCollaborationEnvelope) throws {
        _ = envelope
        throw SharedWorkspaceError.approvalInjectionRejected
    }

    public func writeScratch(actor: String, relativePath: String, bytes: Data) throws {
        try Self.rejectOversized(bytes)
        let path = try SharedWorkspaceLayout.canonicalize(relativePath: relativePath)
        let file = try scratchFile(owner: actor, relativePath: path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: file, options: .atomic)
    }

    public func readScratch(actor: String, owner: String, relativePath: String) throws -> Data {
        guard actor == owner else {
            throw SharedWorkspaceError.scratchNotVisible(actor: actor, owner: owner)
        }
        let path = try SharedWorkspaceLayout.canonicalize(relativePath: relativePath)
        let file = try scratchFile(owner: owner, relativePath: path)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw SharedWorkspaceError.notFound(path)
        }
        return try Data(contentsOf: file)
    }

    public func agreedFileExists(agreementId: String, relativePath: String) throws -> Bool {
        let path = try SharedWorkspaceLayout.canonicalize(relativePath: relativePath)
        let file = try agreedFile(agreementId: agreementId, relativePath: path)
        return FileManager.default.fileExists(atPath: file.path)
    }

    private func writeAgreed(agreementId: String, relativePath: String, bytes: Data) throws {
        let file = try agreedFile(agreementId: agreementId, relativePath: relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: file, options: .atomic)
    }

    private func writeProposal(_ id: UUID, bytes: Data) throws {
        let file = try proposalFile(id)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: file, options: .atomic)
    }

    private func agreedFile(agreementId: String, relativePath: String) throws -> URL {
        let folder = try confined(
            root.appendingPathComponent(SharedWorkspaceLayout.agreed)
                .appendingPathComponent(try Self.validatedAgreementId(agreementId)),
            to: root
        )
        return try file(in: folder, relativePath: relativePath)
    }

    private func proposalFile(_ id: UUID) throws -> URL {
        let folder = try confined(root.appendingPathComponent(SharedWorkspaceLayout.proposals), to: root)
        return try confined(folder.appendingPathComponent("\(id.uuidString).bin"), to: folder)
    }

    private func scratchFile(owner: String, relativePath: String) throws -> URL {
        let folder = try confined(
            root.appendingPathComponent(SharedWorkspaceLayout.scratch)
                .appendingPathComponent(try Self.actorDirectoryName(owner)),
            to: root
        )
        return try file(in: folder, relativePath: relativePath)
    }

    private func file(in folder: URL, relativePath: String) throws -> URL {
        var url = folder
        for part in relativePath.split(separator: "/").map(String.init) {
            url.appendPathComponent(part)
        }
        return try confined(url, to: folder)
    }

    private func confined(_ url: URL, to root: URL) throws -> URL {
        let rootStandard = root.standardizedFileURL
        let fileStandard = url.standardizedFileURL
        let prefix = rootStandard.path.hasSuffix("/") ? rootStandard.path : rootStandard.path + "/"
        guard fileStandard.path == rootStandard.path || fileStandard.path.hasPrefix(prefix) else {
            throw SharedWorkspaceError.pathRejected(url.lastPathComponent)
        }
        return fileStandard
    }

    private func writeIndex(_ snapshot: Snapshot) throws {
        try Self.writeIndex(snapshot, root: root, indexURL: indexURL)
    }

    private static func writeIndex(_ snapshot: Snapshot, root: URL, indexURL: URL) throws {
        let encoder = JSONEncoder.osaurusCanonical()
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: indexURL, options: .atomic)
    }

    private static func read(_ indexURL: URL) throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: indexURL)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
        guard decoded.schema == SharedWorkspaceSchema.current else {
            throw SharedWorkspaceError.untrustedIndexRejected(decoded.schema)
        }
        return decoded
    }

    private static func makeAgreement(
        id: String,
        parties: [String],
        relativePaths: [String]
    ) throws -> SharedWorkspaceAgreement {
        let validated = try validatedAgreementId(id)
        let uniqueParties = Array(Set(parties.filter { !$0.isEmpty })).sorted()
        guard uniqueParties.count >= 2 else {
            throw SharedWorkspaceError.insufficientParties
        }
        let paths = try relativePaths.map { try SharedWorkspaceLayout.canonicalize(relativePath: $0) }
        return SharedWorkspaceAgreement(
            id: validated,
            parties: uniqueParties,
            relativePaths: Array(Set(paths)).sorted()
        )
    }

    private static func validatedAgreementId(_ id: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard !id.isEmpty, id.count <= 64, id.unicodeScalars.allSatisfy({ allowed.contains($0) }), id != ".", id != ".."
        else {
            throw SharedWorkspaceError.invalidAgreementId(id)
        }
        return id
    }

    private static func actorDirectoryName(_ actorId: String) throws -> String {
        guard !actorId.isEmpty, !actorId.contains("/"), !actorId.contains("\0"), actorId != ".", actorId != ".." else {
            throw SharedWorkspaceError.pathRejected(actorId)
        }
        return actorId.replacingOccurrences(of: ":", with: "_")
    }

    private static func rejectOversized(_ bytes: Data) throws {
        if bytes.count > SharedWorkspaceSchema.maxPayloadBytes {
            throw SharedWorkspaceError.payloadTooLarge(bytes.count)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct Snapshot: Codable, Equatable {
        var schema: String
        var agreements: [SharedWorkspaceAgreement]
        var approvals: [SharedWorkspaceApproval]

        static let empty = Snapshot(
            schema: SharedWorkspaceSchema.current,
            agreements: [],
            approvals: []
        )
    }
}
