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

### Phase 2 — break live use while the switch is off (landed)

The original draft of this phase rewrote stored model pins and removed the
opt-in. What landed is a hard stop instead of a silent rewrite. The source
tree stays for Phase 3.

While `OsaurusRouter.isEnabled` is false:

- `.osaurusRouter` does not connect and does not serve chat completions,
  even if a provider row is still marked enabled.
- Hosted search (`/v1/search`, `/v1/contents`) and Router cloud media
  (`/v1/media/…`) are not sent.
- `/credits/*` client calls are not sent, and `RouterBillingLedger` does
  not insert or finalize rows.

An explicit `true` still reaches those paths until Phase 3. Identity,
BYOK, local models, Aptabase, and Sentry are unchanged.

#### Migration for a stored Router pin

This phase does not rewrite saved agent defaults. If a pin still names the
managed Router (`nuo/…`, `osaurus/…`, `osaurus-cloud/…`, or spawn id
`2CFBD528-62FD-4EF0-A143-3FE532F03840`), completions do not run through it
while the switch is off. Choose a local model under Settings → Local
Models, or connect a key under Settings → Providers. The Phase 1 chat hint
opens those two tabs. Do not treat flipping the defaults key back to `true`
as the migration; Phase 3 removes the Router source.

### Phase 3 — hard removal of the credits client (landed)

Removed the Credits, Workspaces, and Router account view trees, the
checkout and welcome-credit services, and `RouterBillingDatabase` /
`RouterBillingLedger`. `.osaurusRouter` completions are refused even if
the defaults key is true. `GET /credits/balance` answers 404.
`WorkspaceSyncService` is gone. Roster refresh, workspace list refresh,
and pool top-up no longer call the Router.

Relay stays. `RelayTunnelManager` also serves Reach From Anywhere, mobile
pairing, and identity address rotation. It is not only cloud sync.

Identity that lived under `Services/Router/` moved to
`Identity/Hosted/` (`OsaurusIDService`, `OsaurusIDSessionStore`,
`OsaurusRouterIDTypes`, `OsaurusRouterAuthSigner`, and the API client
those types sign with). Local Identity, access keys, pairing, BYOK, and
local models were already outside that folder and stay. Announcements
moved to `Services/Announcements/` and were not expanded.

Stored Router model pins (`nuo/…`, `osaurus/…`, `osaurus-cloud/…`, or the
Router provider UUID) are cleared at launch. No replacement model is
chosen. Use Settings → Local Models or Settings → Providers.

#### Still leftover

- iCloud Keychain may still sync the Identity master key. Whether that
  Identity-only sync stays is a future ADR.
- Announcements and ops deep links stay as they are. This phase does not
  productize them.

## Consequences

- Installs that never wrote the defaults key no longer show Credits or
  Workspaces, and launch does not start welcome-credit or workspace-sync
  traffic.
- Local Models, Providers, and Identity stay in Settings. Chat can still
  select a local model or a BYOK provider.
- A user who already set the key to `true` can still reach the Router
  until Phase 3. While the key is absent or false, completions, hosted
  search, cloud media, and credit ledger writes do not run.
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
