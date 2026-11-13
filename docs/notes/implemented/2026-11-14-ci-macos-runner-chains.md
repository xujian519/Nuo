# CI: two macOS chains instead of six parallel lanes (run 43476983762)

## Problem

Every macOS lane in `ci.yml` asked for a `macos-26` runner at the same time:
`build-core-tests`, `test-core`, `test-cli`, `test-packages`, `test-statspack`,
`test-evals`, `swiftlint`. The repository's hosted macOS arm64 pool supplied
about two concurrent runners, so the rest sat in the queue until the platform
gave up.

Evidence from run [43476983762](https://github.com/xujian519/Nuo/actions/runs/43476983762)
(head `a80dddab5`), attempt 2:

| Lane | Result | Runner |
|---|---|---|
| `test-cli` | success (1m53s) | `GitHub Actions 1000042750` |
| `test-statspack` | success | `GitHub Actions 1000042766` |
| `brand-guard` / `standards-guard` / `shellcheck` | success | ubuntu |
| `build-core-tests` | cancelled | none (`runner_id = 0`, zero steps) |
| `test-evals` | cancelled | none |
| `test-packages` | cancelled | none |
| `swiftlint` | cancelled | none |
| `test-core` | cancelled | none (`needs` build, so it had nothing to run) |

The cancelled lanes carried the annotation "The job was not acquired by Runner
of type hosted even after multiple attempts" and "Due to capacity constraints,
jobs targeting macOS arm64 runners may experience longer queue times." Each was
cancelled 15 minutes after it was dispatched, having executed no step, so
`timeout-minutes` was not the cause and raising it does not help.

`test-core` still failed the run on its own terms: its first step,
`Require successful test build`, fails when the build lane did not succeed —
that is the intended behaviour for a required check, not a second bug.

## Decision

The macOS lanes now run as two chains that name their predecessor, so at most
two of them ever wait for a runner:

- **Chain 1**: `build-core-tests` → `test-core` (unchanged; `test-core` keeps
  `if: always()` because a cancelled build must fail the required check).
- **Chain 2**: `swiftlint` → `test-cli` → `test-packages` → `test-evals` →
  `test-statspack`.

Chain members carry `if: ${{ !cancelled() }}`: a failed earlier gate must not
hide a later lane's result, while a workflow cancel (the `ci-${{ github.ref }}`
concurrency group, or a person cancelling) stops the chain instead of
dispatching four more jobs.

Nothing else moves: job names, artifact upload, cache keys, per-lane
`timeout-minutes`, and every existing gate stay as they were, so
`REQUIRED_CI_JOBS` in `scripts/ci/verify-standards-contracts.py` still matches.

## Consequences

- A run needs two macOS runners instead of six, which fits the pool this
  repository actually gets.
- Wall clock grows: chain 1 is bounded by 45 + 60 minutes, chain 2 by
  10 + 10 + 15 + 45 + 45 minutes, so a cold run is roughly two hours instead of
  the ~70 minutes a six-runner pool would have taken.
- A failure inside a chain delays the next lane instead of reporting alongside
  it. Gate results are still complete, because the chain continues past a
  failure.
- Lane-level timing annotations keep working, so a slow lane is still visible
  in the run summary.
- Related PRs that touch CI know the ordering: `swiftlint` now runs before
  `test-cli`, and `test-statspack` last.

## Tests

- `python3 scripts/ci/verify-standards-contracts.py --self-test` — the guard
  still sees all ten required job names and the four required command lines.
- `python3 scripts/ci/verify-doc-links.py --self-test`.
- `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
  plus a dump of every job's `needs` / `if` to confirm the two chains.
- The change itself is proven by the next CI run on `main`: it must acquire a
  runner for every macOS lane and report `build-core-tests`, `test-core`,
  `test-cli`, `test-packages`, `test-statspack`, `test-evals`, and `swiftlint`
  instead of cancelling them.

## First chained run: the chains held, no runner arrived

Run [43487742129](https://github.com/xujian519/Nuo/actions/runs/43487742129)
(head `9f2aeef7f`) dispatched exactly the two chain heads it should have —
`build-core-tests` and `swiftlint` — and nothing else until they settled. Both
were still cancelled with `runner_id = 0` and zero steps, carrying the same
"not acquired by Runner of type hosted" and "capacity constraints, macOS arm64"
annotations, while the three ubuntu jobs on the same run started in seconds.
`test-core` and `test-cli` then became the next dispatched pair and queued
behind them.

So the queue shape is now what the pool can serve; the pool itself offered no
macOS arm64 runner at that moment. On attempt 2 of run `43476983762`,
`test-cli` and `test-statspack` did get runners and passed, so this is
intermittent capacity rather than a broken workflow or a bad label. The chains
stay — six lanes would have starved harder — and the remaining options are a
retry when capacity returns, or a runner this repository controls.

`macos-15` is not a drop-in swap: that image tops out at Xcode 26.3, while
`macos-26` carries the pinned 26.4.1, so changing the label also changes the
toolchain pin.

## Alternatives considered

- **Raise `build-core-tests` from 45 to 60 minutes and merge
  `test-packages` into `test-statspack`.** Rejected: the cancellations happen
  before any step runs, so the budget is not what fails. Merging two lanes also
  trades a fast lane for a longer one while still dispatching five jobs into a
  two-runner pool.
- **Merge every macOS lane into one job.** Rejected: it serializes the same
  work, loses per-lane `timeout-minutes` and per-lane logs, and makes a single
  lane's failure hide the timing of the rest, for no gain over two chains.
- **Serialize all six lanes with `needs` in one chain.** Rejected: it fits the
  pool but wastes the second runner the pool does give, pushing a cold run past
  four hours.
- **Register a self-hosted runner.** Deferred: it removes the dependency on the
  hosted pool, but it also asks a machine to stay on and run repository code.
  Worth revisiting if the chains still starve.
- **Mark the macOS lanes `continue-on-error` so the run looks green.** Rejected
  outright: a gate that cannot run must be visible as missing, not passing.
- **Drop `macos-26` to another label.** Not tried: the images behind other
  labels do not carry the pinned Xcode 26.4.1, and reverting the toolchain pin
  to dodge a queue is a larger regression than a slower run.
