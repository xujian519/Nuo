# Note: Mailbox send accepts an agent display name

Status: implemented

Issue #12. `osaurus_mailbox` rejected a display name in `to` and `agent_id`.

## Problem

The tool required a UUID. A model that had just been told "message 作家" put
that name in `to` and got `invalid_args`. The name-to-id map existed in the
UI and in `spawn_agent`, not in the mailbox tool. Small models do not remember
a 36-character id.

## Decision

`to` (send) and `agent_id` (inbox) accept a display name or a UUID. A value
that parses as a UUID is used only when that agent is installed; otherwise the
call is `not_found`, same as before. Anything else is trimmed and compared,
case-insensitively, to each installed agent's `name` and `displayName`.

- One match is that agent. Authorization is unchanged: a resolved name with no
  allowlist edge is still `unauthorized_edge`, and the Orchestrator can still
  reach any agent without an edge.
- No match is `not_found` with `error_code: unknown_agent` and the installed
  names. Nothing is written.
- More than one match is `invalid_args` with `error_code: ambiguous_agent`
  and each candidate's name and UUID. The tool does not pick one.

`spawn_agent`'s name resolver is not reused. Its candidate set is the spawn
allowlist. The mailbox's candidate set is every installed agent, and the
mailbox service still decides the edge.

## Alternatives considered

- **Resolve only inside the sender's allowlist.** Lost. "No such agent" and
  "you are not allowed to message them" would collapse into one error, and
  the Orchestrator's direct reach would need a second path.
- **Prefix or fuzzy match.** Lost. 「作家」would deliver to 「作家助理」.
- **Keep UUID-only and put the name map in the tool description.** Lost. The
  description is a hint. The live failure was the tool rejecting the name the
  model copied from the user.
