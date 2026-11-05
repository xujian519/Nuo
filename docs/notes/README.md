# Decision notes

Decision notes record why a non-trivial choice was made and what lost. They are
context for future changes: code shows the result, a note shows the reasoning
that produced it.

## When to write one

Write a note for changes that alter behavior, architecture, a contract, a
process, or a persisted format. Mechanical edits, local UI tweaks, comment
fixes, and typo corrections do not need one.

Create or update the note in the same PR as the change. If the decision
changes later, write a new note and link the old one; do not rewrite history.

## Layout

```text
docs/notes/proposed/YYYY-MM-DD-topic.md    # under discussion
docs/notes/implemented/YYYY-MM-DD-topic.md # landed
docs/notes/rejected/YYYY-MM-DD-topic.md    # considered and declined
```

- `proposed` is a draft; it must name the open question.
- `implemented` is current reality written in the present tense.
- `rejected` records what was declined and what that prevents.
- A note moves between folders; its filename and body stay stable.

## Template

```markdown
# Note: <title>

Status: implemented

## Problem

The problem stated so it can be understood without knowing the solution.

## Decision

The implemented reality, present tense. Name the files or contracts that carry
it.

## Alternatives considered

- **Option A** — why it lost.
- **Option B** — why it lost.

## Consequences

What this buys, what it costs, and what must be revisited if the assumption
breaks.
```

## Review rules

- `## Alternatives considered` is mandatory. A decision that does not name what
  it beat will be re-argued.
- Write complete contracts and context, not a transcript of the discussion.
- Link related notes and source paths; do not duplicate the standard.
- A note that no longer matches the code is a bug: update it or mark it
  archived in place.
