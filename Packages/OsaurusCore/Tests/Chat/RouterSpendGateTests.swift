//
//  RouterSpendGateTests.swift
//  osaurusTests
//
//  Pins the Osaurus Router credit-spend gate for HTTP-origin requests:
//  key-less loopback callers must not be able to route master-key-signed,
//  credit-billed requests through the Router unless the user explicitly
//  opted in. Keyed callers and app-internal sources are unaffected.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite(.serialized)
struct RouterSpendGateTests {

    // MARK: - Pure policy

    @Test func blocksUnkeyedHTTPCallerWithoutOptIn() {
        let error = ChatEngine.routerSpendAuthorizationError(
            serviceIsOsaurusRouter: true,
            source: .httpAPI,
            callerHasVerifiedAccessKey: false,
            allowsUnkeyedLoopbackSpend: false
        )
        #expect(error != nil)
        #expect(error?.httpStatus == 403)
    }

    @Test func allowsKeyedHTTPCaller() {
        let error = ChatEngine.routerSpendAuthorizationError(
            serviceIsOsaurusRouter: true,
            source: .httpAPI,
            callerHasVerifiedAccessKey: true,
            allowsUnkeyedLoopbackSpend: false
        )
        #expect(error == nil)
    }

    @Test func allowsUnkeyedCallerWithExplicitOptIn() {
        let error = ChatEngine.routerSpendAuthorizationError(
            serviceIsOsaurusRouter: true,
            source: .httpAPI,
            callerHasVerifiedAccessKey: false,
            allowsUnkeyedLoopbackSpend: true
        )
        #expect(error == nil)
    }

    @Test func neverBlocksAppInternalSources() {
        for source in [RequestSource.chatUI, .plugin, .p2p] {
            let error = ChatEngine.routerSpendAuthorizationError(
                serviceIsOsaurusRouter: true,
                source: source,
                callerHasVerifiedAccessKey: false,
                allowsUnkeyedLoopbackSpend: false
            )
            #expect(error == nil, "source \(source) must not be gated")
        }
    }

    @Test func neverBlocksNonRouterServices() {
        let error = ChatEngine.routerSpendAuthorizationError(
            serviceIsOsaurusRouter: false,
            source: .httpAPI,
            callerHasVerifiedAccessKey: false,
            allowsUnkeyedLoopbackSpend: false
        )
        #expect(error == nil)
    }

}
