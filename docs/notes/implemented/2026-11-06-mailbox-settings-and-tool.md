# Note: Mailbox settings row and model-visible tool

Status: implemented

The accepted decision is
[ADR-Nuo-002](../../adr/ADR-Nuo-002-orchestrator-mailbox-grokbot-path.md).
This note records the slice that turns the P0 directed mailbox from a
service contract into something the user can administer and the model can
call. P4 mesh/ROOM is not implemented.

## Problem

P0 shipped `DirectedMailboxService` as the only write path, but the
allowlist had no UI — edges could only be added by editing
`collaboration/mailbox.json` by hand — and no tool exposed send/reply/inbox
to a model, so no agent could actually use the mailbox. ADR-Nuo-002 lists
both as leftover future work.

## Decision

A `MailboxSettingsSection` in Settings → Orchestrator lists the persisted
edges and adds/removes them through `DirectedMailboxCoordinator`, which
forwards to `DirectedMailboxService.replaceAllowlist`. The section is in
the settings catalog (`settings.orchestrator.mailbox`) with anchor, guide
row, and self-find probe.

`osaurus_mailbox` is a model-visible tool with `send`, `reply`, and
`inbox` actions. It resolves the caller from
`ChatExecutionContext.currentAgentId` and forwards to the coordinator; the
service enforces every admission rule (orchestrator direct, allowlist
edge, reply-to-last-hop, depth ≤ 2, cycle and cap rejection). Envelope
bodies stay untrusted: inbox results mark every entry `untrusted: true`
and carry a warning. The orchestrator always sees the tool; a custom agent
sees it only when its participant id appears in the cached allowlist
(`mailboxVisible(agentId:)`), and subagent child tasks never see it.

## Alternatives considered

- **Name the tool `mailbox` instead of `osaurus_mailbox`.** Lost. Every
  built-in tool the orchestrator can reach carries the `osaurus_` prefix;
  a bare name would collide with plugin-provided tools and break the
  convention the tool prompt teaches.
- **A persisted per-agent visibility toggle instead of deriving visibility
  from the allowlist.** Lost. A second source of truth can disagree with
  the edges the service actually enforces; an agent that can see the tool
  but cannot send, or vice versa, is a worse failure than deriving both
  from the same list.
- **Charge tokens into the run budget from the tool.** Deferred. The tool
  has no tokenizer context, so send/reply record `toolCalls: 1` and zero
  tokens. Token accounting belongs to the turn loop, not the tool, and the
  P0 caps tests already cover the enforcement path.
- **Constructor injection at every tool call site instead of a test
  seam.** Lost. `ToolRegistry` builds tools without arguments, so the tool
  keeps a `@TaskLocal` coordinator override plus an internal
  `DirectedMailboxCoordinator.init(service:)` — the same seam pattern
  `PromptWorkingFolderTool` already uses — and production behavior is
  unchanged.

## Consequences

A new edge saved in Settings is writable by the service immediately and is
visible to the matching custom agent on the next prompt compose. Deleting
the last edge for an agent hides the tool from that agent. Test suites
bind coordinator, service, and agent store to a temp root and never touch
the user-level mailbox file. Token caps still bind through
`recordUsage` from the turn loop; the tool's own accounting only counts
tool calls.
