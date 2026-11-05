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
        #expect(
            ChatEngine.routerDisabledError(
                serviceIsOsaurusRouter: true,
                routerEnabled: true
            ) == nil
        )
        #expect(
            ChatEngine.routerDisabledError(
                serviceIsOsaurusRouter: false,
                routerEnabled: false
            ) == nil
        )
    }

    @Test func disabledRouterDoesNotWriteTheBillingLedger() throws {
        let db = RouterBillingDatabase()
        try db.openInMemory()
        let ledger = RouterBillingLedger(database: db, writesEnabled: { false })
        let summary = RouterBillingSummary(
            requestId: "phase2-off",
            costMicro: "100",
            status: "completed",
            tokenSource: "provider",
            inputTokens: 1,
            outputTokens: 1
        )
        #expect(
            ledger.record(
                summary: summary,
                sessionId: nil,
                turnId: UUID(),
                model: "nuo/example"
            ) == nil
        )
        ledger.finalizeOutcome(entryId: "missing", outcome: .rendered)
        #expect(ledger.count() == 0)
    }
}
