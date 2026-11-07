# ACP and Grok CLI harnesses (slice 5, issue #19)

**Date:** 2026-11-07
**Status:** Implemented

## Problem

`HarnessKind` only understood Claude Code's stream-json and Pi's RPC mode, and
`HarnessRuntimeProbe` could only test those two. Grok CLI was reachable as a
model provider but not as an agent runtime.

## Decision

- Add `.acp` (any Agent Client Protocol agent) and `.grokCLI`
  (`grok agent stdio`). Both use the same `ACPHarnessAdapter`.
- ACP is JSON-RPC over stdio. The codec runs the handshake per process:
  `initialize` → `authenticate` with the agent's `_meta.defaultAuthMethodId`
  when present → `session/new` → `session/prompt`.
- `session/update` notifications map to text, reasoning, tool-started, and
  tool-finished events. `_x.ai/session_notification` `turn_completed` supplies
  output tokens and stop reason for the stats row.
- Agent-to-client `session/request_permission` becomes a Nuo dialog whose
  answer is a JSON-RPC response with the selected `optionId`. Other client
  requests (file system, terminal) are answered with `-32601` so the agent
  cannot hang waiting for a method Nuo does not implement.
- `session/cancel` is the interrupt.
- The runtime probe performs the real handshake and creates a throwaway
  session, which distinguishes installed / signed out / ready.
- ACP sessions are marked non-resumable. The agent issues its session id after
  the process starts; persisting it per chat is a follow-up.
- Grok CLI defaults to `grok` + `agent stdio`, and its help exposes that
  command. Live protocol probing on 2026-11-07 confirmed `initialize`,
  `authenticate` with `cached_token`, `session/new`, `session/prompt`, and
  `session/update` on `grok 1.0.77`.

## Consequences

- A user can register any ACP agent, or Grok CLI in one click, and chat with it
  through the existing harness chat surface.
- Permission requests surface in Nuo rather than being auto-approved.
- Each app relaunch starts a new ACP session; the chat transcript in Nuo is
  unaffected.
- ACP agents run with their own tools; Nuo does not hand them the Osaurus MCP
  bridge, so the agent token carries an empty tool scope.

## Tests

- `ACPHarnessCodecTests` (9): runtime defaults, handshake with and without a
  default auth method, update-to-event mapping, prompt results and errors,
  permission dialogs, unsupported client requests, interrupt, declarative kind
  mapping.
- `HarnessRuntimeProbeTests` gained three fake-ACP cases: ready, auth-first,
  and signed out.

## Alternatives considered

- **Treat Grok CLI as a Pi-RPC runtime.** Grok speaks ACP, not Pi's RPC
  envelope; adapting the two would be a compatibility shim.
- **Only add a generic ACP runtime.** Works, but every Grok user would have to
  know the `agent stdio` command and binary name.
- **Auto-approve ACP permission requests.** Removes a safety boundary the
  agent explicitly asks about; rejected.
- **Persist ACP session ids now.** Requires a per-chat sidecar and a `session/load`
  path that not every ACP agent supports; the runtime is marked non-resumable
  until that lands.
