//
//  OsaurusKeychainServices.swift
//  osaurus
//
//  Central registry of every Keychain service this app writes to.
//

import Foundation
import OsaurusRepository

/// Every generic-password service name the app stores secrets under.
///
/// Factory reset (`OnboardingService`) wipes exactly this list; keeping it
/// next to the wrappers (instead of a hard-coded copy in the reset flow)
/// means a new secret store added with its own service string is one line
/// away from being covered by reset. If you add a keychain-backed store,
/// register its service here.
///
/// The names themselves come from `Brand.Keychain`, which pairs each service
/// with its pre-rename name so the migration has one table to walk. Do not
/// inline a service string here: a store that skips the registry skips both
/// reset and migration.
public enum OsaurusKeychainServices {
    /// Master identity seed + recovery mnemonic (`MasterKey`,
    /// `MasterMnemonicStore`).
    public static let account = Brand.Keychain.account.current
    /// SQLCipher storage key (`StorageKeyManager`).
    public static let storage = Brand.Keychain.storage.current
    /// API access keys (`APIKeyManager`).
    public static let accessKeys = Brand.Keychain.accessKeys.current
    /// Hybrid address allowlist (`WhitelistStore`; the service string keeps
    /// the legacy name).
    public static let addressAllowlist = Brand.Keychain.addressAllowlist.current
    /// Access-key revocations (`RevocationStore`).
    public static let revocations = Brand.Keychain.revocations.current
    /// Agent-scoped secrets (`AgentSecretsKeychain`).
    public static let agentSecrets = Brand.Keychain.agentSecrets.current
    /// Plugin/tool secrets (`ToolSecretsKeychain`).
    public static let toolSecrets = Brand.Keychain.toolSecrets.current
    /// MCP provider tokens and secrets (`MCPProviderKeychain`).
    public static let mcpProviders = Brand.Keychain.mcpProviders.current
    /// Remote model provider credentials (`RemoteProviderKeychain`).
    public static let remoteProviders = Brand.Keychain.remoteProviders.current
    /// Search provider API keys (`SearchProviderKeychain`).
    public static let searchProviders = Brand.Keychain.searchProviders.current
    /// Channel credentials (`ChannelCredentialVault`).
    public static let channels = Brand.Keychain.channels.current
    /// Remote TTS API key (`TTSConfiguration`).
    public static let ttsRemote = Brand.Keychain.ttsRemote.current
    /// GitHub API token (`GitHubAuth`).
    public static let github = Brand.Keychain.github.current
    /// Hugging Face access token (`HuggingFaceAuth`).
    public static let huggingFace = Brand.Keychain.huggingFace.current
    /// Osaurus ID router session token (`OsaurusIDSessionStore`). Stays on the
    /// upstream service name: the token belongs to the upstream identity
    /// service.
    public static let osaurusID = Brand.Keychain.identitySession.current

    /// Everything factory reset must wipe.
    public static let all: [String] = [
        account,
        storage,
        accessKeys,
        addressAllowlist,
        revocations,
        agentSecrets,
        toolSecrets,
        mcpProviders,
        remoteProviders,
        searchProviders,
        channels,
        ttsRemote,
        github,
        huggingFace,
        osaurusID,
    ]

    /// Pre-rename services for `all`. Factory reset wipes these too: leaving
    /// the old copy behind would let a reset install still read the secrets
    /// the user just asked to destroy.
    public static let allLegacy: [String] = Brand.Keychain.all.compactMap(\.legacy)
}
