//
//  MasterMnemonicStore.swift
//  osaurus
//
//  Persistent store for the 24-word BIP39 backup of the master seed.
//
//  Shape mirrors `MasterKey`: iCloud Keychain item under the shared
//  `com.osaurus.account` service, gated behind biometric auth on read.
//  The mnemonic is exactly equivalent to the seed in trust level — anyone
//  who can read either can reconstruct the other — so storing it next to
//  the seed adds no attack surface. What it buys us is a frictionless
//  "View recovery phrase" experience in Settings without needing to
//  re-derive from the seed every time, and lets onboarding skip the
//  "write these 24 words down" gate entirely.
//

import Foundation
import LocalAuthentication
import OsaurusRepository
import Security

public struct MasterMnemonicStore: Sendable {
    static let service = MasterKey.service
    static let account = "master-mnemonic"

    // MARK: - Store

    /// Persist the supplied 24-word phrase into iCloud Keychain alongside the
    /// master seed. If an entry already exists it is replaced — call sites
    /// (initial setup, recovery-from-mnemonic, lazy backfill) all want the
    /// stored phrase to reflect the most recently-installed master.
    public static func store(_ words: [String]) throws {
        guard words.count == 24 else {
            throw OsaurusIdentityError.mnemonicInvalidWordCount
        }
        if KeychainQueryHelpers.disablesKeychainForProcess {
            throw OsaurusIdentityError.keychainWriteFailed
        }
        let phrase = words.joined(separator: " ")
        guard let data = phrase.data(using: .utf8) else {
            throw OsaurusIdentityError.keychainWriteFailed
        }

        if exists() {
            delete()
        }

        // Same dual-write as `MasterKey`: default group always (older
        // builds read only that), shared group as an additional copy.
        guard MasterKey.addGenericPassword(service: service, account: account, label: label, data: data)
        else {
            throw OsaurusIdentityError.keychainWriteFailed
        }
    }

    static let label = "\(Brand.display) Recovery Phrase"

    // MARK: - Existence

    /// Whether the stored phrase exists. No biometric prompt — used by
    /// callers (Settings → Identity) to decide between a direct read and
    /// the lazy backfill path for legacy installs that pre-date this
    /// store.
    public static func exists() -> Bool {
        if KeychainQueryHelpers.disablesKeychainForProcess { return false }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess { return true }

        // Phrase backed up before the Nuo rename lives under the previous
        // service name. Attribute-only probe: no data, so no ACL prompt. A
        // miss here would push `IdentityView` down the "derive it from the
        // master key and store it" path, i.e. an unnecessary biometric prompt
        // to recreate a phrase that is already on the machine.
        guard let legacyService = Brand.Keychain.legacyService(forCurrent: service) else {
            return false
        }
        query[kSecAttrService as String] = legacyService
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Read

    /// Fetch the stored 24-word phrase. Triggers a biometric prompt — the
    /// phrase is the seed in a different encoding, so it carries the same
    /// access gate.
    public static func load(context: LAContext) throws -> [String] {
        if KeychainQueryHelpers.disablesKeychainForProcess {
            throw OsaurusIdentityError.keychainReadFailed
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        if context.interactionNotAllowed {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }

        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        var readLegacy = false
        if status == errSecItemNotFound,
            let legacyService = Brand.Keychain.legacyService(forCurrent: service)
        {
            // Phrase backed up before the Nuo rename. Read-only, same rule as
            // `MasterKey.getPrivateKey`: the mnemonic is the seed in another
            // encoding, so it is never copied forward — the legacy item stays
            // authoritative for identities that predate the rename.
            query[kSecAttrService as String] = legacyService
            status = SecItemCopyMatching(query as CFDictionary, &result)
            readLegacy = true
        }
        guard status == errSecSuccess,
            let data = result as? Data,
            let phrase = String(data: data, encoding: .utf8)
        else {
            throw OsaurusIdentityError.keychainReadFailed
        }

        let words =
            phrase
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
        guard words.count == 24 else {
            throw OsaurusIdentityError.mnemonicInvalidWordCount
        }
        if !readLegacy {
            // The shared-group mirror writes under the current service name,
            // which would be a forward copy for a legacy hit — not allowed.
            migrateToSharedGroupIfNeeded(data: data)
        }
        return words
    }

    /// Once per process, same mirror as `MasterKey`: make sure a synced
    /// phrase exists in both the default and the shared group. Adds copies
    /// only; never deletes, so older builds keep the item they can see.
    private static let migrationLock = NSLock()
    private nonisolated(unsafe) static var migrationAttempted = false

    private static func migrateToSharedGroupIfNeeded(data: Data) {
        guard let group = OsaurusKeychainGroup.shared else { return }
        migrationLock.lock()
        let alreadyTried = migrationAttempted
        migrationAttempted = true
        migrationLock.unlock()
        guard !alreadyTried else { return }
        MasterKey.mirrorGenericPassword(
            service: service,
            account: account,
            label: label,
            data: data,
            sharedGroup: group
        )
    }

    // MARK: - Delete

    /// Remove the stored phrase. Used by `OsaurusIdentity.wipe()` so a
    /// "Reset Identity" tears down the mnemonic alongside the master.
    @discardableResult
    public static func delete() -> Bool {
        if KeychainQueryHelpers.disablesKeychainForProcess { return true }
        // Same dual sweep as `MasterKey.delete()`: the phrase backed up before
        // the rename lives under the previous service name, and leaving it
        // behind would keep a copy of the seed recoverable after the user
        // reset their identity.
        var services = [service]
        if let legacyService = Brand.Keychain.legacyService(forCurrent: service) {
            services.append(legacyService)
        }
        var gone = true
        for name in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: name,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound { gone = false }
        }
        return gone
    }
}
