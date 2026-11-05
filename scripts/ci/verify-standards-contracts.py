#!/usr/bin/env python3
"""Verify the config contracts that docs/DEVELOPMENT_STANDARDS.md depends on.

Each check guards one file that owns a rule. `--self-test` copies the guarded
files into a temporary root, asserts the guard passes, then mutates two
contracts and asserts the guard fails. That negative control is what makes this
guard real instead of decorative.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

REQUIRED_SWIFTLINT_OPT_IN = {
    "empty_count",
    "closure_spacing",
    "first_where",
    "sorted_first_last",
    "empty_string",
    "modifier_order",
}

REQUIRED_CI_JOBS = {
    "build-core-tests",
    "test-core",
    "test-cli",
    "test-packages",
    "test-statspack",
    "test-evals",
    "brand-guard",
    "swiftlint",
    "shellcheck",
    "standards-guard",
}

REQUIRED_AGENTS_SECTIONS = (
    "## Development standards",
    "## Commits and PRs",
    "## Settings catalog",
    "## Model Runtime Non-Negotiables",
)

REQUIRED_STANDARD_SECTIONS = (
    "## 1. Meta-rules",
    "## 2. Gate inventory",
    "## 8. Decision records",
)


def _read(root: Path, relative: str, problems: list[str]) -> str:
    path = root / relative
    if not path.is_file():
        problems.append(f"missing {relative}")
        return ""
    return path.read_text(encoding="utf-8")


def _yaml_list(text: str, key: str) -> list[str]:
    """Return items of a top-level YAML block list (no PyYAML dependency)."""
    items: list[str] = []
    in_block = False
    for line in text.splitlines():
        stripped = line.strip()
        if not in_block:
            if stripped.startswith(f"{key}:"):
                in_block = True
            continue
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("- "):
            items.append(stripped[2:].strip())
            continue
        if line[:1] != " ":
            break
    return items


def check(root: Path) -> list[str]:
    problems: list[str] = []

    swiftlint = _read(root, ".swiftlint.yml", problems)
    if swiftlint:
        opt_in = set(_yaml_list(swiftlint, "opt_in_rules"))
        missing = sorted(REQUIRED_SWIFTLINT_OPT_IN - opt_in)
        if missing:
            problems.append(
                ".swiftlint.yml dropped required opt-in rules: " + ", ".join(missing)
            )

    swift_format_text = _read(root, ".swift-format", problems)
    if swift_format_text:
        try:
            swift_format = json.loads(swift_format_text)
        except json.JSONDecodeError as error:
            problems.append(f".swift-format is not valid JSON: {error}")
        else:
            if swift_format.get("indentation", {}).get("spaces") != 4:
                problems.append(".swift-format must keep 4-space indentation")
            line_length = swift_format.get("lineLength")
            if not isinstance(line_length, int) or line_length > 120:
                problems.append(".swift-format lineLength must stay at or below 120")

    lefthook = _read(root, "lefthook.yml", problems)
    if lefthook and "swift-format lint --strict" not in lefthook:
        problems.append("lefthook.yml no longer runs swift-format lint on push")

    ci = _read(root, ".github/workflows/ci.yml", problems)
    if ci:
        jobs = set(re.findall(r"(?m)^  ([a-z][a-z0-9-]+):$", ci))
        missing_jobs = sorted(REQUIRED_CI_JOBS - jobs)
        if missing_jobs:
            problems.append("ci.yml dropped required jobs: " + ", ".join(missing_jobs))
        for command in (
            "bash scripts/i18n/check.sh",
            "bash scripts/brand/verify.sh",
            "scripts/ci/verify-standards-contracts.py --self-test",
            "scripts/ci/verify-doc-links.py --self-test",
        ):
            if command not in ci:
                problems.append(f"ci.yml no longer runs: {command}")

    agents = _read(root, "AGENTS.md", problems)
    if agents:
        for heading in REQUIRED_AGENTS_SECTIONS:
            if heading not in agents:
                problems.append(f"AGENTS.md dropped section: {heading}")

    standard = _read(root, "docs/DEVELOPMENT_STANDARDS.md", problems)
    if standard:
        for heading in REQUIRED_STANDARD_SECTIONS:
            if heading not in standard:
                problems.append(f"DEVELOPMENT_STANDARDS.md dropped section: {heading}")
        if "REVIEW-ONLY" not in standard:
            problems.append("DEVELOPMENT_STANDARDS.md no longer labels unenforced rules")
        if "Alternatives considered" not in standard:
            problems.append("DEVELOPMENT_STANDARDS.md dropped decision-note requirement")

    contributing = _read(root, "docs/CONTRIBUTING.md", problems)
    if contributing and "DEVELOPMENT_STANDARDS.md" not in contributing:
        problems.append("docs/CONTRIBUTING.md no longer points to the standard")

    notes_readme = _read(root, "docs/notes/README.md", problems)
    if notes_readme and "## Alternatives considered" not in notes_readme:
        problems.append("docs/notes/README.md dropped the alternatives requirement")

    for relative in ("scripts/brand/verify.sh", "scripts/i18n/check.sh"):
        if not (root / relative).is_file():
            problems.append(f"missing gate script {relative}")

    return problems


def _copy_contract_files(source: Path, target: Path) -> None:
    relative_paths = (
        ".swiftlint.yml",
        ".swift-format",
        "lefthook.yml",
        ".github/workflows/ci.yml",
        "AGENTS.md",
        "docs/DEVELOPMENT_STANDARDS.md",
        "docs/CONTRIBUTING.md",
        "docs/notes/README.md",
        "scripts/brand/verify.sh",
        "scripts/i18n/check.sh",
    )
    for relative in relative_paths:
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, destination)


def self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="nuo-standards-") as directory:
        root = Path(directory)
        _copy_contract_files(REPO_ROOT, root)

        baseline = check(root)
        if baseline:
            print("standards-guard self-test: baseline copy already fails", file=sys.stderr)
            for problem in baseline:
                print(f"  - {problem}", file=sys.stderr)
            return 1

        swiftlint_path = root / ".swiftlint.yml"
        original_swiftlint = swiftlint_path.read_text(encoding="utf-8")
        swiftlint_path.write_text(
            original_swiftlint.replace("  - empty_count\n", ""), encoding="utf-8"
        )
        if not check(root):
            print(
                "standards-guard self-test: weakened SwiftLint config was not rejected",
                file=sys.stderr,
            )
            return 1
        swiftlint_path.write_text(original_swiftlint, encoding="utf-8")

        ci_path = root / ".github/workflows/ci.yml"
        original_ci = ci_path.read_text(encoding="utf-8")
        ci_path.write_text(
            original_ci.replace("  standards-guard:", "  standards-guard-removed:"),
            encoding="utf-8",
        )
        if not check(root):
            print(
                "standards-guard self-test: a missing CI job was not rejected",
                file=sys.stderr,
            )
            return 1
        ci_path.write_text(original_ci, encoding="utf-8")

    print("standards-guard self-test: negative control rejected both mutations")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=REPO_ROOT,
        help="repository root to verify (defaults to the checkout containing this script)",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="prove the guard rejects a weakened config before verifying the real tree",
    )
    arguments = parser.parse_args()

    if arguments.self_test:
        result = self_test()
        if result != 0:
            return result

    problems = check(arguments.root.resolve())
    if problems:
        print("standards-guard: config contracts are broken", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print("standards-guard: all config contracts hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
