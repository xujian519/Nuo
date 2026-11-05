# Note: Scheme A seal mark

Status: implemented

## Problem

The app still presented the dinosaur as the product mark: Dock icon, menu bar,
onboarding splash, and the welcome line "A Dino for every side of your work."
Scheme A replaces that mark with the seal, using the photo masters until a
hand-traced SVG exists.

## Decision

`docs/brand/masters/` holds the PNG masters and the handoff. Asset catalog
imageset names stay put; only their contents change.

- AppIcon slots are downscales of `appicon-master-from-photo-1024.png`
  (`#F8141C` on `#FAF7F2`). `osaurus-app-icon.icon` uses the same master,
  paper fill, and no glass.
- `osaurus.imageset` is the filled glyph as an 18pt template image.
  `NSImage(named: "osaurus")` is unchanged.
- `osaurus-main` is the full seal centered on `#1E1E1E`.
- `osaurus-logo` (App and Core) uses the same glyph. The wordmark imageset
  is unchanged: no wordmark master was provided, and the old path must not
  be redrawn to fake one.
- `OnboardingPalette` brand accents are `sealRed`, `sealRedPressed`,
  `sealRedMuted`, and `paper`. `successGreen` is the old green, used only
  for verified / connected / ready. `AccentColor.colorset` is seal red.
- Welcome title and subtitle drop the Dino metaphor. The English keys are
  replayed by `ui-text.localizable` so an upstream merge does not restore
  them. Brain and create avatars stay for a later pass.

## Alternatives considered

- **Wait for the hand-traced SVG.** Lost for this PR. The handoff says PNG
  masters can land for layout review, and the vector export is still required
  before release. Auto-trace was already discarded.
- **Recolor the dinosaur.** Lost. Scheme A is a different mark, not a tint.
- **Rename imagesets to `nuo-seal`.** Lost. Swift looks up `osaurus`,
  `osaurus-main`, and `osaurus-logo` by those names.
- **Clear every Dino string and avatar in this change.** Lost. The handoff
  limits this pass to the welcome copy and the mark. Create-step avatars stay.

## Consequences

Dock, menu bar, and the welcome panel show the seal. 16px and 18px bitmaps
are soft until the SVG replaces them. `scripts/brand/apply.sh` will put the
welcome sentences back if a merge restores the Dino keys. Brain and create
illustrations still depict the dinosaur.
