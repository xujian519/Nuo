# Nuo development standards

This is the normative standard for every change in this repository. It is a
specification, not a wish list: every rule names the file that owns it, the
machine check that enforces it (or an explicit `REVIEW-ONLY` status), and where
the rationale lives.

`AGENTS.md` holds agent standing orders. `docs/CONTRIBUTING.md` owns the
architecture layers and naming table. `docs/RUNTIME_VALIDATION_STANDARD.md` owns
runtime proof for models, caches, tools, and media. This file owns gates,
process, and definition of done. When they disagree, this file wins for process
and the runtime standard wins for runtime evidence.

## 1. Meta-rules (rules about rules)

1. **Statement + gate + rationale.** When adding a rule, answer all three:
   where is its home, what machine check rejects a violation, and where is the
   reason recorded. A rule without a gate must be labelled `REVIEW-ONLY`; do not
   imply enforcement that does not exist.
2. **One home per fact.** Put each rule in exactly one of: `AGENTS.md`
   (standing orders), `docs/CONTRIBUTING.md` (architecture and naming),
   `docs/RUNTIME_VALIDATION_STANDARD.md` (runtime proof), `docs/brand/` (brand
   contracts), or `docs/notes/` (decision history). Other homes link; they do
   not restate the rule.
3. **Facts are generated or gated.** Inventories such as the settings catalog,
   support matrices, and default tables must be generated from source or
   checked by a gate. A hand-maintained list is a future stale list.
4. **Exceptions are explicit.** Put a narrow inline exception and its reason
   next to the code or rule. A file-level or global rule disable is a bug unless
   it is recorded in a decision note.
5. **Local narrow, CI full.** Hooks stay fast. CI owns exhaustive coverage and
   the platform matrix. Never rehearse the whole suite before every commit, and
   never skip the narrow set that matches your change surface.
6. **Negative control.** A gate is real only when a known regression visibly
   fails it. New gates ship with a self-test or fixture that proves they reject
   an invalid input (`python3 scripts/ci/verify-standards-contracts.py --self-test`).
   A gate that cannot be seen to fail is treated as absent.
7. **Decision notes for non-trivial work.** Behavior, architecture, contract,
   process, or format changes carry a note in `docs/notes/` with an
   `## Alternatives considered` section in the same change.
8. **Evidence over claims.** "Tests pass", "works", or "fixed" require the
   command, artifact, or live observation that proves it. Unproven rows stay
   `PARTIAL` or `BLOCKED`.
9. **Coverage is a dead-code detector, not a KPI.** An uncovered line is first
   presumed dead and deleted, not covered with a hollow test. This repository
   has no coverage gate yet; see §2 for the honest status.
10. **Prose is local.** Comments explain why the adjacent code is shaped this
    way. Do not restate code, narrate control flow, or preserve review history.

## 2. Gate inventory

Status legend: `ENFORCED` = a machine check fails the build; `SELF-TESTED` =
enforced and has a negative control; `REVIEW-ONLY` = reviewer obligation, no
machine check; `TODO` = known gap, do not describe it as enforced.

| Gate | Command / job | What it proves | Status |
|---|---|---|---|
| Formatting | `swift-format lint --strict --recursive Packages App` (lefthook pre-push) | Style is mechanical, not argued in review | ENFORCED |
| SwiftLint | `swiftlint lint` (CI `swiftlint`) | Opt-in rules and analyzer checks still apply | ENFORCED |
| Shell lint | `shellcheck --severity=warning` (CI `shellcheck`) | Scripts fail closed before they run in release paths | ENFORCED |
| Localization | `bash scripts/i18n/check.sh` (CI `build-core-tests`) | Required catalogs parse and every Swift literal maps to a catalog key | ENFORCED |
| Brand | `bash scripts/brand/verify.sh` (CI `brand-guard`) | Frozen identifiers are intact and no legacy brand string leaks outside the allowlist | ENFORCED |
| Standards contracts | `python3 scripts/ci/verify-standards-contracts.py --self-test` (CI `standards-guard`) | The config contracts in this standard still exist and a weakened config is rejected | SELF-TESTED |
| Core tests | `make test`, CI `test-core` | OsaurusCore behavior under the shipped test configuration | ENFORCED |
| CI mirror | `make ci-test` | A failed CI run reproduces locally with one worker and the same allowances | ENFORCED |
| CLI tests | CI `test-cli` | `Packages/OsaurusCLI` still builds and passes | ENFORCED |
| Package tests | CI `test-packages` | Repository install path and PluginTestKit contracts | ENFORCED |
| Plugin tests | CI `test-statspack` | Bundled runtime reads OsaurusCore correctly | ENFORCED |
| Evals harness | `make evals-test`, CI `test-evals` | Fixture decode, scorers, regression-lab plumbing | ENFORCED |
| Deterministic evals | `make evals-deterministic` (`--fail-on-floor`) | Token-free suites keep their pinned pass rate | ENFORCED |
| Runtime proof | `docs/RUNTIME_VALIDATION_STANDARD.md` + targeted evals | Model/cache/tool behavior matches the claimed row | REVIEW-ONLY |
| Live UI proof | `AGENTS.md` release-proof section | The built app exposes and applies the change | REVIEW-ONLY |
| Doc links | `python3 scripts/ci/verify-doc-links.py --self-test` (CI `standards-guard`) | Every relative Markdown link resolves inside the checkout | SELF-TESTED |
| Doc budgets | none | — | TODO |
| Coverage | none | — | TODO (no coverage gate; CI builds with coverage off) |
| PR title and commit format | none | — | REVIEW-ONLY |

`REVIEW-ONLY` rows are obligations on the author and reviewer. They are not
optional because they lack a bot.

## 3. Change surface to evidence

Pick the smallest set that can catch the regression, then stop.

| Change surface | Minimum evidence |
|---|---|
| Swift source in `Packages/OsaurusCore` | `make test` plus the focused suite for the touched area |
| Test harness or CI plumbing | `make ci-test`, or the exact CI command being changed |
| User-visible string or catalog | `bash scripts/i18n/check.sh` |
| Brand-visible text, icon alt text, marketing copy | `bash scripts/brand/verify.sh`; add a rule under `scripts/brand/rules/` for a new surface |
| Setting added/renamed/moved | Settings catalog steps in `AGENTS.md` plus a live app click-through |
| Runtime, parser, tool, cache, delegation, model default | `docs/RUNTIME_VALIDATION_STANDARD.md` rows and the applicable evals lanes |
| Shell script | `shellcheck` on the changed file plus a dry run where possible |
| Docs only | The checks named in the doc plus a link review; no code suite required |

Do not repeat a passing check for a new commit, and do not run the full matrix
locally unless the change is repository-wide, CI is being diagnosed, or the
user asks for it.

## 4. Swift and code rules

- **Toolchain.** Swift tools `6.2`; the app target builds with
  `SWIFT_STRICT_CONCURRENCY = complete`. New code must be concurrency-clean
  under that setting.
- **Isolation.** UI state is `@MainActor`; long-lived services are `actor`;
  crossing a boundary requires `Sendable` or an explicit isolation annotation.
  `@unchecked Sendable` needs a comment naming the lock or invariant that makes
  it sound.
- **Banned in product code:** force unwrap `!`, `try!`, `as!`, silently
  swallowing `try?`, and `fatalError` on user-reachable paths. Convert them to
  guarded unwraps, typed throws, or a typed failure the caller can report.
- **Errors.** Fail loud at load when the problem is self-contained; otherwise
  fail at the earliest resolvable point. Give the user an actionable error that
  names the setting or resource limit. Never skip a missing referent silently.
  An empty `catch` must name the error and why ignoring it is safe.
- **Layering and naming.** Follow `docs/CONTRIBUTING.md`: Models are pure data,
  Services own logic and are not observable, Managers own UI state on the main
  actor, Views are SwiftUI. Use the documented `Manager` / `Service` / `Engine`
  / `Store` / `Database` suffixes.
- **Comments.** Keep them local and about rationale. One trailing newline per
  file.
- **Dependencies.** `osaurus.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  is the single source of truth. Keep both workspace mirror files in sync. Do
  not add separate root pins for MLX, tokenizers, Jinja, or vmlx internals that
  the consolidated `vmlx-swift` package owns. A dependency bump is an ASK FIRST
  change.
- **Generated or frozen code.** Do not hand-edit generated artifacts or frozen
  identifiers. Change the generator or the brand rule instead.

## 5. User-facing surfaces

- **Brand.** Never hand-edit a brand string and never run a repo-wide `sed`.
  Replay `scripts/brand/apply.sh` after an upstream merge; `scripts/brand/verify.sh`
  is the guard. New surfaces need a rule in `scripts/brand/rules/`. See
  `docs/brand/INTERNAL-IDENTIFIERS.md` for what stays frozen.
- **Settings.** `SettingsSearchIndex` is the single catalog for Management
  search and the Orchestrator. Any add, remove, rename, move, or label change
  updates the catalog row, the control anchor, `guide-settings.md`, and
  `SettingsSearchSelfFindProbe.swift` in the same change. A control that is not
  in the catalog is not shipped.
- **Localization.** Every user-visible string lives in the string catalog and is
  reached through a catalog key or the localized primitive. Do not add literal
  copy to SwiftUI views; `scripts/i18n/lint-swift-literals.sh` is part of
  `check.sh`.
- **Docs.** Update the affected README, guide topic, and settings path in the
  same change. One fact, one home. A guide path that disagrees with the catalog
  is a bug.

## 6. Tests and proof

1. **Real implementation first.** Mock only expensive or non-deterministic
   boundaries: network, clock, external services, model runtimes. Mock-green is
   not product-green.
2. **Exercise real entry points.** Product-visible behavior goes through the
   real loader, CLI, or HTTP surface. Test built CLI products with the shipped
   binary, not a builder helper that can hide module-resolution errors.
3. **Assert the world, not the report.** Re-read the file, re-run the command,
   compare bytes. Do not trust the object under test to describe its own result.
4. **Deterministic suites stay deterministic.** Evals that need no model, no
   embedder, and no network are pinned by `Config/floors.json` and must run
   with `--fail-on-floor`. New deterministic rows land with their floor.
5. **Keychain and model isolation.** Follow the keychain-disabled recipe in
   `AGENTS.md`. Tests that need real Keychain proof run without the flag and are
   named as such.
6. **Runtime proof is separate.** A unit test is a contract guard, not runtime
   evidence. Runtime claims follow `docs/RUNTIME_VALIDATION_STANDARD.md` and
   record proven, partial, failed, and unproven rows separately.

## 7. Commits and pull requests

- Use Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`,
  `chore:`. One logical change per commit. Do not mix a refactor with a
  behavior change in the same commit.
- Keep a PR reviewable. Changes above roughly 800 lines should be split unless
  they are mechanical or generated; justify the exception in the description.
- The PR description states the problem, the decision, the alternatives that
  lost, the exact commands run, and the evidence paths. UI changes include
  before/after; runtime changes include the fields required by the runtime
  standard.
- Do not paste AI-generated walls of text. Short, concrete, checkable claims
  only. Reviewers may close a PR whose description cannot be verified.
- Never post images to the repository and never commit credentials, tokens, or
  `.env` content. Use the keychain wrappers and CI secrets.
- If any required source trace, automated score, or live row is missing, report
  `PARTIAL` or `BLOCKED`. Do not describe the change as fixed, proven,
  release-ready, or regression-free.

## 8. Decision records

Non-trivial decisions live in `docs/notes/{proposed|implemented|rejected}/`
using `YYYY-MM-DD-topic.md`. See `docs/notes/README.md` for the template and
lifecycle. Rules:

- Create or update the note in the same PR as the change.
- `## Alternatives considered` is mandatory and must state why each alternative
  lost. A decision without alternatives will be re-argued.
- Never rewrite an implemented note into a different decision. Write a new note
  and link both.
- Archived notes are frozen history. They are not current authority.

Mechanical edits, local UI tweaks, and typo fixes do not need a note.

## 9. Agent boundaries

**Always do**

- Read `AGENTS.md` and this standard before changing code.
- Run the narrow gate set for the change surface.
- Update the settings catalog, i18n catalog, brand rules, and docs together with
  the code they describe.
- Keep proof artifacts and report the exact commands and SHAs used.
- Leave changes in the workspace unless the user asks for a commit or push.

**Ask first**

- Adding, removing, or bumping a dependency.
- Changing CI runners, toolchain pins, cache salts, or required checks.
- Renaming or deleting a public type, API route, tool name, or persisted field.
- Changing a default, admission limit, or RAM policy.
- Force-pushing, rewriting shared history, or deleting branches.

**Never do**

- Hand-edit brand strings, frozen identifiers, or generated artifacts.
- Commit secrets, credentials, or environment files.
- Add fake guards, placeholder gates, hidden sampler defaults, or parser repairs
  to make a row look safe.
- Bypass a failing test or gate to land a change.
- Weaken a lint or standard contract instead of fixing the violation.
- Spawn recursive local agent workers for release work unless the user
  explicitly asks.

## 10. Change checklist

- [ ] Rule or behavior has a home; no second source of truth introduced.
- [ ] Narrow gate set for the change surface run and recorded.
- [ ] Settings catalog, i18n, brand rules, and docs updated where applicable.
- [ ] Tests describe behavior and exercise a real entry point.
- [ ] Negative control updated if a gate or guard changed.
- [ ] Decision note written when the change is non-trivial.
- [ ] PR evidence names commands, SHAs, artifacts, and any `PARTIAL` rows.
