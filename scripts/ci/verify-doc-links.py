#!/usr/bin/env python3
"""Reject relative Markdown links that point at missing files.

Scope: every tracked Markdown file passed on the command line. External URLs,
anchors, absolute paths, and templated targets are out of scope; this gate only
proves that a relative file link resolves inside the checkout.

`--self-test` builds a known-good and a known-broken tree and asserts the gate
passes the first and rejects the second, so the gate itself cannot rot.
"""

from __future__ import annotations

import argparse
import re
import sys
import tempfile
import urllib.parse
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PATHS = ("docs", "README.md", "AGENTS.md")

EXTERNAL_PREFIXES = (
    "http://",
    "https://",
    "mailto:",
    "tel:",
    "data:",
    "file://",
    "app://",
)

# `[text](target)` and `![alt](target)`, with an optional title.
INLINE_LINK = re.compile(r"!?\[[^\]]*\]\(\s*([^)\s]+)(?:\s+[\"'][^\"']*[\"'])?\s*\)")
REFERENCE_LINK = re.compile(r"(?m)^\[[^\]]+\]:\s*(\S+)")


def _strip_code(text: str) -> str:
    """Blank out fenced blocks and inline code so examples are not links."""
    output: list[str] = []
    in_fence = False
    fence_marker = ""
    for line in text.splitlines(keepends=True):
        stripped = line.lstrip()
        if not in_fence and (stripped.startswith("```") or stripped.startswith("~~~")):
            in_fence = True
            fence_marker = stripped[:3]
            output.append("\n")
            continue
        if in_fence:
            if stripped.startswith(fence_marker):
                in_fence = False
            output.append("\n")
            continue
        output.append(re.sub(r"`[^`\n]+`", " ", line))
    return "".join(output)


def _iter_markdown(root: Path, paths: tuple[str, ...], problems: list[str]) -> list[Path]:
    files: list[Path] = []
    for relative in paths:
        path = root / relative
        if path.is_dir():
            files.extend(sorted(path.rglob("*.md")))
        elif path.is_file():
            files.append(path)
        else:
            problems.append(f"missing scan path {relative}")
    return files


def check(root: Path, paths: tuple[str, ...]) -> list[tuple[Path, int, str]]:
    problems: list[tuple[Path, int, str]] = []
    missing_targets: list[str] = []
    files = _iter_markdown(root, paths, missing_targets)
    problems.extend((root / path, 0, message) for message in missing_targets)

    for file in files:
        text = _strip_code(file.read_text(encoding="utf-8"))
        targets = [(match.start(), match.group(1)) for match in INLINE_LINK.finditer(text)]
        targets.extend((match.start(), match.group(1)) for match in REFERENCE_LINK.finditer(text))
        for offset, raw_target in sorted(targets):
            target = raw_target.strip()
            if not target or target.startswith("#"):
                continue
            lowered = target.lower()
            if lowered.startswith(EXTERNAL_PREFIXES):
                continue
            if target.startswith("/") or "<" in target or ">" in target:
                continue
            target = target.split("#", 1)[0].split("?", 1)[0]
            if not target:
                continue
            resolved = (file.parent / urllib.parse.unquote(target)).resolve()
            relative_target = resolved.relative_to(root.resolve()) if resolved.is_relative_to(root.resolve()) else resolved
            if not resolved.exists():
                line = text.count("\n", 0, offset) + 1
                problems.append((file, line, f"{relative_target} (from {raw_target})"))
    return problems


def self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="nuo-doc-links-") as directory:
        root = Path(directory)
        (root / "docs").mkdir()
        (root / "docs/target.md").write_text("# Target\n", encoding="utf-8")
        (root / "docs/good.md").write_text(
            "# Good\n\nSee [target](target.md) and [external](https://example.com).\n"
            "\n```\n[broken](missing.md)\n```\n",
            encoding="utf-8",
        )
        if check(root, ("docs",)):
            print("doc-link self-test: clean tree was rejected", file=sys.stderr)
            return 1

        (root / "docs/broken.md").write_text(
            "# Broken\n\nSee [missing](missing.md).\n", encoding="utf-8"
        )
        if not check(root, ("docs",)):
            print("doc-link self-test: broken link was not rejected", file=sys.stderr)
            return 1

    print("doc-link self-test: clean tree passed, broken link rejected")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=REPO_ROOT)
    parser.add_argument(
        "--paths",
        nargs="+",
        default=list(DEFAULT_PATHS),
        help="files or directories to scan, relative to --root",
    )
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    if arguments.self_test and self_test() != 0:
        return 1

    root = arguments.root.resolve()
    problems = check(root, tuple(arguments.paths))
    if problems:
        print(f"doc-links: {len(problems)} broken link(s)", file=sys.stderr)
        for file, line, message in problems:
            location = file.relative_to(root) if file.is_relative_to(root) else file
            print(f"  - {location}:{line}: {message}", file=sys.stderr)
        return 1

    print("doc-links: every relative Markdown link resolves")
    return 0


if __name__ == "__main__":
    sys.exit(main())
