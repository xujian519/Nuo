# CI: macOS lanes run on a self-hosted runner (m4pro)

## Problem

The hosted `macos-26` arm64 pool did not hand this repository runners. Run
[43487742129](https://github.com/xujian519/Nuo/actions/runs/43487742129)
dispatched only the two chain heads from the previous decision
(`2026-11-14-ci-macos-runner-chains.md`), and both were cancelled 15 minutes
later with `runner_id = 0` and zero steps, annotated "not acquired by Runner of
type hosted" and "capacity constraints, macOS arm64". The three ubuntu jobs on
the same run started within seconds. The chains fixed the queue shape; the pool
itself was empty.

## Decision

Register `m4pro` (this Mac) as a repository-level self-hosted runner and move
every macOS lane onto it.

- Runner: `actions/runner` 2.338.2, `~/actions-runner-nuo`, labels
  `self-hosted`, `macOS`, `ARM64`, `nuo-macos`. Installed as a launchd agent
  (`~/Library/LaunchAgents/actions.runner.xujian519-Nuo.m4pro.plist`), so it
  runs while the user is logged in.
- All seven macOS jobs request `runs-on: [self-hosted, macOS, ARM64, nuo-macos]`.
- **Xcode pin moved from 26.4.1 to 27.2.** The machine carries one Xcode, 27.2
  at `/Applications/Xcode.app`; the old pin named
  `/Applications/Xcode_26.4.1.app`, which does not exist here.
  `maxim-lobanov/setup-xcode` is gone with it: that action runs
  `sudo xcode-select -s`, and the runner is a launchd agent with no
  passwordless sudo. `DEVELOPER_DIR` is set at workflow level instead, and each
  job that builds asserts `xcodebuild -version` equals `XCODE_VERSION` so a
  machine with a different toolchain fails loudly.
- **DerivedData is isolated.** Cache restore, the build, the prune step, and
  the pack/unpack of test products all use `${{ runner.temp }}/DerivedData`;
  `scripts/ci/core-test-products.py` gained `--derived-data` for that. Xcode's
  default location is the operator's own DerivedData, and the cache step
  replaces it wholesale while the prune step deletes first-party products from
  it.
- **Test roots are isolated.** `test-core` sets `OSAURUS_TEST_ROOT` and
  `OSU_MODELS_DIR` to empty `/tmp/nuo-ci` paths and recreates them per run. On a
  machine with real models in `~/MLXModels`, dispatch-style tests otherwise
  resolve and try to load them inside the iOS-less SwiftPM harness.
- **Fork pull requests never reach the runner.** This repository is public, so
  every macOS job carries
  `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`.
  Fork PRs still get the three ubuntu guards; the macOS checks report skipped.
- The two chains stay as ordering, which is now what one runner enforces
  anyway: `build-core-tests` → `test-core`, and `swiftlint` → `test-cli` →
  `test-packages` → `test-evals` → `test-statspack`.

## First real test run on the machine: two environment assumptions

Run [43498206739](https://github.com/xujian519/Nuo/actions/runs/43498206739)
attempt 2 got every macOS lane onto `m4pro`; `swiftlint`, `build-core-tests`,
`test-cli` and `test-packages` passed. `test-core` reported 118 failed out of
12,204 (`xcrun xcresulttool get test-results summary`), in two groups that are
both about the machine rather than the code:

- **107 locale failures.** The suite asserts English copy; this Mac runs
  Simplified Chinese. Examples: `paragraphTexts(blocks)` returned
  "已中断 — 在生成回复之前已停止。" where the test expects "Interrupted — stopped
  before a response was produced.", and a breadcrumb came back as
  ["通用", "General", "Global Hotkey"]. A hosted image is English, so the suite
  never had to say which language it means.
- **11 keychain failures with `-25308` (`errSecInteractionNotAllowed`).** The
  login keychain already holds this operator's app secrets, and a freshly built
  test binary is a different signer, so reading one requires approval. A launchd
  job cannot answer, so the read fails; running the same suite from a terminal
  instead pops a SecurityAgent dialog and hangs. A hosted runner starts with an
  empty keychain, so the suite had never met a pre-existing item. `test-core`
  now creates an empty unlocked keychain in `/tmp/nuo-ci`, makes it the only
  entry in the user search list and the default for the duration of the suite,
  and restores the login keychain in an `if: always()` step.

The keychain fix holds: the next run reported 116 failures with **zero**
keychain ones.

### Locale: accepted as a known failure (decided 2026-11-14)

`test-core` still fails on the self-hosted runner, and this is the accepted
state. The suite asserts English copy, this machine's system language is
Simplified Chinese, and `L()` resolves `String(localized:bundle:.module)`
through the process's `AppleLanguages` default. Four ways to override it were
tried against a real xctestrun on the machine, and none of them moved the
strings:

| Attempt | Result |
|---|---|
| `xcodebuild test-without-building -testLanguage en -testRegion US` | ignored for this action |
| `TestLanguage`/`TestRegion` written into the xctestrun | strings stay Chinese |
| `EnvironmentVariables: { AppleLanguages: (en) }` in the xctestrun | strings stay Chinese; a standalone probe confirmed `Locale.preferredLanguages` ignores the variable |
| `CommandLineArguments: [-AppleLanguages, (en)]` | the harness reads them as test selectors and executes 0 tests |

The chosen option is to leave the failure visible: 116 of 12,204 cases fail,
`test-core` is red, and the workflow comment plus this note say why. The two
alternatives considered were flipping the machine's global `AppleLanguages`
for the length of the job (every app launched in that window would come up in
English) and registering the runner under a separate English-locale macOS
account. Either is a one-line decision away if a green `test-core` becomes a
requirement.

Losing the `-testLanguage`/`-testRegion` flags is deliberate: they do nothing
here, and leaving them would imply the lane is locale-pinned.

## Evidence

- Registration: `gh api repos/xujian519/Nuo/actions/runners` lists `m4pro`,
  labels `self-hosted, macOS, ARM64, nuo-macos`, `status: online`.
- End-to-end proof: dispatch-only workflow run
  [43494553116](https://github.com/xujian519/Nuo/actions/runs/43494553116)
  executed all six steps on `runner=m4pro` — `Darwin 27.2.0 arm64`,
  `macOS 27.2.1`, `Xcode 27.2`, `Swift 6.4.2`, and
  `standards-guard: all config contracts hold`. That workflow was a probe and
  was removed in `5653a8103`.

## Consequences

- A run is bounded by one machine: the two chains execute back to back, so a
  cold run is roughly three to four hours instead of never finishing. Warm
  caches shorten that.
- The Mac must be awake and logged in for CI to run. `./svc.sh stop` pauses it,
  `./svc.sh uninstall` removes the launchd agent.
- The runner executes repository code as the logged-in user. The fork guard is
  the containment: only pushes to `main`, `workflow_dispatch`, and PRs from
  branches inside this repository reach it.
- `defaults write com.apple.dt.XCBuild IgnoreFileSystemDeviceInodeChanges -bool YES`
  in `build-core-tests` writes a user-level Xcode preference. It is what makes a
  restored DerivedData usable; it also applies to the operator's own builds on
  this machine.
- Fork PRs no longer get macOS CI. Acceptable while the only contributor is the
  repository owner; the guard is the line to revisit if outside contributions
  need macOS coverage.

## Tests

- `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
  and a dump of every job's `runs-on` / `needs` / `if`.
- `python3 -m unittest discover -s scripts/ci -p test_core_test_products.py`.
- `python3 scripts/ci/verify-standards-contracts.py --self-test`: all ten
  required job names and the four required command lines survive.
- `python3 scripts/ci/verify-doc-links.py --self-test`, `bash scripts/i18n/check.sh`.
- The real proof is the next CI run on `main`: every macOS lane must report on
  `m4pro` instead of being cancelled.

## Alternatives considered

- **Install Xcode 26.4.1 on this machine and keep the old pin.** Rejected for
  now: it is a ~7 GB download behind an Apple ID, and the local toolchain is
  already 27.2, which is what this machine builds with outside CI. Revisit if a
  lane proves to depend on 26.4.1 behaviour.
- **Keep the lanes on `macos-26` and retry until the pool hands out runners.**
  Rejected: two full attempts over an hour produced zero runners for the heavy
  lanes while a machine sat idle.
- **Switch `runs-on` to `macos-15`.** Rejected: that image tops out at Xcode
  26.3, so it would move the toolchain anyway while keeping the same contended
  arm64 pool.
- **Run two runner instances on this Mac for parallelism.** Not done: it doubles
  CPU contention with the operator's own work, and the chains already serialize
  safely. A second instance is the first thing to try if wall clock matters.
- **Make the repository private instead of adding the fork guard.** Not done:
  the guard keeps fork PRs off the machine without changing who can read the
  project.
- **Skip the macOS lanes on PRs entirely and run them only on `main`.** Rejected:
  that removes the feedback the lanes exist for; same-repo branches still get
  them under the guard.
