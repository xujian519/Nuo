# Note: Retire the Dino metaphor from onboarding copy

Status: implemented

## Problem

Scheme A replaced the product mark but onboarding still called the agent a
"dino": "Meet your dino", "Create your Dino", "Say hi to your dino",
"Give your dino a brain", plus the avatar strip's accessibility labels
("Blue dino"). The welcome headline had already moved to "Local agents that
keep their word.", so the first-run flow contradicted itself within two
screens.

## Decision

Retire the metaphor in the brand rule layer, never by hand-editing strings.

`scripts/brand/rules/30-ui-text.json` gains:

- `ui-text.onboarding-agent-copy` (English): drives the 17 catalog key
  renames and syncs their whole-literal references in Swift.
- Five per-language rules (`-de`, `-ko`, `-ru`, `-zh-hans`, `-zh-hant`) that
  rewrite the translations with each language's word for "agent".
- `ui-text.agent-avatar-accessibility`: rewrites the six
  `AgentMascot.displayName` literals to "Blue agent" etc., leaving enum
  cases and `osaurus-avatar-*` asset names untouched.

Language-specific handling was required, so a single global `dino -> agent`
pair was not sufficient:

| Language | Trap | Handling |
|---|---|---|
| German | Agent is n-declension | accusative/possessive take `-en` (`deinen Agenten`), nominative stays `Agent` |
| Korean | particle agreement flips | `공룡` ends in a consonant (`을/이`) vs `에이전트` in a vowel (`를/가`) |
| Russian | four case forms | stem swap `динозавр -> агент` preserves endings automatically (`агенту`, `агентом`) |
| Chinese | measure word | `一只小恐龙 -> 一个智能体` |

## Alternatives considered

- **Hand-edit `Localizable.xcstrings`.** Rejected: breaks the replay contract
  and would be undone by the next upstream merge.
- **One global `dino -> agent` pair.** Rejected: produces `deinen agent`,
  `공룡이 -> 에이전트이`, and `设置一只智能体`.
- **Keep Dino as an in-product pet name.** Rejected: Scheme A positions the
  product as local agents; the pet name was the old brand's hook.
- **Delete the dead `Create Dino` catalog key.** Kept instead. It has no Swift
  reference; renaming it to `Create Agent` would duplicate an existing key in
  the JSON. It now sits as the similarly-dead `Create agent`.

## Not covered

The visual side is still dinosaur: six `osaurus-avatar-*` mascots (used
across the agent list, chat source badges, and onboarding), `osaurus-brain`,
and the `*-create` illustrations. Those need art, not a string rule; they
are tracked in `docs/brand/NUO-REBRAND-PLAN.md` Phase 4.
