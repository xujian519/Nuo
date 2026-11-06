# Note: Approval breakpoints, P2

Status: implemented

The accepted decision is
[ADR-Nuo-002](../../adr/ADR-Nuo-002-orchestrator-mailbox-grokbot-path.md).
This note records P2 only. At the time of this note P3 and P4 were not
implemented. P3 (demo to skill) has since landed — see
[P3](2026-11-05-demo-skill-p3.md). P4 (mesh gate) is still untriggered: there
is no mesh code.

## Problem

A multi-step run that paused on an in-memory approval card could not
survive half an hour, and a free-form mailbox sentence could have been
treated as permission to mutate. Completed steps would have been easy to
run again on the way back in.

## Decision

`ApprovalBreakpointService` stores `runId`, the next step index, and
output refs for steps that already finished. The pending interrupt is
either tool policy `.ask` or the existing `clarify` tool. Approval
matches the tool name and the hash of the canonical arguments.
`ToolRegistry` throws before the tool body when a breakpoint context is
bound. `ClarifyTool` records the same checkpoint and still returns the
awaiting-response envelope the chat intercept already pauses on. No
binding leaves both paths as they were. `commit` runs only after
`approve` has authorized that one step.

## Alternatives considered

- **A new pause type inside `AgentToolLoop`.** Lost. The loop already
  stops for `clarify` and for `.ask`. P2 persists those pauses. Rewriting
  the loop is out of scope.
- **Treat the mailbox objective as the approval.** Lost. P0 marks that
  text untrusted. The binding is the tool name plus the parameter hash.
- **Apply the mutating tool, then wait for approval.** Lost. The side
  effect has to wait until resume. `recordCompleted` refuses while an
  interrupt is pending.
- **Drop the checkpoint at 30 minutes.** Lost. Thirty minutes is a normal
  wait. The default deadline is 24 hours. A shorter deadline expires
  without inventing the output.

## Consequences

A five-step run can stop on the fourth step, accept a matching approval
after 30 minutes, and commit only that step. A wrong tool, a wrong hash,
an envelope, a second approve, and an expired deadline do not license
the effect. P3, P4, and Router credits are unchanged.
