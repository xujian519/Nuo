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
