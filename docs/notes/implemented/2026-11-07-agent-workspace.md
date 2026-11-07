# Per-agent workspace (slice 3, issue #17)

**Date:** 2026-11-07
**Status:** Implemented

## Problem

A custom agent had one optional, user-picked `workingFolderPath` and no folder
of its own. A chat or background run with no folder either asked the user or
fell back to a per-chat scratch directory, so an agent could not accumulate
files across chats, schedules, and delegated runs.

## Decision

- `OsaurusPaths.agentWorkspaceDirectory(for:)` names
  `~/.nuo/agents/<uuid>/workspace/`.
- `AgentWorkspace.ensure` creates it; `AgentManager.add` calls it for every
  non-built-in agent, which covers create, duplicate, and import flows that
  save through `add`.
- Folder priority is: explicit request/chat folder → the agent's sticky
  `workingFolderPath` → the agent workspace.
- `AgentWorkspace.defaultFolder` returns the workspace only when the agent is
  **not** running behind the VM boundary. A sandboxed agent already has a
  private home at `/workspace/agents/<name>`; its writable root stays there.
- The harness launch context uses the workspace when the chat names no folder,
  replacing per-chat scratch for external runtimes.
- Deleting an agent removes the whole `agents/<uuid>/` directory, which
  includes the workspace (`AgentDatabaseStore.deleteOnDisk`).

## Consequences

- A host-folder or harness agent writes to a durable private directory with no
  setup step.
- A sandboxed agent keeps the VM boundary; the host workspace is not exposed
  to the guest. Unifying the two roots would require a sandbox bind mount and a
  migration of existing `/workspace/agents/<name>` homes.
- Chats that previously started folder-less now start with the workspace
  folder. That is the intended default, and an explicit project/chat folder
  still wins.

## Tests

- `AgentWorkspaceTests` pins the path shape, creation, delete cleanup, the
  host fallback, the sandbox exemption, and the built-in Orchestrator
  exemption.
- `AgentWorkingFolderTests` and `DelegatedWorkingFolderTests` were updated to
  the new fallback.

## Alternatives considered

- **Bind-mount `~/.nuo/agents/<uuid>/workspace` into the guest at
  `/workspace/agents/<name>`.** Keeps one path for both modes, but changes the
  sandbox contract, plugin paths, database resolution, SOUL.md seeding, and
  existing user data. Deferred as a separate migration.
- **Make every agent sandbox-off by default.** Removes the isolation boundary
  and changes a security default; rejected.
- **Create the workspace lazily on first write.** Saves an empty directory per
  agent, but the folder chip and storage surface would show nothing until the
  first turn, and a failed first write would have nowhere to land.
