# Note: Settings search matches the translated title

Status: implemented

Issue #13. A Chinese UI could not find a setting by the title on screen.

## Problem

`SettingsSearchIndex` stored the English catalog key (`title`, `section`).
The settings screen renders that key through `Localizable.xcstrings`, so
「定向邮箱」is what the user sees for "Directed Mailbox". Search compared the
query to the English key, the English section, the keyword list, and the
already-translated tab label. A Chinese query matched none of those.

## Decision

`SettingsSearchIndex.search` also matches `LCached(title)` and
`LCached(section)`. A translated title ranks with the source title. The source
strings stay in the match set, so an English query still hits when the UI is
Chinese. `tab.label` was already localized and is unchanged.

The localizer is a default argument. Tests inject a map instead of changing
the process locale. One probe reads the compiled `zh-Hans` catalog and checks
that "Directed Mailbox" is 「定向邮箱」, then searches that string.

## Alternatives considered

- **Hand-written localized keywords on every catalog row.** Lost. The
  translation would live in the index and in `Localizable.xcstrings`. The next
  catalog edit would not update search.
- **Walk the built SwiftUI tree and index the rendered labels.** Lost. Search
  runs before the destination tab exists, and a control that is off-screen
  would disappear from the index.

## Live proof

2026-11-13, isolated Release app `com.nuo.proof.issues20261113` at
`/tmp/nuo-issue-proof/DerivedData`, data root `/tmp/nuo-issue-proof/ui-root`.
The system language was `zh-Hans-CN`. Settings search for 「定向邮箱」showed
「1 个设置匹配」and one row titled 「定向邮箱」under 编排器. Selecting that row
opened 编排器 with the 定向邮箱 section on screen. `~/.nuo` was not modified.
