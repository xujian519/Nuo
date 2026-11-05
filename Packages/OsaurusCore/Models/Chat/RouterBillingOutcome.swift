import Foundation

/// How a billed turn rendered. Kept so existing chat rows still decode after
/// the Router billing ledger was removed. Nothing writes a new ledger.
public enum RouterBillingOutcome: String, Codable, Sendable, CaseIterable {
    case pending
    case rendered
    case reasoningOnly
    case toolOnly
    case empty
    case error
    case cancelled

    public static func classify(
        hasVisibleText: Bool,
        hasToolCalls: Bool,
        hasReasoning: Bool,
        wasCancelled: Bool,
        hadError: Bool
    ) -> RouterBillingOutcome {
        if hasVisibleText { return .rendered }
        if hasToolCalls { return .toolOnly }
        if hasReasoning { return .reasoningOnly }
        if wasCancelled { return .cancelled }
        if hadError { return .error }
        return .empty
    }
}
