# Note: Cut the built-in themes to Light + Dark and repaint them from Radix Colors

Status: implemented

## Problem

The theme gallery shipped **eight** built-in presets — Dark, Light, Neon, Nord,
Paper, Terminal, Nuo Dark and Nuo Light. Seven of them were palette sketches
from earlier rounds, each one a hand-picked set of hex values with no shared
ramp behind it. In practice nobody could tell which one was "the" Nuo look,
and the ones that were distinctive (Neon, Terminal) read as costume rather
than as product.

The two canonical themes were no better as a *system*: `NuoHex` in
`Packages/NuoDesignSystem/Sources/NuoDesignSystem/NuoColor.swift` held 27
hand-tuned values ("paper" `#F7F4ED`, "cinnabar" `#C93A2B`, …) that did not
correspond to any published scale, so contrast ratios had to be re-derived by
hand every time a value moved.

The request was to keep only a light and a dark theme, let both follow the
system appearance, and take the colors from a well-regarded open-source
palette. Everything else about the theme system — import/export, the editor,
custom themes, per-agent themes — stays as it was.

## Decision

The built-in catalog is exactly two entries, `CustomTheme.darkDefault` and
`CustomTheme.lightDefault`, and both are repainted from **Radix Colors**
(MIT) 12-step ramps.

- **Neutral layer — `sand`, not `gray`.** `sand` is a warm gray; `gray` is
  neutral and washes out the paper warmth the brand depends on. Light mode
  takes `sand-1…3`, dark mode `sand-1…4`, so the same semantic (canvas,
  card, sunken panel, floating surface) lands on the same step in both
  directions.
- **Accent layer — `tomato`.** It shares the hue family of the existing
  cinnabar `#C93A2B`, so "cinnabar means presence / commit"
  (`docs/nuo-ui/DESIGN_SPEC.md` §2.2) still holds and the "red = important"
  double encoding survives. Error uses `red`, not `tomato`, so the two stay
  separable by hue.
- **Tertiary text is `sand-12` at 65 % alpha.** Radix's 12 steps only clear
  4.5:1 on a light canvas at steps 11 and 12, so there is no third opaque
  text step between them. The alpha form mirrors Radix's own `*-a` alpha
  ramps and lands at 5.00:1 (light) / 7.05:1 (dark). `NSColor(nuoHex:)` now
  accepts `RRGGBBAA` so the token layer can carry it.
- **Status colors invert by mode.** Light mode uses step 12 (`green-12`
  `#193B2D`, `amber-12` `#4F3422`, `red-12` `#641723`) because step 11 misses
  4.5:1 on the warm canvas; dark mode uses step 11 (`#3DD68C`, `#FFCA16`,
  `#FF9592`). Light status text sinks, dark status text lifts.
- **Component borders use `sand-10`**, which clears 3:1 against every surface
  in both modes. `hairline` stays at `sand-6` because it is a separator, not
  an information-bearing boundary.
- **`followsSystemAccent` stays `false`** for both built-ins. "Follow the
  system" means *appearance* follows the system light/dark, not *accent*
  follows the macOS accent color — the accent is brand semantics, and letting
  the system recolor it would silently replace cinnabar with system blue.
  Custom themes keep the opt-in.

`ThemeConfigurationStore.currentBuiltInThemeSchema` moves 7 → 8. On upgrade
the two canonical themes are reinstalled with the new palette, and the six
retired presets' JSON files are deleted from `~/.nuo/themes/` — leaving them
behind would keep them visible in the gallery as stale local themes with the
old colors. If the active theme was one of them, the active reference is
cleared so the app falls back to appearance-driven resolution.

`ThemeManager.startupSelection` treats a built-in theme that is neither
canonical Dark nor canonical Light as **absent**. The active theme is read
during `ThemeManager.init`, which runs *before* the deferred install that
deletes the retired files; honoring it there would boot the app on a palette
that no longer exists in the catalog and keep it for the whole session.

The contract is machine-checked:
`Packages/OsaurusCore/Tests/Theme/ThemePaletteContrastTests.swift` asserts
body text ≥4.5:1 against **every** surface it can land on (canvas, card,
sidebar, sunken panel, button, input, code block), accent ≥4.5:1 on canvas
and card and ≥3:1 elsewhere, component borders ≥3:1, and syntax colors on the
code background. `ThemeBuiltInMigrationTests` asserts the retired files are
deleted and that the store installs exactly two themes.

## Alternatives considered

- **GitHub Primer** — a good scale, but its neutral ramp is blue-tinted and
  its accent is blue. Using it would have contradicted the cinnabar brand
  discipline outright.
- **Catppuccin** — beautiful, but pastel-first and built around an
  eight-color accent family. The brand is two hues, not eight.
- **Keeping more presets** — every additional preset is another palette
  nobody maintains, another file to migrate, and another thing users have to
  triage. Two is the number that matches how many people actually use themes.
- **`gray` instead of `sand` for the neutral layer** — rejected: it removes
  the warm paper cast that the whole "paper and ink" language rests on.
- **Keeping step-11 status colors in light mode** — `green-11` measures
  4.48:1 and `amber-11` 4.38:1 on the warm canvas, just under AA. Rather
  than publish a table with failing cells, the status text takes step 12 and
  the shade distinction is carried by hue plus the mandatory icon.
- **Pre-blending tertiary text into an opaque hex instead of using alpha** —
  rejected: the blended value would be a value that exists in no ramp, and
  it would not follow if the canvas ever changed.
- **Enabling system-accent following on the built-ins** — rejected: the user
  chose "appearance follows the system", and the accent is a brand meaning,
  not a preference.
- **Deleting the retired theme files at the file-system level without a
  schema bump** — rejected: `installBuiltInThemesIfNeeded()` only rewrites
  built-ins when the stored schema is older, so without the bump the new
  palette would never reach existing installations either.

## Consequences

- The gallery shows two themes; the six retired ones are gone for good.
  Users who want one of those palettes can still import a theme JSON or
  duplicate a built-in theme in the editor.
- Every text color is now traceable to a published scale, so re-tuning means
  picking a different step instead of hand-picking a hex value.
- The palette is no longer arbitrary, but it is also no longer free: the
  accent is a tomato red rather than the exact `#C93A2B` cinnabar, and the
  light-mode status colors are deeper than before. The brand reads as
  "warm paper + cinnabar" rather than "the exact old hex values".
- `inkGhost` and `hairline` remain below 3:1 by design — they are decorative
  only, and the rule that `inkGhost` must never carry text is unchanged.
- `docs/nuo-ui/DESIGN_SPEC.md` §3.1 and `docs/ACCESSIBILITY.md` now carry the
  new values and the measured ratios.
