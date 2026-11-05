# ADR-Nuo-001: Remove Router credits and cloud sync

Status: Accepted

Date: 2026-11-05

## Context

Nuo keeps local inference, Foundation Models, bring-your-own-key providers, and
local Identity. The Osaurus Router is a separate hosted control plane: it
bills credits, lists workspaces, and syncs shared-agent membership. Those
calls are on by default today.

`OsaurusRouter.isEnabled` reads `ai.osaurus.router.enabled`. Before this
decision, a missing key meant enabled, so a new install and any upgrade that
had never written the key still injected the managed provider, showed Credits
and Workspaces, and launched welcome-credit and workspace-sync requests.
Onboarding could also turn the switch on and pin a Router model.

Identity, access keys, local pairing, and BYOK do not require that control
plane. Relay is not removed here: it also serves mobile reachability, and
whether any remaining Relay path exists only to support sync is a later
question.

## Decision

Remove the Router credits control plane and cloud sync in three phases.
Keep local Identity, local inference, and BYOK. Do not delete the Router
source tree until a later phase has a migration note for stored pins.

Phase 1 is the only phase this record implements. The defaults key stays
`ai.osaurus.router.enabled`. An explicit `true` still restores the old
surfaces until Phase 2.

## Phased plan

### Phase 1 — soft-disable (this change)

- Missing `ai.osaurus.router.enabled` means off. Explicit `true` / `false`
  still win.
- Hide Credits, Workspaces, and the composer balance chip while the Router
  is off. The views and catalog rows stay so an explicit opt-in can show
  them again.
- Onboarding must not enable the Router or pin a Router model. "Set up
  later" may still record the hosted choice for telemetry; it does not
  apply it.
- Do not run `WelcomeCreditService.bootstrapAtLaunch()` or
  `WorkspaceSyncService.start()` at launch while the Router is off.
- If an agent or the open chat is still aimed at the Router provider, show
  a short hint toward a local model or a bring-your-own-key provider.

### Phase 2 — migrate stored pins, then stop re-entry

- Rewrite agent defaults and session selections that still name the managed
  Router provider to a local model or a BYOK provider, with a note of what
  was rewritten.
- Remove UI and onboarding paths that can turn the Router back on, after
  that migration exists.
- Leave the service and view source in the tree so the app still builds.

### Phase 3 — hard-delete

- Delete the credits, workspaces, and sync implementations under
  `Packages/OsaurusCore/Services/Router/`, and the Credits, Workspaces, and
  Router view trees, once Phase 2 has shipped.
- Delete Relay only if the remaining call sites exist only to serve that
  sync. If Relay still serves mobile reachability, that deletion waits on
  its own decision.

## Consequences

- Installs that never wrote the defaults key no longer show Credits or
  Workspaces, and launch does not start welcome-credit or workspace-sync
  traffic.
- Local Models, Providers, and Identity stay in Settings. Chat can still
  select a local model or a BYOK provider.
- A user who already set the key to `true` keeps the previous Router
  behavior until Phase 2.
- A stored model id that still names the Router shows a migration hint. It
  does not silently rewrite the pin.

## Alternatives considered

- **Delete `Services/Router/`, Credits, Workspaces, and Relay in one change.**
  Lost. Stored model pins, open chats, and any Relay duty besides sync would
  break with no migration, and Identity and BYOK sit next to that code.
- **Hide the screens but leave the default on.** Lost. Launch would still
  run welcome-credit and workspace-sync requests, which is the behavior this
  decision turns off.
- **Also disable Identity and Relay in Phase 1.** Lost. Local Identity and
  pairing stay. Relay is not known to exist only for sync, so it is not
  part of this phase.

## Out of scope

- Identity, access keys, and local pairing.
- BYOK providers and local MLX / Foundation Models.
- Aptabase and Sentry.
- A redesign of Settings or chat.
- Hard-deletion of `Services/Router/**`, the Credits / Workspaces / Router
  view trees, or Relay.

## Leftover risks

These are future decisions. This ADR does not expand into them.

- iCloud Keychain can still sync the Identity master key on its own. Whether
  that Identity-only key sync stays, and how it is split from any Router
  credential, is TBD.
- Announcements and other ops deep links that open Credits are undecided.
  Phase 1 only hides the destination while the Router is off.
