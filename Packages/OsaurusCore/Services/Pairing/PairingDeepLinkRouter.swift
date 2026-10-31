//
//  PairingDeepLinkRouter.swift
//  osaurus
//
//  Parses `nuo://<addr>?pair=<base64url(invite)>` deeplinks and stages
//  the decoded invite for the receiver's UI to approve.
//

import Foundation
import OsaurusRepository

@MainActor
public enum PairingDeepLinkRouter {

    /// Returns true when the URL was claimed by the pairing router (regardless
    /// of decode success — bad URLs surface as a toast). Returns false for any
    /// URL on another scheme so other handlers (e.g. Hugging Face) can take
    /// over. Both the current and the pre-rename scheme are ours.
    @discardableResult
    public static func handle(_ url: URL) -> Bool {
        guard Brand.ownsURLScheme(url.scheme) else { return false }

        do {
            let invite = try AgentInvite.decode(from: url)
            // Validate signature + expiry early so the receiver UI doesn't
            // even render an obviously-broken invite.
            try invite.verifySignature()
            guard !invite.isExpired else {
                ToastManager.shared.error(
                    L("Invite expired"),
                    message: L("This invite expired \(invite.expirationDate.formatted()).")
                )
                return true
            }
            IncomingPairCoordinator.shared.pendingInvite = invite
        } catch let error as AgentInviteError {
            ToastManager.shared.error(L("Invalid invite"), message: error.errorDescription)
        } catch {
            ToastManager.shared.error(
                L("Invalid invite"),
                message: error.localizedDescription
            )
        }
        return true
    }
}
