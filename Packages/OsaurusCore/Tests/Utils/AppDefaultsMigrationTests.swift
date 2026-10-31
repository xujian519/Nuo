//
//  AppDefaultsMigrationTests.swift
//
//  Pin the one-time preferences copy that makes the rename invisible: the
//  bundle id change hands the app a fresh defaults domain, so the old one has
//  to be read once and copied forward without clobbering newer values.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite
struct AppDefaultsMigrationTests {

    /// Throwaway suites so a test never touches the real preference domains.
    private func makeDomain(_ label: String) -> String {
        "nuo-defaults-migration-tests.\(label).\(UUID().uuidString)"
    }

    private func makeDefaults(_ domain: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        return defaults
    }

    @Test("Copies keys the new domain lacks and records the marker")
    func copiesMissingKeys() throws {
        let legacyDomain = makeDomain("legacy")
        let currentDomain = makeDomain("current")
        let legacy = makeDefaults(legacyDomain)
        let current = makeDefaults(currentDomain)
        defer {
            legacy.removePersistentDomain(forName: legacyDomain)
            current.removePersistentDomain(forName: currentDomain)
        }

        legacy.set("dark", forKey: "ai.osaurus.theme")
        legacy.set(4242, forKey: "ai.osaurus.server.port")
        legacy.synchronize()

        let copied = AppDefaultsMigration.migrate(legacyDomain: legacyDomain, into: current)

        #expect(copied == 2)
        #expect(current.string(forKey: "ai.osaurus.theme") == "dark")
        #expect(current.integer(forKey: "ai.osaurus.server.port") == 4242)
        #expect(current.bool(forKey: AppDefaultsMigration.markerKey))
    }

    @Test("A newer value already in the current domain wins")
    func doesNotClobberNewerValues() {
        let legacyDomain = makeDomain("legacy")
        let currentDomain = makeDomain("current")
        let legacy = makeDefaults(legacyDomain)
        let current = makeDefaults(currentDomain)
        defer {
            legacy.removePersistentDomain(forName: legacyDomain)
            current.removePersistentDomain(forName: currentDomain)
        }

        legacy.set("legacy-value", forKey: "shared.key")
        legacy.set("only-in-legacy", forKey: "legacy.only")
        legacy.synchronize()
        current.set("current-value", forKey: "shared.key")

        let copied = AppDefaultsMigration.migrate(legacyDomain: legacyDomain, into: current)

        #expect(copied == 1)
        #expect(current.string(forKey: "shared.key") == "current-value")
        #expect(current.string(forKey: "legacy.only") == "only-in-legacy")
    }

    @Test("Second run is a no-op, even after the old domain gains a key")
    func isOneShot() {
        let legacyDomain = makeDomain("legacy")
        let currentDomain = makeDomain("current")
        let legacy = makeDefaults(legacyDomain)
        let current = makeDefaults(currentDomain)
        defer {
            legacy.removePersistentDomain(forName: legacyDomain)
            current.removePersistentDomain(forName: currentDomain)
        }

        legacy.set("first", forKey: "first.key")
        legacy.synchronize()
        #expect(AppDefaultsMigration.migrate(legacyDomain: legacyDomain, into: current) == 1)

        legacy.set("second", forKey: "second.key")
        legacy.synchronize()
        #expect(AppDefaultsMigration.migrate(legacyDomain: legacyDomain, into: current) == 0)
        #expect(current.string(forKey: "second.key") == nil)
    }

    @Test("Window frames are not carried across the rename")
    func skipsWindowFrames() {
        let legacyDomain = makeDomain("legacy")
        let currentDomain = makeDomain("current")
        let legacy = makeDefaults(legacyDomain)
        let current = makeDefaults(currentDomain)
        defer {
            legacy.removePersistentDomain(forName: legacyDomain)
            current.removePersistentDomain(forName: currentDomain)
        }

        legacy.set("80 80 900 600 ", forKey: "NSWindow Frame Osaurus Chat")
        legacy.set("kept", forKey: "real.setting")
        legacy.synchronize()

        let copied = AppDefaultsMigration.migrate(legacyDomain: legacyDomain, into: current)

        #expect(copied == 1)
        #expect(current.object(forKey: "NSWindow Frame Osaurus Chat") == nil)
        #expect(current.string(forKey: "real.setting") == "kept")
    }

    @Test("An absent legacy domain just marks the copy as done")
    func absentLegacyDomain() {
        let legacyDomain = makeDomain("absent")
        let currentDomain = makeDomain("current")
        let current = makeDefaults(currentDomain)
        defer { current.removePersistentDomain(forName: currentDomain) }

        #expect(AppDefaultsMigration.migrate(legacyDomain: legacyDomain, into: current) == 0)
        #expect(current.bool(forKey: AppDefaultsMigration.markerKey))
    }
}
