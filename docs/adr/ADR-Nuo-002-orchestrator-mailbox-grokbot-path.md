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

P0 did not include the items below. P1 is the appendix at the end of this
file. P2–P4 are still not accepted.

- Shared workspace and a persistent browser. The workspace slice is the
  P1 appendix. A resident shared browser is still not accepted.
- Turning a demo into a Skill.
- Productizing multi-step checkpoints inside the agent loop. P2
  records the approval breakpoint; it does not rewrite the loop.
- True Mesh or ROOM.
- Opening `host.dispatch` so one agent runs as another.
- A Settings control or a model-visible mailbox tool.
- Router credits, cloud sync, Identity, and BYOK (ADR-Nuo-001).

## Leftover risks

These stay future work. This ADR does not expand into them.

- Without a UI, operators cannot edit the allowlist except through the
  service. Adding a setting later has to update the settings catalog.
- The depth ceiling is hard-clamped at 2. Raising it needs its own
  decision; a hand-edited `maxDepth` does not.
- Project memory namespaces are unchanged and are not granted by the
  mailbox. A later design has to say whether a bot may read a project.
- Envelope text is marked untrusted, but no model runner consumes the
  mailbox yet. The runner must keep treating the body as data.
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

A resident shared browser, demo→Skill, Mesh, and Router credits stay
out of this phase.
