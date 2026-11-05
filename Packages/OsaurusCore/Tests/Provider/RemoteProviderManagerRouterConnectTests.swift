//
//  RemoteProviderManagerRouterConnectTests.swift
//  osaurusTests
//
//  Phase 3 removed the managed Osaurus Router: its provider can no longer be
//  injected or connected, so the retry/recovery lifecycle tests are gone.
//  What stays is the transient-vs-terminal error classifier and the rate-limit
//  hint parser, which are provider-agnostic and still back other remotes.
//

import Foundation
import Testing

@testable import OsaurusCore

/// MainActor-isolated mutable counter usable from `@Sendable` override/observer blocks.
@MainActor
private final class Counter {
    var value = 0
    func increment() { value += 1 }
}

@Suite(.serialized)
@MainActor
struct RemoteProviderManagerRouterConnectTests {

    private var routerId: UUID { RemoteProviderManager.osaurusRouterProviderId }

    /// Clean-slate the managed router in the shared singleton (it may already
    /// be present if the test machine has a real identity) and reset seams.
    private func resetRouter(_ manager: RemoteProviderManager) {
        manager._testRemoveProviders(ids: [routerId])
    }

    private func observeModelsChanged(_ counter: Counter) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .remoteProviderModelsChanged,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { counter.increment() }
        }
    }

    // MARK: - Error classification

    @Test func isTransientConnectError_classifiesRetryableFailures() {
        // Transient: network + server 5xx / rate-limit.
        #expect(RemoteProviderManager.isTransientConnectError(URLError(.timedOut)))
        #expect(RemoteProviderManager.isTransientConnectError(URLError(.notConnectedToInternet)))
        #expect(RemoteProviderManager.isTransientConnectError(URLError(.networkConnectionLost)))
        #expect(RemoteProviderManager.isTransientConnectError(URLError(.cannotFindHost)))
        #expect(
            RemoteProviderManager.isTransientConnectError(
                OsaurusRouterAPIError.server(code: "X", message: "boom", status: 503)
            )
        )
        #expect(
            RemoteProviderManager.isTransientConnectError(
                OsaurusRouterAPIError.rateLimited(retryAfter: "1")
            )
        )
        #expect(RemoteProviderManager.isTransientConnectError(OsaurusRouterAPIError.transport("down")))
        #expect(RemoteProviderManager.isTransientConnectError(RemoteProviderServiceError.invalidResponse))

        // Terminal: identity / auth / other 4xx / config / unknown.
        #expect(!RemoteProviderManager.isTransientConnectError(OsaurusRouterAPIError.noIdentity))
        #expect(!RemoteProviderManager.isTransientConnectError(OsaurusRouterAPIError.unauthorized))
        #expect(!RemoteProviderManager.isTransientConnectError(OsaurusRouterAPIError.insufficientFunds))
        #expect(
            !RemoteProviderManager.isTransientConnectError(
                OsaurusRouterAPIError.server(code: "X", message: "bad", status: 400)
            )
        )
        #expect(!RemoteProviderManager.isTransientConnectError(RemoteProviderServiceError.requestFailed("nope")))
        #expect(!RemoteProviderManager.isTransientConnectError(RemoteProviderServiceError.invalidURL))
        #expect(!RemoteProviderManager.isTransientConnectError(URLError(.userAuthenticationRequired)))
    }

    /// The OpenAI-compatible discovery path (LM Studio, custom endpoints) wraps
    /// a raw transport `URLError` into `.requestFailedWithDiagnostics`. The
    /// underlying code must still drive the transient/permanent verdict —
    /// otherwise an offline-at-launch failure is misclassified as terminal and
    /// the recovery sweeps never reconnect it (the reported "broken after
    /// update until manual refresh" bug).
    @Test func isTransientConnectError_unwrapsDiagnosticsTransportError() {
        func wrapped(_ underlying: Error) -> RemoteProviderServiceError {
            let diagnostics = ProviderReplayDiagnosticBundle(
                phase: "model_discovery",
                request: URLRequest(url: URL(string: "http://localhost:1234/v1/models")!),
                transportError: underlying
            )
            return .requestFailedWithDiagnostics("Network error", diagnostics)
        }

        // Transient underlying transport errors stay transient through the wrap.
        #expect(RemoteProviderManager.isTransientConnectError(wrapped(URLError(.notConnectedToInternet))))
        #expect(RemoteProviderManager.isTransientConnectError(wrapped(URLError(.networkConnectionLost))))
        #expect(RemoteProviderManager.isTransientConnectError(wrapped(URLError(.cannotConnectToHost))))

        // Terminal transport errors, and a non-URLError transport failure with
        // no recoverable code, remain terminal.
        #expect(!RemoteProviderManager.isTransientConnectError(wrapped(URLError(.userAuthenticationRequired))))
        #expect(
            !RemoteProviderManager.isTransientConnectError(
                RemoteProviderServiceError.requestFailedWithDiagnostics(
                    "boom",
                    ProviderReplayDiagnosticBundle(
                        phase: "model_discovery",
                        request: URLRequest(url: URL(string: "http://localhost:1234/v1/models")!)
                    )
                )
            )
        )
    }

    // MARK: - Retry-After hint extraction

    @Test func retryAfterHint_extractsTypedRateLimitHints() {
        #expect(
            RemoteProviderManager.retryAfterHint(
                from: RemoteProviderServiceError.rateLimited(retryAfter: 7, statusCode: 429)
            ) == 7
        )
        #expect(
            RemoteProviderManager.retryAfterHint(
                from: OsaurusRouterAPIError.rateLimited(retryAfter: "12")
            ) == 12
        )
        // No hint: absent value, unparseable value, other error shapes.
        #expect(
            RemoteProviderManager.retryAfterHint(
                from: OsaurusRouterAPIError.rateLimited(retryAfter: nil)
            ) == nil
        )
        #expect(
            RemoteProviderManager.retryAfterHint(
                from: OsaurusRouterAPIError.rateLimited(retryAfter: "soon")
            ) == nil
        )
        #expect(RemoteProviderManager.retryAfterHint(from: URLError(.timedOut)) == nil)
        #expect(RemoteProviderManager.retryAfterHint(from: nil) == nil)
    }
}
