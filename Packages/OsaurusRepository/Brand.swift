//
//  Brand.swift
//  OsaurusRepository
//
//  Runtime source of truth for the product's user-visible identity.
//
//  The build-time half of the brand (bundle id, display name, artifact names,
//  Info.plist registration) is replayed by `scripts/brand/` from
//  `scripts/brand/rules/*.json`. This file is the runtime half: the values
//  that must agree across the app, the CLI, the migration code and the
//  diagnostics, in one place, so a rename never has to be re-derived by hand
//  from a thousand literals.
//
//  It lives in OsaurusRepository because that is the only package both
//  OsaurusCore (the app) and OsaurusCLICore (the `nuo` command) depend on.
//  Duplicating these strings per target is exactly what the brand layer exists
//  to prevent.
//
//  Editing rules:
//  - `Brand.*` is what new code writes.
//  - `Brand.Legacy.*` exists **only** so an upgrade can find data written by
//    the previous name. Nothing may create new legacy data, and nothing may
//    delete legacy data. The single exception is dual-registration during the
//    compatibility release, called out at each use site.
//  - Legacy values are inherited from upstream Osaurus. They are frozen
//    contracts for the migration, not leftovers to "clean up": changing one
//    strands the data it points at.
//

/// Canonical product identity plus the pre-rename identifiers it replaced.
public enum Brand {
    // MARK: - Identity

    /// User-visible product name.
    public static let display = "Nuo"
    /// Machine-visible slug: command name, URL scheme, bundle-name stem.
    public static let slug = "nuo"
    /// `CFBundleIdentifier` of the app. Unit tests build as
    /// `\(bundleID).tests`, UI tests as `\(bundleID).uitests`.
    public static let bundleID = "com.nuo.app"
    /// Custom URL scheme. `Legacy.urlScheme` stays registered for old links.
    public static let urlScheme = "nuo"

    /// Every scheme a deep link may arrive on: the current one plus the
    /// pre-rename one, which stays registered because links already in the
    /// wild (agent invites, theme shares, Workspaces invites, the Hub's
    /// "Use this model" entry) are minted with the old scheme.
    public static let urlSchemes: Set<String> = [urlScheme, Legacy.urlScheme]

    /// True when `scheme` belongs to this app (either generation of it).
    public static func ownsURLScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased(), !scheme.isEmpty else { return false }
        return urlSchemes.contains(scheme)
    }
    /// Home-directory data root, resolved by `OsaurusPaths.root()`.
    public static let dataRootName = ".nuo"

    // MARK: - Network identity

    /// Bonjour service types this app publishes. Legacy types stay
    /// registered for one release so older clients keep discovering us.
    public static let bonjourServiceTypes = ["_nuo._tcp", "_nuo-mobile._tcp"]

    // MARK: - Control channel

    /// Prefix for the distributed notifications the CLI posts to the running
    /// app. Actions: `serve`, `stop`, `ui`, `modelsReload`, `toolsReload`.
    public static let controlNotificationPrefix = "com.nuo.control"

    /// Full distributed-notification name for `action`.
    public static func controlNotification(_ action: String) -> String {
        "\(controlNotificationPrefix).\(action)"
    }

    // MARK: - Preferences domain

    /// `UserDefaults` suite the app writes to. It is the bundle id, so the CLI
    /// has to ask for it by name instead of using its own standard defaults.
    public static let defaultsDomain = bundleID

    // MARK: - Keychain services

    /// One generic-password service, in both its current and pre-rename name.
    ///
    /// `legacy` is `nil` for services that stay on the upstream name because
    /// the data is owned by an upstream service, not by this app (see
    /// `identitySession`).
    public struct KeychainService: Sendable, Hashable {
        /// Service name new writes use.
        public let current: String
        /// Pre-rename service name, read for migration only.
        public let legacy: String?

        public init(current: String, legacy: String?) {
            self.current = current
            self.legacy = legacy
        }
    }

    /// Every Keychain-backed store the app owns.
    public enum Keychain {
        /// Master identity seed + recovery mnemonic.
        public static let account = KeychainService(current: "com.nuo.account", legacy: "com.osaurus.account")
        /// SQLCipher data-encryption key + HKDF salt.
        public static let storage = KeychainService(current: "com.nuo.storage", legacy: "com.osaurus.storage")
        /// API access keys.
        public static let accessKeys = KeychainService(
            current: "com.nuo.access-keys",
            legacy: "com.osaurus.access-keys"
        )
        /// Hybrid address allowlist.
        public static let addressAllowlist = KeychainService(
            current: "com.nuo.whitelist",
            legacy: "com.osaurus.whitelist"
        )
        /// Access-key revocations.
        public static let revocations = KeychainService(
            current: "com.nuo.revocations",
            legacy: "com.osaurus.revocations"
        )
        /// Agent-scoped secrets.
        public static let agentSecrets = KeychainService(
            current: "ai.nuo.agent-secrets",
            legacy: "ai.osaurus.agent-secrets"
        )
        /// Plugin/tool secrets.
        public static let toolSecrets = KeychainService(current: "ai.nuo.tools", legacy: "ai.osaurus.tools")
        /// MCP provider tokens.
        public static let mcpProviders = KeychainService(current: "ai.nuo.mcp", legacy: "ai.osaurus.mcp")
        /// Remote model provider credentials.
        public static let remoteProviders = KeychainService(current: "ai.nuo.remote", legacy: "ai.osaurus.remote")
        /// Search provider API keys.
        public static let searchProviders = KeychainService(current: "ai.nuo.search", legacy: "ai.osaurus.search")
        /// Channel credentials.
        public static let channels = KeychainService(current: "ai.nuo.channels", legacy: "ai.osaurus.channels")
        /// Remote TTS API key.
        public static let ttsRemote = KeychainService(current: "ai.nuo.tts.remote", legacy: "ai.osaurus.tts.remote")
        /// GitHub API token.
        public static let github = KeychainService(current: "com.nuo.github", legacy: "com.dinoki.osaurus.github")
        /// Hugging Face access token.
        public static let huggingFace = KeychainService(
            current: "com.nuo.huggingface",
            legacy: "com.dinoki.osaurus.huggingface"
        )
        /// Osaurus ID router session token.
        ///
        /// Frozen on the upstream service name: the token is minted by, and
        /// scoped to, the upstream `*.osaurus.ai` identity service, so renaming
        /// the local service would only strand it.
        public static let identitySession = KeychainService(current: "ai.osaurus.id", legacy: nil)

        /// Everything, in registry order.
        public static let all: [KeychainService] = [
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
            identitySession,
        ]

        /// Pre-rename service for a current service name, when one exists.
        public static func legacyService(forCurrent current: String) -> String? {
            all.first { $0.current == current }?.legacy
        }

        /// Current service for a pre-rename service name, when one exists.
        public static func currentService(forLegacy legacy: String) -> String? {
            all.first { $0.legacy == legacy }?.current
        }
    }

    // MARK: - Legacy identity (migration only)

    /// Identifiers the product used before the rename. Read-only: these point
    /// at data the user already has, and are never the target of a write.
    public enum Legacy {
        /// Previous user-visible product name.
        public static let display = "Osaurus"
        /// Previous slug (command name, `.app` stem, helper names).
        public static let slug = "osaurus"
        /// Previous `CFBundleIdentifier`.
        public static let bundleID = "com.dinoki.osaurus"
        /// Previous URL scheme; still registered so saved links work.
        public static let urlScheme = "osaurus"
        /// Previous home-directory data root (`~/.osaurus`).
        public static let dataRootName = ".osaurus"
        /// Pre-`~/.osaurus` data root under Application Support.
        public static let appSupportDirectoryName = "com.dinoki.osaurus"
        /// Previous Bonjour service types; still advertised/browsed for one
        /// release.
        public static let bonjourServiceTypes = ["_osaurus._tcp", "_osaurus-mobile._tcp"]
        /// Previous distributed-notification prefix.
        public static let controlNotificationPrefix = "com.dinoki.osaurus.control"

        /// Previous distributed-notification name for `action`.
        public static func controlNotification(_ action: String) -> String {
            "\(controlNotificationPrefix).\(action)"
        }

        /// Previous `UserDefaults` domain, read as a fallback for one release.
        public static let defaultsDomain = bundleID
    }
}
