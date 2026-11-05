//
//  RouterPhase2ControlPlaneTests.swift
//  OsaurusCoreTests
//
//  ADR-Nuo-001 Phase 2: while the Router switch is off, credit, hosted
//  search, and cloud-media paths are refused, completions are not served,
//  and the billing ledger does not gain rows.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite("Router Phase 2 control plane")
struct RouterPhase2ControlPlaneTests {

    @Test func controlPlanePathsAreRefusedOnlyWhenDisabled() {
        let blocked = [
            "/credits/balance",
            "/credits/welcome/claim",
            "/credits/redeem",
            "/workspaces/team-1/credits/balance",
            "/v1/search",
            "/v1/contents",
            "/v1/media/images/generations",
        ]
        for path in blocked {
            #expect(OsaurusRouter.isControlPlanePath(path))
            #expect(OsaurusRouter.refusesControlPlaneRequest(path: path, enabled: false))
            #expect(!OsaurusRouter.refusesControlPlaneRequest(path: path, enabled: true))
        }
        for path in ["/id/me", "/models", "/workspaces", "/health", "/announcements"] {
            #expect(!OsaurusRouter.isControlPlanePath(path))
            #expect(!OsaurusRouter.refusesControlPlaneRequest(path: path, enabled: false))
        }
    }

    @Test func disabledRouterDoesNotServeCompletions() {
        let blocked = ChatEngine.routerDisabledError(
            serviceIsOsaurusRouter: true,
            routerEnabled: false
        )
        guard let blocked else {
            Issue.record("expected a router-disabled error")
            return
        }
        guard case .routerDisabled = blocked.kind else {
            Issue.record("expected routerDisabled")
            return
        }
        #expect(blocked.httpStatus == 403)
        let alsoBlocked = ChatEngine.routerDisabledError(
            serviceIsOsaurusRouter: true,
            routerEnabled: true
        )
        guard let alsoBlocked, case .routerDisabled = alsoBlocked.kind else {
            Issue.record("router completions stay off after Phase 3")
            return
        }
        #expect(
            ChatEngine.routerDisabledError(
                serviceIsOsaurusRouter: false,
                routerEnabled: false
            ) == nil
        )
    }

}
