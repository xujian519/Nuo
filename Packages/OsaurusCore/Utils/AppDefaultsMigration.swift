//
//  AppDefaultsMigration.swift
//  osaurus
//
//  One-time copy of the pre-rename preferences domain into the current one.
//
//  `CFBundleIdentifier` drives `UserDefaults.standard`'s domain, so the rename
//  gives the app a brand-new, empty preferences domain while every setting the
//  user ever changed still lives in the old one. Without this copy a user who
//  upgrades would find their chat settings, server port, model defaults and
//  per-agent toggles silently reset — the data is on disk, but nothing reads
//  it.
//
//  Copy, never move: the old domain stays intact so a rollback to the previous
//  build still finds its settings. The marker lives in the *new* domain, so it
//  travels with the settings it guards, and no real preference is ever
//  overwritten by a stale value from the old one.
//

import Foundation
import OsaurusRepository
import os

public enum AppDefaultsMigration {

    /// Marker for "the old domain has been copied". A frozen identifier:
    /// it is only ever read by this migration.
    public static let markerKey = "ai.osaurus.brand.defaults-migrated"

    /// Preference keys this migration never carries over, even from the old
    /// domain: window frames are keyed by window title (which changed with the
    /// rename), so copying them would leave unreachable junk behind.
    static let skippedPrefixes = ["NSWindow Frame ", "NSPreferencesContentSize"]

    private static let log = Logger(subsystem: "com.dinoki.osaurus", category: "DefaultsMigration")

    /// Copy every key of `legacyDomain` that the current domain does not
    /// already have, then mark the copy as done. Returns the number of keys
    /// copied; a second call is a no-op.
    @discardableResult
    public static func migrate(legacyDomain: String, into current: UserDefaults) -> Int {
        guard !current.bool(forKey: markerKey) else { return 0 }

        let legacy = UserDefaults(suiteName: legacyDomain)
        let values = legacy?.persistentDomain(forName: legacyDomain) ?? [:]

        var copied = 0
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            guard key != markerKey else { continue }
            guard !skippedPrefixes.contains(where: { key.hasPrefix($0) }) else { continue }
            // Newest wins: anything already set in the current domain was
            // written by this build and is not overwritten by the old value.
            guard current.object(forKey: key) == nil else { continue }
            current.set(value, forKey: key)
            copied += 1
        }

        current.set(true, forKey: markerKey)
        current.synchronize()
        return copied
    }

    /// Production entry point. Called once at process start, before any
    /// settings are read. Never runs under a test/override root: the old
    /// domain on a developer machine belongs to the real user.
    @discardableResult
    public static func migrateIfNeeded() -> Int {
        guard OsaurusPaths.overrideRoot == nil else { return 0 }
        if let testRoot = ProcessEnvironment.value("OSAURUS_TEST_ROOT"),
            !testRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return 0
        }

        let copied = migrate(legacyDomain: Brand.Legacy.defaultsDomain, into: .standard)
        if copied > 0 {
            log.info(
                "Copied \(copied, privacy: .public) preference(s) from \(Brand.Legacy.defaultsDomain, privacy: .public) to \(Brand.defaultsDomain, privacy: .public)"
            )
        }
        return copied
    }
}
