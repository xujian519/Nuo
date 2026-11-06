# Note: Shared workspace, P1

Status: implemented

The accepted decision is
[ADR-Nuo-002](../../adr/ADR-Nuo-002-orchestrator-mailbox-grokbot-path.md).
P0 is the mailbox. This note records P1 only. At the time of this note P2–P4
were not implemented. P2 (approval breakpoints) and P3 (demo to skill) have
since landed — see [P2](2026-11-05-approval-breakpoints-p2.md) and
[P3](2026-11-05-demo-skill-p3.md). P4 (mesh gate) is still untriggered: there
is no mesh code.

## Problem

Two agents that already have a directed mailbox still had no agreed place
to leave a file the other agent could read on a later run. A visible write
that had not been approved could have landed anyway, and a mailbox
envelope could have been mistaken for that approval. Browser sessions are
already per-agent WebKit stores; sharing them was an open question.

## Decision

`SharedWorkspaceService` owns `collaboration/workspace/`. The subdirectory
rules and the browser flag are the ADR appendix. A party writes a listed
path directly. Every other cross-agent-visible write returns
`approvalRequired` and does not create the agreed file. Approval matches
the pending id, agreement, writer, canonical path, and content hash. The
Orchestrator approves and is not a party. `applyUntrusted` and
`grantAgreement(untrusted:)` always reject envelope text.

`BrowserSessionPersistencePolicy.sharedPersistentSessionEnabled` stays
false. Selecting the shared strategy throws. No shared
`WKWebsiteDataStore` is created.

## Alternatives considered

- **Route every `file_write` and sandbox write through this gate now.**
  Lost. Those tools also serve a single agent's own folder. Hooking them
  in this change would mix that path with cross-agent approval. The
  appendix says they are not routed yet.
- **Treat a directory grant as a prefix.** Lost. `notes/status.txt` would
  then cover `notes/secrets.txt`. P1 lists exact files.
- **Accept approval text from the mailbox envelope.** Lost. P0 already
  marks envelope content untrusted. An injected "approve this" must not
  publish bytes.
- **Turn on one shared `WKWebsiteDataStore` for every agent.** Lost. That
  mixes cookies and storage. The current per-agent store stays. A resident
  shared browser is a later service, not a flag flip.

## Consequences

Agent A can write an agreed path and a new service instance lets Agent B
read those bytes. An outsider write or an unlisted path stays pending.
A mismatched approval, a self-approval, and an envelope do not publish.
At the time of this note P2–P4 and the Router credits decision were
unchanged. P2 and P3 have since landed (see the phase notes above); P4 is
still untriggered.
