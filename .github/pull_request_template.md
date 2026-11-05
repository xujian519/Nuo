## Summary

Explain the motivation and the changes. Link issues (e.g., Closes #123).

## Changes

- [ ] Behavior change
- [ ] UI change (screenshots below)
- [ ] Refactor / chore
- [ ] Tests
- [ ] Docs

## Test Plan

Steps to verify locally (commands, screenshots, recordings). Include model used.

## Evidence

- Source SHA: `<sha>`
- Commands run: `<make test | make ci-test | scripts/i18n/check.sh | ...>`
- Artifacts / logs: `<paths or hashes>`
- Runtime or live-UI rows: `<proven / partial / failed / unproven>` (required when a model, cache, tool, or user-facing lifecycle changes)

## Alternatives considered

Required for non-trivial changes; link the decision note in `docs/notes/` instead
of repeating it here.

## Screenshots

If UI updated, add before/after.

## Checklist

- [ ] I have read `docs/DEVELOPMENT_STANDARDS.md` and `CONTRIBUTING.md`
- [ ] I ran the narrow gate set for this change surface (commands listed above)
- [ ] I added/updated tests where reasonable
- [ ] I updated the settings catalog, i18n catalog, brand rules, and docs where applicable
- [ ] Non-trivial change includes a decision note with `## Alternatives considered`
- [ ] UI changes include before/after; runtime changes include the fields required by `docs/RUNTIME_VALIDATION_STANDARD.md`
- [ ] I verified build on macOS with Xcode 16.4+
