# Mailbox: built-in tool scope, and a bounded headless start

Date: 2026-11-14
Issues: #12 (display-name addressing), #15 (wake), #16 (durable queue)

## Problem

Two live defects surfaced while proving the directed-mailbox slices on a
real model (Gemma 4 E4B 8-bit, isolated Release app):

1. A custom agent sitting on the allowlist saw `osaurus_mailbox` in its
   prompt surface but every call returned
   `{"ok":false,"kind":"tool_not_found","message":"osaurus_mailbox is not available in this conversation."}`.
   The orchestrator executed the same tool fine.
2. A mailbox wake persisted its delivery row as `starting` and then never
   reached the model. `chat_active` stayed 0, no chat session was created,
   and because the row still looked active, launch reconciliation skipped
   it and the operator had no Resume or Discard to act on. Only a force
   quit plus restart (which rewrote the row to `interrupted`) unlocked it.

## Root cause

**(1) Two authorization passes disagreed.** `SystemPromptComposer.resolveTools`
first decides mailbox visibility per agent (allowlist edge, explicit pick,
or the Default agent) and strips the tool otherwise. A later, broader
allowlist pass — the one that re-decides every built-in for
`snapshot.agentId != Agent.defaultId || hasExecutionWorkspace` — rebuilt
`allowed` from capability flags and never re-added `osaurus_mailbox`, so it
deleted the spec the gate had just approved. `ToolRegistry.isDynamicToolGranted`
then repeated the mistake at call time: its private overload applied the
agent's *plugin/dynamic* grant list to built-ins, so even a spec that reached
the schema could be refused during execution.

**(2) A headless start had no terminal state.** `startWork` wrote
`markStarting`, awaited `context.prepare()`, and returned silently whenever
the task was no longer active. A start that wedged before the first stream
tick left the ledger row `starting` with no owner and no timeout.

## Fix

- `SystemPromptComposer`: the broad allowlist now re-adds `osaurus_mailbox`
  when the mailbox gate already approved it (Default agent, explicit
  pick/load, or an allowlist edge).
- `ToolRegistry.isDynamicToolGranted` (private overload): built-in and
  runtime-managed names return `true`. Those are authorized by the
  composer's per-capability gates and, at call time, by
  `ToolExecutionScope`; the dynamic grant list is for plugin/MCP/dynamic
  names only.
- `BackgroundTaskManager.armStartWatchdog`: 120s after `markStarting`, a row
  still `starting` with a live task becomes `interrupted` with
  "The run never reached the model. Resume it to retry.", and the waiting
  `awaitCompletion` continuation resolves as a failure. The row is then
  exactly what Resume exists for.

## Live evidence (2026-11-14)

Isolated Release app `com.nuo.proof.issues20261113`, data root
`/tmp/nuo-issue-proof/live-12-root`, models `/Users/xujian/MLXModels`,
`~/.nuo` mtime unchanged (`1794569578`).

- Writer (custom agent, `作家 -> 读者` edge) sent with `to: "读者"`; the
  envelope persisted as `request 作家 -> 读者`. No `tool_not_found`.
- A wake row stayed `starting`, then the watchdog flipped it to
  `interrupted` at exactly +120s. Clicking 继续运行 completed it in 5s and
  wrote `reply 读者 -> 作家`.

Remaining and still open: the wake turn itself does not start while the
delivering chat turn is active; the watchdog makes that recoverable instead
of silent, but it is not yet the "delivery wakes the recipient" contract.
That row is PARTIAL until the start path is fixed.

## Alternatives considered

- **Let the broad allowlist keep every built-in** (drop the filter): it
  exists to keep the auto-mode schema to the agent's enabled set; removing
  it would re-expose Apple apps, computer use, and DB tools that the user
  switched off.
- **Make `ToolExecutionScope` the only gate and drop the dynamic grant
  check for everything**: the scope already does the job for built-ins, but
  dynamic names still need the plugin grant, so only the built-in branch was
  relaxed.
- **Block the wake until the chat turn finishes**: the delivery would sit
  `queued`, but a mailbox reply arriving after a long turn is still the same
  user-visible stall, and the queue already has ordering semantics.

## Tests

- `SystemPromptComposerToolResolutionTests.allowlistedCustomAgentSeesMailbox`
  — no edge ⇒ no tool; edge ⇒ tool in the schema and permitted by the
  execution scope.
- `DeliveryQueueControlsTests.stalledStartIsInterrupted` — a `starting` row
  with a live task becomes `interrupted` after the watchdog window.
- Wider pass: 210 tests across 14 suites (tool scope, mailbox tool,
  directed mailbox, wake, delivery queue, composer, settings search).
