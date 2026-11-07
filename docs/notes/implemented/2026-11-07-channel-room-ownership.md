# Channel room task ownership (slice 4, issue #18)

**Date:** 2026-11-07
**Status:** Implemented

## Problem

`AgentChannelRoomDirectory` cached room names for display only. The inbound
relay resolved a target per message, so one room could hand turns to different
agents, and there was no durable answer to "who answers here?", "is this room
stopped?", or "what happens to the history if I archive it?".

## Decision

- `AgentChannelRoomStore` (actor) persists
  `<root>/agent-channels/rooms.json` with schema
  `osaurus.agent-channel-rooms.v1`. It is separate from the message database:
  ownership is small, inspectable state and must survive a message-store
  failure.
- A record holds `connectionId`, `roomId`, `ownerAgentId`, `taskId`,
  `externalSessionKey`, `status`, `statusBeforeArchive`, and timestamps.
- The state machine is enforced in the store:
  `idle → assigned → running → waiting → idle`, plus
  `stopped`, `archived`, and `restore`.
- `claim` is the inbound path: the first message assigns the resolved agent;
  later messages keep that owner. A manual `reassign` is the only way to move
  the room. A stopped or archived room refuses the message with a typed
  `AgentChannelRoomError`.
- `assign` is race-safe: two simultaneous calls serialize in the actor; the
  second sees `assigned` and gets `.conflict`.
- `AgentChannelRoomService` is the single write path for
  Assign / Stop / Resume / Reassign / Archive / Restore. It cancels the live
  task on Stop, Reassign, and Archive, and audits every action through
  `AgentChannelMessageStore.recordAuditEvent`.
- Permission: the local user (no requester) and the Orchestrator may act; a
  local agent may act only on a room it owns.
- The inbound relay marks `running` when a turn starts, `waiting` when the
  agent asks a question, and `idle` when the turn ends with no queued
  follow-up.

## Consequences

- One room has one answering agent until an explicit reassign.
- Stop and Archive refuse new messages instead of silently starting a turn;
  Resume re-opens the room and keeps the task id so the next message continues
  the same conversation.
- Archive keeps the message rows untouched; Restore returns the room to its
  pre-archive state with history intact.
- The room status row is inside each destination card, so it appears next to
  the configuration it describes.

## Tests

- `AgentChannelRoomStoreTests`: first-claim ownership, concurrent assignment,
  running/waiting/idle, stop/resume, archive/restore, reassign, persistence.
- `AgentChannelRoomServiceTests`: task cancellation on Stop/Reassign/Archive,
  permission rejection, and room availability.

## Alternatives considered

- **Store ownership in the message database.** One transaction boundary, but
  room state would disappear with a damaged or recreated message database, and
  every UI read would need the SQLCipher key.
- **Derive the owner from the last routed message.** No new file, but routing
  is stateless and an alias change would silently move the room between agents.
- **Let the relay resolve a target per message.** This is the pre-slice
  behavior; it defeats "one room, one task owner" and makes Stop/Resume
  ambiguous.
- **Resume by dispatching a synthetic "continue" prompt.** Would create a turn
  with no user intent and could answer a question the user never asked.
  Resume re-opens the room and waits for the next real message.
