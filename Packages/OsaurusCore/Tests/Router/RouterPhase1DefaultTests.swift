//
//  RouterPhase1DefaultTests.swift
//  OsaurusCoreTests
//
//  ADR-Nuo-001 Phase 1: the Router control plane is off unless the user
//  wrote an explicit true, settings search hides Credits and Workspaces
//  in that state, and a leftover Router model id is recognizable.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite("Router Phase 1 default", .serialized)
struct RouterPhase1DefaultTests {

    @Test func absentKeyDefaultsToOffAndExplicitValueWins() {
        let suite = "router-phase1-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.removeObject(forKey: OsaurusRouter.enabledDefaultsKey)
        #expect(OsaurusRouter.isEnabled(in: defaults) == false)

        defaults.set(true, forKey: OsaurusRouter.enabledDefaultsKey)
        #expect(OsaurusRouter.isEnabled(in: defaults) == true)

        defaults.set(false, forKey: OsaurusRouter.enabledDefaultsKey)
        #expect(OsaurusRouter.isEnabled(in: defaults) == false)
    }

    @Test func settingsSearchHidesControlPlaneWhenRouterOff() {
        let off = SettingsSearchIndex.search("Workspaces", routerEnabled: false)
        #expect(!off.contains { $0.tab == .workspaces || $0.tab == .credits })

        let on = SettingsSearchIndex.search("Workspaces", routerEnabled: true)
        #expect(!on.contains { $0.id == "workspaces.overview" })

        let providers = SettingsSearchIndex.search("Providers", routerEnabled: false)
        #expect(providers.contains { $0.id == "providers.overview" })

        let identity = SettingsSearchIndex.search("Identity", routerEnabled: false)
        #expect(identity.contains { $0.tab == .identity })
    }

    @Test func unresolvedRouterPrefixShowsMigrationHint() {
        let show = RouterPinnedModel.shouldShowMigrationHint(
            selectedModelId: "foundation",
            pinnedModelId: "nuo/deepseek-v4-1-flash",
            route: { id in id == "foundation" ? .other : .unresolved }
        )
        #expect(show)
        #expect(RouterPinnedModel.isRouterModelId("osaurus/deepseek-v4-1-flash"))
        #expect(RouterPinnedModel.isRouterModelId("osaurus-cloud/some-model"))
    }

    @Test func resolvedByokProviderIsNotARouterPin() {
        let show = RouterPinnedModel.shouldShowMigrationHint(
            selectedModelId: "nuo/custom",
            pinnedModelId: nil,
            route: { _ in .other }
        )
        #expect(!show)
    }

    @Test func resolvedRouterProviderShowsMigrationHint() {
        let show = RouterPinnedModel.shouldShowMigrationHint(
            selectedModelId: "nuo/deepseek-v4-1-flash",
            pinnedModelId: "OsaurusAI/Raptor-0.6-4B-JANG_6M",
            route: { id in id.hasPrefix("nuo/") ? .router : .other }
        )
        #expect(show)
    }

    @Test func localAndByokIdsAreNotRouterPins() {
        #expect(!RouterPinnedModel.isRouterModelId("OsaurusAI/Raptor-0.6-4B-JANG_6M"))
        #expect(!RouterPinnedModel.isRouterModelId("openai/gpt-4.1"))
        #expect(!RouterPinnedModel.isRouterModelId(nil))
        #expect(!RouterPinnedModel.isRouterModelId("  "))
    }

    @Test func spawnIdentityCountsAsRouterPin() {
        let id = SpawnRemoteModelIdentity.make(
            providerId: RemoteProviderManager.osaurusRouterProviderId,
            modelId: "deepseek-v4-1-flash"
        )
        #expect(RouterPinnedModel.isRouterModelId(id))
        let other = SpawnRemoteModelIdentity.make(
            providerId: UUID(),
            modelId: "deepseek-v4-1-flash"
        )
        #expect(!RouterPinnedModel.isRouterModelId(other))
    }
}
