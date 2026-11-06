# Note: Router credits and cloud sync, Phase 1

Status: implemented

The accepted decision is
[ADR-Nuo-001](../../adr/ADR-Nuo-001-remove-router-credits-and-cloud-sync.md).
This note records Phase 1 and Phase 2. At the time of this note Phase 3 was
not implemented; it landed later in `b9414a8e3` (see the Phase 3 section
below and "Phase 3 — hard removal of the credits client (landed)" in the
ADR).

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

## Phase 2

While the Router switch is off, `.osaurusRouter` does not connect or
complete, hosted search and Router cloud media are not sent, `/credits/*`
client calls are not signed, and the billing ledger does not gain or
finalize rows. Explicit `true` still reaches those paths until Phase 3.
Saved agent model pins are not rewritten.

### Migration

A pin of `nuo/…`, `osaurus/…`, `osaurus-cloud/…`, or the Router provider
UUID does not complete while the switch is off. Pick a local model or
connect your own provider. The chat hint from Phase 1 opens those settings.
Turning the defaults key back on is not the migration.

## Alternatives considered for Phase 2

- **Rewrite every stored Router model id in this change.** Lost. A silent
  rewrite can point an agent at the wrong local model. The user picks the
  replacement; the Router path simply refuses to run.
- **Ignore an explicit `true` as well.** Lost. Phase 3 deletes the source.
  Phase 2 only stops the path when the switch is off, including when some
  other flag is still enabled.
- **Delete the Router service tree now.** Lost. That is Phase 3.

## Phase 3

Credits, Workspaces, and Router account screens are gone. Checkout,
welcome credit, and the billing ledger are gone. Router completions are
refused even when the defaults key is true. The workspace sync stream is
gone. Relay stays because it also serves mobile pairing and identity
address rotation.

Identity files that used to live in `Services/Router/` now live in
`Identity/Hosted/`. Announcements moved to `Services/Announcements/` and
were not expanded. Launch clears stored Router model pins and does not
choose a replacement.

## Alternatives considered for Phase 3

- **Delete Relay with the sync client.** Lost. Relay still serves Reach
  From Anywhere and identity address rotation.
- **Delete `Identity/Hosted` with the credits client.** Lost. Osaurus ID,
  its session token, and wallet signing are Identity, not credits.
- **Pick a local model for every cleared Router pin.** Lost. The Mac may
  not have that model. The pin is cleared and the user chooses.

## Consequences

New and upgraded installs that never wrote the key keep local Identity, local
models, and BYOK. They do not start credits or workspace sync traffic, and
they do not complete, search, or generate media through the Router. At the
time of this note Phase 3 still had to delete the source; that deletion has
since landed in `b9414a8e3`.
