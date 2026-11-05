# Note: Replace the dinosaur agent avatars with illustrated portraits

Status: implemented

## Problem

`docs/brand/NUO-REBRAND-PLAN.md` Phase 4 left the six `osaurus-avatar-*`
mascots as dinosaurs. They are the most-seen imagery in the product — the agent
list, the chat source badge, the Orchestrator header, and the onboarding avatar
strip all go through `AgentAvatarView`. The copy had already stopped calling the
agent a dino (`2026-11-05-retire-dino-metaphor.md`), so the words and the picture
disagreed on first launch.

The built-in Orchestrator had a second problem: it shared the `green` mascot with
any user-created green agent, so nothing visually distinguished the agent that
configures the app from an ordinary one.

## Decision

Replace the artwork, keep every identifier.

- Six new portraits land in the existing `osaurus-avatar-{blue,green,orange,
  purple,red,yellow}.imageset` directories under their existing file names. The
  imageset name is a key into `AgentMascot.assetName`, referenced from 27 call
  sites; renaming directories would be pure churn, and the brand shows in the
  pixels, not the resource name.
- A seventh imageset, `nuo-primary-avatar.imageset`, carries the Orchestrator
  portrait. `AgentMascot` gains `case primary` plus a hand-written
  `allCases` that omits it, so the three `allCases` consumers — the
  onboarding strip, the two `AgentsView` pickers, and the randomizer — exclude
  it with no edits. `Agent.default.avatar` moves from `"green"` to `"primary"`.
  `DefaultAgentConfiguration` does not persist an avatar, so no migration is
  needed and no stored value can resurrect the old one.
- `AvatarBitmapRenderer` is untouched: the new art is transparent, square, and
  bottom-pinned, so the existing center-crop + vImage resample produces the same
  1:1 bitmap the dinosaurs did.

Art was generated locally with ComfyUI's Z-Image Turbo stack (8 steps, cfg 1.0,
`res_multistep`, `simple`, 1024², fixed seed per mascot), cut out with a
border-median background mask intersected with border-connected components, then
normalised so the artwork bbox is 0.86 × canvas wide and pinned to the canvas
bottom. Exported at 256/512/768 px for the three scale slots.

## Alternatives considered

- **Rename the imagesets to drop `osaurus`.** Rejected: 27 Swift call sites plus
  the asset-catalog paths, for no user-visible gain. The frozen-identifier rule
  in `docs/brand/INTERNAL-IDENTIFIERS.md` already covers asset names.
- **Give the Orchestrator a monogram instead of a portrait.** Rejected: the
  Orchestrator is the one agent that has a fixed identity, and a letter loses to
  a face in the header and chat badges.
- **Add `.primary` to `allCases` and filter it at each consumer.** Rejected:
  three call sites would each need to remember the exclusion; the next consumer
  would get it wrong. Excluding it from the enum's own `allCases` makes the
  correct behaviour the default.
- **Tint the portrait to the mascot colour.** Rejected: the sub-agent portraits
  are differentiated by clothing colour in the art itself; a tint wash on top
  would flatten them.
- **Use IPAdapter / ControlNet / a LoRA for character consistency.** Not
  available in the installed ComfyUI stack. Consistency across the seven
  portraits is stylistic (same render style, same framing, same lighting), not
  identity-locked — recorded honestly in the plan.

## Not covered

`osaurus-brain` and the `osaurus-*-create` onboarding illustrations are still
dinosaur-era art; the wordmark SVG is still the `OSAURUS` outline. They need
separate art passes and stay listed under Phase 4.
