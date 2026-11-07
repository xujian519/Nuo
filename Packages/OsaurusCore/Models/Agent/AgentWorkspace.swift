//
//  AgentWorkspace.swift
//  osaurus
//
//  Slice 3 (issue #17): every custom agent owns a private, durable folder at
//  `~/.nuo/agents/<uuid>/workspace/`. It becomes the default working root for
//  host-folder runs when the user has not picked one, so an agent accumulates
//  its own files across chats instead of writing into a shared or temporary
//  directory.
//
//  A sandboxed agent already runs behind the VM boundary with its own home
//  (`/workspace/agents/<name>`); that home stays the writable root, and this
//  folder is not exposed to the guest.
//

import Foundation

public enum AgentWorkspace {
    /// The agent's private workspace path. Not created by this accessor.
    public nonisolated static func directory(for agentId: UUID) -> URL {
        OsaurusPaths.agentWorkspaceDirectory(for: agentId)
    }

    /// Creates the workspace directory when missing. Best effort: a failure
    /// leaves the agent without a default folder, which keeps the previous
    /// no-folder behavior instead of blocking agent creation.
    @discardableResult
    public static func ensure(for agentId: UUID) -> URL? {
        let url = directory(for: agentId)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            print("[AgentWorkspace] could not create \(url.path): \(error)")
            return nil
        }
    }

    /// The fallback folder for a run that named none. Nil means "keep the
    /// current execution mode": sandboxed agents stay jailed to their VM home,
    /// and an uncreatable workspace behaves like today's folder-less run.
    @MainActor
    public static func defaultFolder(for agentId: UUID) -> (bookmark: Data?, path: String?)? {
        guard agentId != Agent.defaultId else { return nil }
        guard AgentManager.shared.effectiveAutonomousExec(for: agentId)?.enabled != true else {
            return nil
        }
        guard let url = ensure(for: agentId) else { return nil }
        return (nil, url.path)
    }
}
