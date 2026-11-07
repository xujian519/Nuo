# Note: Durable delivery queue

Status: implemented

This is slice 2 of the Grok Bot parity plan (issue #16). It records the
background chat queue on disk so a relaunch can tell what was waiting, what
was running, and what never started. It does not add the message-level
controls (edit / reorder / steer) yet.

## Problem

`BackgroundTaskManager` kept admission state in two in-memory arrays:
`queuedOrder` and `pendingStarts`. Terminal Activity tabs were persisted, but a
dispatch that was queued or running when the process stopped left no durable
row. After a relaunch the work was simply gone, and nothing could distinguish
"the provider failed" from "the process died mid-turn".

## Decision

`DeliveryQueueStore` is an actor that owns
`~/.nuo/queue/deliveries.json` (`OsaurusPaths.deliveryQueueDirectory()`). It
serialises every mutation and replaces the file atomically. The schema is
`osaurus.delivery-queue.v1`; an unknown schema fails the load instead of
silently dropping rows.

`DeliveryRecord` carries the id, agent, task lane, source, title, prompt,
external session key, mailbox wake context, status, attempts, and timestamps.
`DeliveryStatus` is `queued → starting → completed | failed | interrupted |
cancelled`. `running` exists for a later streaming update; today a task moves
from `starting` to a terminal state.

`BackgroundTaskManager` writes:

- `enqueue(.queued)` in `dispatchChat`, before the task is registered. A
  failure is logged and never blocks the dispatch; the in-memory queue remains
  the executor for this process.
- `markStarting` at the top of `startWork`, so both an immediate slot and a
  promoted queued row record the same first attempt.
- `markFinished(.completed | .failed)` from `markCompleted`,
  `markFinished(.cancelled)` from `finishChatCancellation`, and a final
  `.cancelled` from `finalizeTask` when a finalize overtakes the normal path.

`reconcileDeliveryQueue()` runs from `applicationDidFinishLaunching` and calls
`markInterruptedOnLaunch()`: every row that still claims to be active becomes
`interrupted`. Nothing restarts automatically. A row is evidence, not a
command.

Terminal rows are bounded at `terminalRetentionLimit` (500); active rows are
never trimmed.

### Queue controls

`BackgroundTaskManager.queuedDeliveries` lists ledger rows that are still
`.queued`; `queuedDeliveryIDs` publishes the live FIFO so the list shows
promotion order and drops a row the moment it is cancelled or promoted.

- **Cancel** calls `cancelTask` and repeats the ledger write, so the row leaves
  the list in the same turn instead of waiting for the cancellation observer.
- **Edit** is limited to `.queued` rows. `DeliveryQueueStore.updatePrompt`
  rewrites the ledger row, and `queuedPromptOverrides` carries the new text to
  the deferred start, which consumes and removes it. The task id, place in the
  FIFO, and session identity stay put; only the text that will run changes.
- **Reorder** swaps a queued delivery with the nearest queued delivery of the
  same agent, skipping other agents' entries. The ledger keeps submission
  timestamps; execution order is live state, so nothing is persisted.
- **Steer** into a running turn is not implemented. A headless run has no
  interactive input owner; appending a user turn to a streaming `ChatSession`
  would race the model loop and change completion semantics for schedules,
  watchers, and mailbox wakes. Interactive chats already let the user type
  during a run, which covers the OpenBot "steer" case where it matters.

The queue list refreshes on `objectWillChange` with a 400 ms debounce, and
`refreshDeliveries` writes its published arrays only when they change, so the
refresh cannot retrigger itself.

### Resume and discard

`BackgroundTaskManager.interruptedDeliveries` is the published read model:
`reconcileDeliveryQueue()` and `refreshInterruptedDeliveries()` filter the
ledger for `interrupted` rows, newest first. Settings → Orchestrator →
**Delivery Queue** renders that list; the view never opens the queue file.

- **Resume run** builds a fresh `DispatchRequest` from the stored row. When the
  row carries an `externalSessionKey` the request reattaches to the
  interrupted chat, so the new turn lands beside the partial one; otherwise it
  starts a new chat. The old row is closed as `.cancelled` with
  `error: "resumed"` before admission, which keeps the ledger evidence while
  removing the row from the list immediately; a refused dispatch re-enqueues
  the original row.
- A row with a `mailboxWake` context resumes through `MailboxWakeService`
  (`resumeRun` / `finishResumedRun`). The resumed turn still has to answer the
  envelope, so the service writes the reply when the turn completes. A plain
  re-dispatch would run the work and leave the sender without an answer.
- **Discard** removes the row. Both actions require an explicit press; launch
  reconciliation still never restarts work on its own.
- A refused resume (quota, busy recipient, dispatch refused) returns false and
  leaves the row `interrupted`, so the user can retry.
- `DeliveryRecord.isResumable` keeps the resume honest about what the row
  stores. A `.workspace` row ran on a teammate's Mac, and a `.delegation` row
  carried response-token / turn / context caps that the record does not hold.
  Re-dispatching either would rebuild a different run, so those rows are
  discard-only. `sourcePluginId` joined the record so a resumed `.plugin` row
  routes its events back to the same plugin.

## Alternatives considered

- **A SQLite table beside `scheduler.sqlite`.** Lost for this slice. The queue
  is one small append-mostly ledger, and a JSON atomic replace gives the same
  crash safety without a second encrypted database, migration runner, and key
  path. Slice 4's room store is a better candidate for SQLite.
- **Persist only terminal rows.** Lost. The interesting row is the one that was
  running when the process died; persisting only what finished reproduces the
  current blind spot.
- **Auto-resume every interrupted row at launch.** Lost. A headless turn can
  spend model quota and touch files; restarting it without a user decision
  turns a crash into duplicate side effects. The row is marked and left for an
  explicit resume.
- **A second scheduler for deliveries.** Lost. `DispatchRequest` →
  `TaskDispatcher` → `BackgroundTaskManager` is the one queue every trigger
  uses. A second scheduler would fork cancellation, capacity, and residency
  semantics.
- **Store the full prompt in the scheduler database.** Lost. The queue needs
  the prompt to be resumable, and `scheduler.sqlite` already stores run
  instructions; putting the same bytes in two files creates a second source of
  truth for the same value.
- **Reuse the interrupted task id on resume.** Lost. A fresh dispatch id keeps
  the new attempt separate from the old ledger row and avoids reusing a chat
  session id that already holds a partial turn.
- **Mark a resumed row `completed`.** Lost. The turn did not complete; marking
  it completed would make the ledger claim work that never finished. The row
  closes as `cancelled` with the `resumed` marker.
- **Let the UI read `deliveries.json` directly.** Lost. Two readers of one file
  can drift from the actor's in-memory copy and race the atomic replace. The
  published list is the single read model.
- **Implement edit as cancel + re-dispatch.** Lost. The replacement task would
  get a new id, a new session, and the tail of the FIFO, so editing the head of
  a queue would silently move it behind everything else. Keeping the task and
  overriding its prompt preserves position and identity.
- **Persist queue position in the ledger.** Lost for this slice. Queued rows
  never resume after a relaunch (launch reconciliation marks them
  `interrupted`), so a stored position would only describe a process that no
  longer exists.
- **Allow reorder across agents.** Lost. The global FIFO skips agents at their
  per-agent cap; letting a user move a row across lanes would make the visible
  order disagree with the admission rule. Moving within the same lane keeps
  both consistent.
- **Steer a running headless turn.** Lost for this slice, for the reasons in
  "Queue controls" above. The control stays documented as open rather than
  being approximated by appending a turn.

## Consequences

A relaunch can now show `interrupted` rows instead of losing them. The file is
plaintext like the rest of `~/.nuo` (FileVault-protected); prompts are stored
verbatim, which matches `agent_runs.instructions`.

The write from `markCompleted` / `cancelTask` / `finalizeTask` is a detached
`Task`, because those paths are synchronous. A crash in the few milliseconds
between the memory flip and the disk write leaves the row active, and the next
launch marks it `interrupted` — the conservative outcome.

`steer` and the `running` streaming update remain open. The `running` status
still exists only in the schema. Live proof of the queued-message controls is
outstanding: exercising the list needs a run that holds an execution slot, and
the isolated proof machine has no loadable model. The unit suites cover edit,
reorder, cancel, the store's prompt update, launch reconciliation, and the
mailbox resume path.
