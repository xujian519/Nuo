import Foundation

/// Detects a chat or agent model that is still aimed at the managed Osaurus
/// Router so Phase 1 of ADR-Nuo-001 can point the user at local or BYOK.
///
/// Picker ids use the provider display name (`nuo/…` now, `osaurus/…` and
/// `osaurus-cloud/…` from earlier builds). Spawn targets embed the stable
/// provider UUID. A resolved picker row wins over the prefix, so a BYOK
/// provider that happens to share the name is not treated as the Router.
enum RouterPinnedModel {
    enum Route: Equatable, Sendable {
        case router
        case other
        case unresolved
    }

    /// Display-name prefixes the managed Router provider has shipped under.
    static let pickerPrefixes: Set<String> = ["nuo", "osaurus", "osaurus-cloud"]

    static func isRouterModelId(_ modelId: String?) -> Bool {
        guard let raw = normalized(modelId) else { return false }
        if let parsed = SpawnRemoteModelIdentity.parse(raw),
            parsed.providerId == RemoteProviderManager.osaurusRouterProviderId
        {
            return true
        }
        guard let head = raw.split(separator: "/", maxSplits: 1).first else { return false }
        return pickerPrefixes.contains(head.lowercased())
    }

    /// True when the open selection or the stored agent model is the Router
    /// and has not been resolved to a different provider.
    static func shouldShowMigrationHint(
        selectedModelId: String?,
        pinnedModelId: String?,
        route: (String) -> Route
    ) -> Bool {
        for id in [selectedModelId, pinnedModelId] {
            guard let raw = normalized(id) else { continue }
            switch route(raw) {
            case .router:
                return true
            case .other:
                continue
            case .unresolved:
                if isRouterModelId(raw) { return true }
            }
        }
        return false
    }

    private static func normalized(_ modelId: String?) -> String? {
        guard let trimmed = modelId?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
