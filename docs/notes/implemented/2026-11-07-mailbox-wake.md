# Note: Mailbox wake — a send starts the recipient's turn

Status: implemented

The accepted decision is
[ADR-Nuo-002](../../adr/ADR-Nuo-002-orchestrator-mailbox-grokbot-path.md).
This note records slice 1 of the Grok Bot parity plan (issue #15). It does not
authorize mesh/ROOM, a depth ceiling above 2, or cross-agent memory grants.

## Problem

The directed mailbox was a durable store with a pull interface. `send` wrote
an envelope; the recipient agent only saw it if it happened to call
`osaurus_mailbox` with `action: inbox` on a later turn. Nothing started that
turn. A bot that messages another bot therefore produced a message that sat on
disk, which is the difference between a chat tool and a teammate.

## Decision

`DirectedMailboxCoordinator.send` keeps `DirectedMailboxService` as the only
write path, then hands the landed delivery to an optional wake handler behind
a fire-and-forget `Task`. The sending tool returns as soon as the envelope is
durable.

`MailboxWakeService` owns the wake:

- It accepts only `request` deliveries. A `reply` never wakes its recipient,
  which is the cycle break: A → B wakes B, B's answer lands in A's inbox, and
  A reads it on its own next turn. A `send` that carries a parent envelope
  (a forward) still wakes its recipient, so the depth-2 chain from P0 can
  continue.
- It admits at most one turn at a time across the machine
  (`MailboxWakePolicy.maxConcurrentTurns`), and six wakes per agent per rolling
  hour. A wake that admission refuses leaves the envelope in the inbox, so the
  pull path still works.
- It dispatches a `DispatchRequest` with `source: .mailbox`,
  `showToast: false`, `reattachSession: false`, `loadIntent: .background`, and
  a `mailboxWake` context (`envelopeId`, `runId`, `senderParticipantId`,
  `recipientAgentId`). A mailbox run never reattaches to an unrelated chat row.
- The prompt quotes the envelope body between explicit untrusted markers and
  tells the recipient not to call the reply action. The body is capped at
  `promptBodyLimit`; the answer is capped at `replyTextLimit` and written back
  through `DirectedMailboxCoordinator.reply`, so the service checks the last
  hop and the run caps again.
- The wake is installed from `applicationDidFinishLaunching`
  (`MailboxWakeService.shared.install()`). Unit tests inject a fake dispatcher
  and a reply sink, so they never touch the user-level mailbox file or a model.

`SessionSource.mailbox` is a new persisted provenance value. It maps to the
`.schedule` inference/residency class (headless, not chat-owned) and to the
`.schedule` `agent_runs` trigger kind; the persisted `source=mailbox` payload
keeps the two apart. `AgentChannelBindingRunSource` refuses it, so a mailbox
turn cannot publish proactively to a channel.

## Alternatives considered

- **Make `send` await the recipient's whole turn.** Lost. A local model turn can
  take minutes; the sending tool would block its own agent loop, and a provider
  timeout would turn a durable message into a failed tool call.
- **Wake on `reply` too.** Lost. Two agents that both auto-reply form an
  unbounded ping-pong; the P0 depth and cycle checks bound forwards, not reply
  loops. The pull path remains available for the sender.
- **Write the reply from inside the recipient's turn by prompting it to call
  `osaurus_mailbox reply`.** Lost. It spends a model step and fails when the
  model forgets; reading the finished session's last assistant message is
  deterministic and keeps the tool surface unchanged.
- **Add a second scheduler for mailbox work.** Lost. `DispatchRequest` →
  `TaskDispatcher` → `BackgroundTaskManager` is the one queue every trigger
  already uses; a second scheduler would fork capacity, recovery, and
  cancellation semantics.
- **Reuse `SessionSource.delegation` for attribution.** Lost. Delegation binds
  child budgets and strips `spawn_*`; a peer message is not a child task, and
  the audit trail must be able to tell them apart.
- **Persist the wake queue now.** Deferred to slice 2 (issue #16). This slice
  keeps the admission counters in memory; a crash loses the wake, and the
  envelope remains readable through `inbox`.

## Consequences

A mailbox `send` now produces a recipient turn without user action, and the
answer returns as a reply envelope. The sender is not woken by that reply, so
the exchange ends after one hop unless the sender reads its inbox.

The wake counters are per-process. A restart clears the hourly quota and any
in-flight marker, which slice 2 replaces with persisted delivery rows. The
`agent_runs` trigger kind reads as `schedule`; a dedicated kind is a later
schema change.

Live UI proof for the two-agent send → run → reply flow is not claimed here.
The deterministic coverage is `MailboxWakeServiceTests` (six cases) plus the
existing `DirectedMailboxTests` and `OsaurusMailboxToolTests`; the model
runtime is faked, so this is a contract proof, not runtime evidence.
