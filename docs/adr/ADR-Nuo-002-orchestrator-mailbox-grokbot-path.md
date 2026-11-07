# ADR-Nuo-002: Orchestrator directed mailbox

Status: Accepted

Date: 2026-11-05

## Context

Nuo already has an Orchestrator, per-agent Agent DB, app-wide memory, and a
collaboration envelope. The envelope
(`osaurus.agent-collaboration.v1`) carries sender, recipient, correlation,
and provenance. `AgentCollaborationService` only keeps it in memory.
[AGENT_COLLABORATION_PROTOCOL.md](../AGENT_COLLABORATION_PROTOCOL.md) says
that service is the contract proof, not a team runtime.

Grok Bot-style collaboration wants one agent to hand work to another named
agent and get an answer back. A true mesh, where any agent may wake any
other agent, is not the Day-1 shape. Subagent dispatch is also the wrong
shape: it runs a helper under the parent, and `host.dispatch` keeps the
calling agent's context
([HOST_API.md](../plugins/HOST_API.md)). Cross-agent mail must not be
implemented by widening that ABI.

Memory is already partitioned. Global recall uses the shared vector bucket
(empty agent id). Each agent has `MemoryNamespace.agent` plus
`~/.nuo/agents/<uuid>/db.sqlite` ([AGENT_DB.md](../AGENT_DB.md),
[MEMORY.md](../MEMORY.md)). A second plugin memory database would fork that.

[ADR-Nuo-001](ADR-Nuo-001-remove-router-credits-and-cloud-sync.md) is a
separate decision. This record does not turn Router credits back on.

## Decision

P0 is a directed mailbox owned by the Orchestrator. It reuses
`AgentCollaborationEnvelope`. It does not add a second wire schema and it
does not implement `AgentCollaborationTransport`. That transport's `send`
has no admission check; a durable transport with the same signature would
let callers skip the gate.

`DirectedMailboxService` is the only write path:

- `send` / `inbox` persist the envelope. Body text is untrusted. A stored
  `contentUntrusted: false` is read back as untrusted.
- The Orchestrator may address any target. Any other sender needs an
  explicit persisted allowlist edge. The same rule gates `authorizeSpawnResume`.
- A reply may return only to the previous sender. It is not a new edge.
- One run has token, tool, and subtask caps. Forward mail spends one
  subtask. Depth counts forward hops and defaults to 2. A stored or
  requested depth above 2 is clamped. Cycles and a second root in the same
  run are rejected.
- Global memory stays the shared bucket. Bot-domain memory returns that
  agent's existing `MemoryNamespace.agent` key and Agent DB file. It does
  not create those files and it does not open another agent's partition.
  Any other partition key, including a plugin store, a project namespace,
  or a lowercase alias of an agent id, is rejected.
- Spawn authorization does not inherit the caller's `host.dispatch`
  context and does not replace subagent dispatch. Nothing in this change
  edits the dispatch ABI.

The on-disk file is `OsaurusPaths.directedMailboxFile()`
(`collaboration/mailbox.json`). It is not a row in an agent's database.

P0 has no Settings row and no chat tool. The contract is the service.
Superseded by the 2026-11-06 appendix below: a Settings row and a
model-visible tool now exist.

## P0 scope

This record implements only P0:

- Accepted ADR text (this file).
- Persisted directed send / inbox.
- Orchestrator or an explicit communication allowlist as the only
  spawn/resume authority.
- Two-layer memory grants over the stores that already exist.
- Per-run token, tool, and subtask caps; depth ceiling 2; cycle rejection;
  unauthorized-edge rejection.
- The in-memory collaboration service stays, so the envelope tests still
  have a transport with no disk and no policy.

Default caps when a caller does not pass limits: 8000 tokens, 16 tool
calls, 4 subtasks, depth 2. These are mailbox admission numbers, not model
sampler defaults.

## Consequences

- Two agents can exchange one request and one reply through a file that
  survives a new `DirectedMailboxService` on the same directory.
- An agent cannot mail or spawn a peer that is not on its allowlist, and
  cannot read that peer's inbox or memory partition.
- A chain Orchestrator → A → B is depth 2. B → C is rejected. A forward
  back to someone already on the chain is a cycle.
- Once the token or tool cap is spent, another forward is rejected. The
  reply path still delivers, so the run can return.
- `host.dispatch` still ignores `agent_id` / `agent_address`. Identity,
  local models, and BYOK are not part of this path.
- There is still no product UI. A live chat proof is not claimed.

## Alternatives considered

- **A parallel mailbox envelope and a plugin memory database.** Lost. The
  protocol doc says later persistence must keep this envelope. A second
  store would split bot memory from Agent DB and the agentId vector
  partition.
- **Implement the durable store as `AgentCollaborationTransport`.** Lost.
  `send` on that protocol cannot express depth, caps, or the allowlist.
  Callers could persist an envelope the gate would have rejected.
- **Use subagent dispatch as the cross-agent path.** Lost. That replaces
  cross-agent mail with a child task and would press on the dispatch ABI
  that inherits the caller's context.
- **Let any registered agent message any other agent.** Lost. That is a
  mesh. P0 is directed.
- **Store the mailbox inside the target agent's Agent DB.** Lost. The
  Orchestrator would write another agent's database, and `db_query` would
  surface untrusted mail as table rows. Agent DB remains the bot-domain
  data store, not the mailbox.
- **Leave the service in memory.** Lost. P0 requires a mailbox that
  survives a new process.

## Out of scope

P0 did not include the items below. P1, P2, and P3 are the appendices.
P4 is not triggered.

- Shared workspace and a persistent browser. The workspace slice is the
  P1 appendix. A resident shared browser is still not accepted.
- Turning a demo into a Skill. P3 records that path. Raw pointer
  trails are not skills.
- Productizing multi-step checkpoints inside the agent loop. P2
  records the approval breakpoint; it does not rewrite the loop.
- True Mesh or ROOM. The P4 gate is not triggered; see the appendix.
  There is no mesh code.
- Opening `host.dispatch` so one agent runs as another.
- A Settings control or a model-visible mailbox tool. Superseded by the
  2026-11-06 appendix below.
- Router credits, cloud sync, Identity, and BYOK (ADR-Nuo-001).

## Leftover risks

These stay future work. This ADR does not expand into them.

- Without a UI, operators cannot edit the allowlist except through the
  service. Adding a setting later has to update the settings catalog.
  Superseded by the 2026-11-06 appendix below.
- The depth ceiling is hard-clamped at 2. Raising it needs its own
  decision; a hand-edited `maxDepth` does not.
- Project memory namespaces are unchanged and are not granted by the
  mailbox. A later design has to say whether a bot may read a project.
- Envelope text is marked untrusted, but no model runner consumes the
  mailbox yet. The runner must keep treating the body as data.
  Superseded by the 2026-11-06 appendix below.
- Live app proof of the mailbox is not part of P0.

## Appendix: P1 shared workspace (authorized 2026-11-05)

P1 is a separate change stacked on the P0 mailbox. It does not authorize
P2 (demo → Skill), P3 (multi-step checkpoint productization), or P4
(Mesh / ROOM). `host.dispatch` still inherits the caller's agent. Envelope
text stays untrusted. Bot memory is still the existing agentId partition.

### Root and subdirectories

The root is `OsaurusPaths.sharedCollaborationWorkspace()`
(`collaboration/workspace/`). It sits next to the mailbox file and is not
an Agent DB and not a vector bucket.

| Subdirectory | Visible to another agent | Write rule |
|---|---|---|
| `agreed/<agreement-id>/<exact-relative-path>` | Parties of that agreement, and only paths listed on it | A party may write a listed path. Any other visible write becomes an approval and does not land. |
| `proposals/<approval-uuid>.bin` | No. `read` never serves this tree | Staged bytes for one pending approval |
| `scratch/<actor-id>/<exact-relative-path>` | No | Only that actor |

Agreements name exact relative files. A grant of `notes/status.txt` does
not cover `notes/secrets.txt` or a parent directory. Paths with `..`,
empty segments, or a leading `/` are rejected. The approver is the
Orchestrator and is not itself a party. An approval counts only when the
id, agreement, writer, canonical path, and content hash all match the
pending record. A mismatch leaves the record pending and writes nothing.
Mailbox envelope text cannot grant an agreement or approve a write.

### Browser persistence

Each agent already has its own `WKWebsiteDataStore(forIdentifier:)`
(`Packages/OsaurusCore/Browser/Runtime/BrowserSession.swift`). The catalog
is `OsaurusPaths.browserSessionsFile()`. P1 keeps that isolation.
`BrowserSessionPersistencePolicy.sharedPersistentSessionEnabled` is false.
Selecting `sharedPersistentSession` fails closed. A resident shared
browser service is follow-up work, not this phase.

`file_write` and the sandbox tools are not routed into this gate yet. A
later change has to do that before those tools can place cross-agent
visible bytes. This appendix does not claim they already do.

## Appendix: P2 approval breakpoints (authorized 2026-11-05)

P2 is the durable form of the pauses that already exist: tool policy
`.ask`, and the `clarify` tool. It does not add a second pause type, and
it does not rewrite `AgentToolLoop`. P3 and P4 are not accepted.

A checkpoint is `runId`, the next step index, and refs to outputs of
steps that already ran (`ApprovalCheckpoint`). It is stored under
`OsaurusPaths.approvalBreakpointDirectory()`. While a step is pending,
`recordCompleted` refuses, so the next mutation is not recorded early.

An approval matches the pending **tool name** and the SHA-256 of the
canonical JSON arguments. Mailbox envelope text is rejected. A mismatch
does not authorize resume. After a match, `resumeAuthorized` flips and
the side effect is still the caller's job; `commit` only stores the
output ref once that effect has run. A second `approve` before `commit`
is refused, so the effect is not licensed twice.

Pending approvals expire at a deadline (default 24 hours). An approve
after the deadline does not apply the step. `acknowledgeTimeout` drops
the pending interrupt and does not invent the missing output. The
backlog limit (default 32, overridable) refuses a new interrupt instead
of running it.

`ToolRegistry`'s `.ask` branch calls this store only when
`ChatExecutionContext.approvalBreakpoint` is bound, and it throws before
the tool body. With no binding, the existing approval card is unchanged.
`ClarifyTool` writes the same kind of checkpoint and still returns
`Awaiting user response`, which is the pause the chat intercept already
understands.

A resident shared browser, Mesh, and Router credits stay out of this
phase. Demo → Skill is the P3 appendix.

## Appendix: P3 demo to skill (authorized 2026-11-05)

P3 records an explicit demonstration and turns only a fully successful
tool chain into a Skill. `DemoSkillRecorder.start` / `stop` bracket the
recording. A failed step, an empty recording, or a `mouse` / `pointer`
tool rejects the demo. Rejection does not write `SKILL.md`.

A successful stop is a draft (`pendingReview`). It is not in the skill
store yet. A human `acceptReview` writes `skills/<slug>/SKILL.md` in the
Agent Skills format. Mailbox envelope text cannot accept a draft.
`rejectReview` leaves no file.

After acceptance, `attachSchedule` or `attachWatcher` hangs the same
instructions off a real `Schedule` or `Watcher` value. `run` replays the
successful tool names only. This does not start the cloud computer, and
it does not rewrite the agent loop.

The golden set is `Packages/OsaurusEvals/Suites/DemoSkill/` (nine
deterministic cases, domain `demo_skill`). `floors.json` pins the suite
at 1.0.

## Appendix: P4 mesh gate (not triggered, 2026-11-05)

P4 would be a true Mesh or ROOM: at least three long-lived bots that
need a two-hop collaboration the Orchestrator does not sit on. That
evidence is not present. This appendix does not add mesh code, `bot_send`,
or a ROOM. Directed mailbox rules from P0 still apply.

## Appendix: mailbox Settings row and model-visible tool (authorized 2026-11-06)

P0 shipped the service and stopped there. The allowlist could be changed
only by hand-editing `collaboration/mailbox.json` or by calling the
service, and no model could call `send`, `reply`, or `inbox`. The contract
existed; no agent could use it, and no operator could administer it. This
slice closes both gaps. It adds no admission rule and removes none:
`DirectedMailboxService` is still the only write path and the only gate.

### Settings row

`MailboxSettingsSection` is the last section of Settings → Orchestrator,
titled `Directed Mailbox`, anchored `settings.orchestrator.mailbox`. It
lists the persisted edges and adds or removes them. Both actions call
`DirectedMailboxCoordinator.addEdge` / `removeEdge`, which forward to
`DirectedMailboxService.replaceAllowlist`. The view never writes the file.
The section also prints the per-run caps as read-only text.

The From picker excludes the Orchestrator. An edge with the Orchestrator as
sender is dead weight, because it reaches any target without one. Both
pickers list every agent, and Add stays disabled while the two ends match
or one is empty. A service that failed to load shows its error string in
the section instead of crashing.

Catalog sync, all four in the same change:

- `SettingsSearchIndex` row `settings.orchestrator.mailbox`, tab
  `orchestrator`, section and title `Directed Mailbox`, plus aliases and a
  disambiguation against delegation targets.
- the same id as the section anchor.
- a `guide-settings.md` row naming the same path.
- the on-screen title in `SettingsSearchSelfFindProbe`.

A row without the anchor does not scroll, and a guide path that disagrees
with the catalog is a bug.

### Model-visible tool

`osaurus_mailbox` is a built-in with three actions: `send`, `reply`,
`inbox`. The caller is `ChatExecutionContext.currentAgentId`, resolved
through `AgentManager` to `local:<uuid>`. No chat context means
`unavailable`. The tool parses arguments and forwards to the coordinator;
it decides no admission rule itself.

- `send` opens a run, or continues the run of the parent envelope.
- `reply` returns to that envelope's sender only. The service checks the
  hop again.
- `inbox` defaults to the caller. `agent_id` names another owner, and only
  the Orchestrator may pass it.

Visibility:

- The Orchestrator always sees the tool; it sits on the baseline schema.
- A custom agent sees it only when its participant id is on either end of
  the cached allowlist.
- A bounded subagent child never sees it, the same structural exclusion as
  `spawn_agent`.

The composer strip exempts an explicit `capabilities_load` pick, so a
schema can appear ahead of an edge. The service still rejects that send.

Caps, depth ceiling, cycles, and the allowlist are unchanged. `send` and
`reply` cost one tool call each. Tokens stay with the turn loop, so the
tool records zero. Every inbox entry carries `untrusted: true` and the
result carries a standing warning; the body stays data. Service failures
map to typed envelopes with a stable `error_code`, including
`unauthorized_edge`, `unknown_envelope`, `depth_exceeded`, `cycle`, and
each cap.

### Still not done

- P4 mesh or ROOM. No `bot_send`, no room, and no three-bot evidence.
- A depth ceiling above 2.
- Cross-agent memory partition grants.
- The `host.dispatch` contract. Identity, local models, and BYOK stay
  outside this path.

### New leftover

The coordinator caches the allowlist at init and refreshes it only after a
UI add or remove (`DirectedMailboxCoordinator.swift:20,37-40,59`). The
service reads the file at init as well and rewrites the whole snapshot on
every save. A hand edit or a second writer is therefore invisible to the
gate, and the next in-app save overwrites it. The prompt gate can lag the
file in both directions: a tool that stays visible after an external
removal, or a tool that stays hidden after an external addition. The
service still rejects the first case at call time.

This record claims no live app proof. The eval row now exists:
`Packages/OsaurusEvals/Suites/Mailbox/` holds five deterministic cases in
domain `mailbox`. They cover an unauthorized edge, the depth ceiling, a
cycle, a spent subtask cap whose reply still delivers, and a tampered
trust bit that reads back untrusted. `floors.json` pins `"Mailbox"` at
1.0. The unit regression set is
`Packages/OsaurusCore/Tests/AgentCollaboration/OsaurusMailboxToolTests.swift`
(eleven cases, temp-directory mailbox).

## Appendix: mailbox wake (authorized 2026-11-07)

Slice 1 of the Grok Bot parity plan closes the "no model runner consumes the
mailbox" gap without changing any admission rule. `send` still lands through
`DirectedMailboxService`; after it lands, `MailboxWakeService` starts one
headless turn of the recipient. A `reply` never wakes, which is the cycle
break. The wake admits one turn at a time and six wakes per agent per hour;
a refused wake leaves the envelope in the inbox, so the pull path remains.

The decision note is
[2026-11-07-mailbox-wake.md](../notes/implemented/2026-11-07-mailbox-wake.md).
It records the alternatives that lost and the per-process quota. Slice 2
(issue #16) later added the durable delivery ledger behind the same wake, so a
wake that was running when the process stopped is now recoverable. The depth
ceiling, cycle rejection, caps, and `host.dispatch` rule are unchanged.

## Appendix: durable delivery queue (authorized 2026-11-07)

Slice 2 records every background dispatch in
`~/.nuo/queue/deliveries.json` before it is registered, updates it on start
and on every terminal path, and marks rows left active by the previous process
as `interrupted` at launch. `DeliveryQueueStore` is the write path;
`BackgroundTaskManager` remains the executor. Nothing auto-resumes.

Settings → Orchestrator → **Delivery Queue** lists the interrupted rows and
offers **Resume run** / **Discard**. A resumed mailbox row answers its envelope
through `MailboxWakeService` after the new turn completes.

The decision note is
[2026-11-07-durable-delivery-queue.md](../notes/implemented/2026-11-07-durable-delivery-queue.md).
Message-level controls (edit / reorder / steer) are not in this slice.

## Appendix: workspace, room ownership, ACP (2026-11-07)

The remaining parity slices landed without relaxing an admission rule:

- **Slice 3 — per-agent workspace.** Every custom agent owns
  `~/.nuo/agents/<uuid>/workspace/`. Folder priority is explicit request/chat
  folder → sticky working folder → workspace. A sandboxed agent keeps its VM
  home, so the isolation boundary is unchanged. Notes:
  [agent-workspace](../notes/implemented/2026-11-07-agent-workspace.md).
- **Slice 4 — room task ownership.** A channel room has one owner and one live
  task, persisted in `agent-channels/rooms.json`. Stop / Resume / Reassign /
  Archive / Restore run through one service; the inbound relay claims the room
  and reports turn lifecycle. Notes:
  [channel-room-ownership](../notes/implemented/2026-11-07-channel-room-ownership.md).
- **Slice 5 — ACP and Grok CLI.** `HarnessKind.acp` and `.grokCLI` share an ACP
  codec (`initialize → authenticate → session/new → session/prompt`) with
  permission dialogs and `session/cancel`. Grok CLI runs through
  `grok agent stdio`. Notes:
  [acp-grok-harness](../notes/implemented/2026-11-07-acp-grok-harness.md).

Still open: `steer` into a running turn (slice 2), ACP session resume across a
process restart, and a live click-through of the queued-row buttons and room
controls on a machine where the UI automation can drive those small controls.
