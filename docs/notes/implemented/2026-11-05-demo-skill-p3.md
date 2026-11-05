# Note: Demo to skill, P3

Status: implemented

The accepted decision is
[ADR-Nuo-002](../../adr/ADR-Nuo-002-orchestrator-mailbox-grokbot-path.md).
This note records P3. P4 is the appendix that says the mesh gate is not
triggered. There is no mesh code.

## Problem

A demonstrated tool chain had no explicit recording boundary, so a failed
step or a pointer trail could have been saved as a Skill. A draft also
needed a person to accept it before a Schedule or Watcher could run it.

## Decision

`DemoSkillRecorder` requires `start` and `stop`. Only a recording whose
every step succeeded becomes `pendingReview`. `acceptReview` writes
`SKILL.md`. `attachSchedule` and `attachWatcher` hang that skill off a
real `Schedule` or `Watcher`, and `run` replays the successful tool
names. Nine golden cases live in `Packages/OsaurusEvals/Suites/DemoSkill/`
and are pinned in `floors.json`.

## Alternatives considered

- **Save the recording as soon as stop is pressed.** Lost. The draft has
  to stay out of the skill store until a person accepts it.
- **Keep failed steps and drop them at export.** Lost. A demo that failed
  or included a mouse trail must not be promotable at all.
- **Treat a mailbox sentence as the review.** Lost. Envelope text stays
  untrusted.
- **Record raw pointer trails or ship a cloud computer.** Lost. Those are
  forbidden for this phase.

## Consequences

A successful demo can be reviewed, stored, scheduled, and replayed. A
failed demo, an empty demo, a rejected review, and a mouse trail do not
write `SKILL.md`. P4 stays closed.
