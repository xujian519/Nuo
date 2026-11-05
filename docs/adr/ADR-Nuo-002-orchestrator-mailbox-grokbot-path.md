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

P1–P4 are not defined and not accepted here. Do not treat this ADR as
approval to land them.

- Shared workspace and a persistent browser.
- Turning a demo into a Skill.
- Productizing multi-step checkpoints.
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
