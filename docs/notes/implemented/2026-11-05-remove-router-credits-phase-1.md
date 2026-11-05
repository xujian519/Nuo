# Note: Router credits and cloud sync, Phase 1

Status: implemented

The accepted decision is
[ADR-Nuo-001](../../adr/ADR-Nuo-001-remove-router-credits-and-cloud-sync.md).
This note records the Phase 1 slice that landed with it. Phases 2 and 3 are
not implemented.

## Problem

A missing `ai.osaurus.router.enabled` value turned the Osaurus Router on.
Launch then ran welcome-credit and workspace-sync requests, and onboarding
could pin the Router as the chat provider. Local inference and BYOK do not
need that control plane.

## Decision

Phase 1 soft-disables the control plane. `OsaurusRouter.isEnabled` is false
when the defaults key is absent. Credits, Workspaces, and the composer balance
chip stay hidden while it is false. Onboarding does not enable or pin the
Router. Launch does not call `WelcomeCreditService.bootstrapAtLaunch()` or
`WorkspaceSyncService.start()` while it is false. A chat whose selected or
stored model is still the Router provider shows a hint to use a local model
or a bring-your-own-key provider.

Explicit `true` still restores the old surfaces. The service and view source
stays.

## Alternatives considered

- **Hard-delete the Router, credits, workspaces, and Relay in this change.**
  Lost. There is no migration for stored pins yet, and Relay is not known to
  exist only for sync.
- **Hide the UI and leave the default on.** Lost. The launch hooks would
  still place the business calls.
- **Disable Identity or Relay in the same change.** Lost. Both are outside
  Phase 1. iCloud Keychain Identity sync and announcement deep links are
  leftover risks in the ADR, not work for this change.

## Consequences

New and upgraded installs that never wrote the key keep local Identity, local
models, and BYOK, and do not start the credits or workspace sync traffic.
Phase 2 still has to migrate stored Router pins and remove the re-enable
paths. Phase 3 still has to delete the source.
