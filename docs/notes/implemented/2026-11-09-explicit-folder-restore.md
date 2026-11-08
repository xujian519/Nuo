# Note: An explicit folder restore makes the folder the chat's own

Status: implemented

## Problem

A fresh chat for a custom agent now seeds the agent's workspace folder and sets
`folderFromAgentDefault` (`ChatWindowState.adoptAgentWorkingFolder`). Any
explicit restore that replaced that seed — a dispatch bookmark through
`ExecutionContext`, or a folder supplied through `restoreAndWait` — left the
marker set. `ChatWindowState.adoptProjectFolder` then treated the chat's own
folder as an agent default and replaced it with the project folder.

## Decision

- `ChatFolderState.restoreAndWait` fires `onExplicitFolderRestored` when the
  restore resolves a folder.
- `ChatSession` clears `folderFromAgentDefault` from that callback.
- The fire-and-forget `restore` path does not fire it: it backs
  `adoptDefaultFolder`, whose agent-seeded folder must stay replaceable by a
  project folder.

## Alternatives considered

- **Clear the marker in `restore` as well** — the agent workspace seed would
  immediately look chat-owned, so a project folder could no longer replace the
  default it is meant to replace.
- **Compare paths inside `adoptProjectFolder`** — path equality cannot tell an
  explicit restore from an agent seed when both resolve to the same directory,
  and calling `AgentWorkspace.defaultFolder` there creates directories as a
  side effect of a guard.
- **Change the failing test to use `setFolder`** — the test pins the restore
  path that dispatch and persistence actually use; weakening it would leave
  the marker bug in place.

## Consequences

An explicit restore now owns the chat folder, matching the existing rule that
a chat's own folder wins over a project default. An agent-seeded folder stays
replaceable. `PerChatFolderIsolationTests` continues to cover the dispatch
restore path.

## Tests

- `ProjectFolderSandboxConflictTests.existingChatFolder_wins` pins the rule.
- `PerChatFolderIsolationTests` covers the explicit dispatch-bookmark restore.
