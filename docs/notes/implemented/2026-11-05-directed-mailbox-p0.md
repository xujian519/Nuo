# Note: Directed mailbox, P0

Status: implemented

The accepted decision is
[ADR-Nuo-002](../../adr/ADR-Nuo-002-orchestrator-mailbox-grokbot-path.md).
This note records the P0 slice. P1–P4 are not implemented.

## Problem

The collaboration envelope existed only in
`AgentCollaborationInMemoryTransport`. Nothing persisted a directed
send/inbox, rejected an unauthorized edge, or stopped a run that exceeded
its depth or its token, tool, or subtask cap. Cross-agent work could have
been faked by subagent dispatch or by a second memory database.

## Decision

P0 extends the existing envelope. `DirectedMailboxService` persists
`AgentCollaborationEnvelope` at `collaboration/mailbox.json` and is the
admission gate. `AgentCollaborationService` stays in memory for the
protocol tests.

Bot-domain memory is a grant: `MemoryNamespace.agent` plus that agent's
existing Agent DB path. Global memory stays the shared empty-id bucket.
The grant does not create files. `host.dispatch` is unchanged.

## Alternatives considered

- **Bypass the collaboration types with a new envelope and a plugin memory
  store.** Lost. That forks the wire contract and the agentId partitions
  the memory system already has.
- **Persist by conforming to `AgentCollaborationTransport`.** Lost. The
  transport `send` cannot carry the allowlist, the depth ceiling, or the
  caps, so a caller could write mail the gate would reject.
- **Route cross-agent mail through subagent dispatch.** Lost. Dispatch
  inherits the caller's agent context. The mailbox must not change that
  ABI, and a child task is not another agent.
- **Drop the mail into the target Agent DB.** Lost. That writes another
  agent's database and presents untrusted text as SQL rows.

## Consequences

A new service instance on the same directory sees the previous envelopes.
Unauthorized edges, depth above 2, cycles, and over-cap charges are
rejected and are not written. A reply can still return after the token cap
is spent. Identity, local inference, BYOK, and Router credits are outside
this change.
