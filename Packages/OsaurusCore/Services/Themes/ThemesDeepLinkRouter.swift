//
//  ThemesDeepLinkRouter.swift
//  osaurus
//
//  Parses `nuo://themes-install?hash=<sha256>` (and the pre-rename
//  `osaurus://` form) deep links and stages
//  the requested install on the management UI for ThemesView to pick up.
//

import Foundation
import OsaurusRepository

@MainActor
public enum ThemesDeepLinkRouter {

    /// Returns true when the URL was claimed by this router. Returns false
    /// for any URL not in the `.../themes-install` shape so the caller can
    /// keep dispatching to other handlers.
    @discardableResult
    public static func handle(_ url: URL) -> Bool {
        guard Brand.ownsURLScheme(url.scheme),
            url.host?.lowercased() == ThemeShareService.deepLinkHost
        else { return false }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let raw = comps?.queryItems?.first(where: {
            $0.name.lowercased() == ThemeShareService.deepLinkHashParam
        })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let raw, ThemeShareService.isValidHash(raw) else { return false }

        ManagementStateManager.shared.selectedTab = .themes
        ManagementStateManager.shared.pendingThemeInstallHash = raw.lowercased()
        return true
    }
}
