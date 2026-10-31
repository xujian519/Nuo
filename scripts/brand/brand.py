#!/usr/bin/env python3
"""nuo brand layer.

This repository is a fork that keeps merging from upstream, so the rebrand is not a
one-shot `sed`. It is a *replayable* layer:

    scripts/brand/brand.json      single source of truth for every name we change
    scripts/brand/rules/*.json    declarative, idempotent rewrites, grouped by phase
    scripts/brand/apply.sh        replay every rule (run after each upstream merge)
    scripts/brand/verify.sh       guard: no regression, no contract drift
    scripts/brand/baseline.json   ratchet snapshot of remaining legacy occurrences

Commands
    apply     apply (or --dry-run) every rule whose phase <= --phase
    verify    fail on rule regressions, ratchet regressions, contract drift
    snapshot  rewrite baseline.json from the current tree
    inventory human-readable census of remaining legacy brand occurrences
    status    short summary of the above

Design constraints (see docs/brand/NUO-REBRAND-PLAN.md):

* Idempotent. Applying twice is a no-op. Rules state a post-condition of "0 matches",
  never a before-count, so a merge that reintroduces a line is simply re-fixed.
* Frozen identifiers are enumerated in brand.json -> frozen.literals and are spliced
  out before any text rule runs, so a broad "Osaurus" rule can never touch
  `OsaurusCore`, `ai.osaurus.`, `X-Osaurus-*`, `osaurus_plugin_entry`, ...
* Rules are opt-in per phase via `enforced`. A phase flips its rules to true when the
  change actually lands, so CI never fails on work that has not started.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRAND_DIR = Path(__file__).resolve().parent
RULES_DIR = BRAND_DIR / "rules"
BASELINE_PATH = BRAND_DIR / "baseline.json"

LEGACY_RE = r"(?i)osaurus"


# --------------------------------------------------------------------------- utils


def die(msg: str, code: int = 2) -> "NoReturn":  # noqa: F821
    print(f"brand: {msg}", file=sys.stderr)
    raise SystemExit(code)


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        die(f"missing {path.relative_to(ROOT)}")
    except json.JSONDecodeError as exc:
        die(f"invalid JSON in {path.relative_to(ROOT)}: {exc}")


CONFIG = load_json(BRAND_DIR / "brand.json")


def placeholders() -> dict[str, str]:
    b, l = CONFIG["brand"], CONFIG["legacy"]
    table = {}
    for key, value in b.items():
        table[key] = ",".join(value) if isinstance(value, list) else str(value)
        table[f"brand_{key}"] = table[key]
    for key, value in l.items():
        table[key] = ",".join(value) if isinstance(value, list) else str(value)
        table[f"legacy_{key}"] = table[key]
    return table


PLACEHOLDERS = placeholders()
PLACEHOLDER_RE = re.compile(r"\{([a-z_]+)\}")


def fmt(text: str) -> str:
    """Substitute {display}/{slug}/... so rules never hard-code a name twice."""

    def sub(match: re.Match) -> str:
        key = match.group(1)
        if key not in PLACEHOLDERS:
            die(f"unknown placeholder {{{key}}} in {text!r}")
        return PLACEHOLDERS[key]

    return PLACEHOLDER_RE.sub(sub, text)


def lit(rule: dict, key: str) -> str:
    """Rule text, optionally exempt from placeholder substitution.

    Shell rules are full of `${var}`/`${arr[@]}`; a rule that anchors on shell
    source sets `"raw": true` so those braces stay literal.
    """
    return rule[key] if rule.get("raw") else fmt(rule[key])


def glob_to_regex(pattern: str) -> re.Pattern:
    out = ["^"]
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if c == "*":
            if pattern[i : i + 2] == "**":
                out.append(".*")
                i += 2
                if pattern[i : i + 1] == "/":
                    i += 1
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    out.append("$")
    return re.compile("".join(out))


EXCLUDE_RES = [glob_to_regex(p) for p in CONFIG["paths"]["exclude"]]
STRICT_RES = [glob_to_regex(p) for p in CONFIG["paths"]["strict"]]
PENDING_RES = [glob_to_regex(p) for p in CONFIG["paths"].get("strict_pending", [])]


def all_files() -> list[str]:
    """Tracked + untracked-not-ignored files, as repo-relative posix paths."""
    out = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        capture_output=True,
        check=True,
    ).stdout
    return [p for p in out.decode("utf-8").split("\0") if p]


_FILE_CACHE: list[str] | None = None


def repo_files() -> list[str]:
    global _FILE_CACHE
    if _FILE_CACHE is None:
        _FILE_CACHE = all_files()
    return _FILE_CACHE


def is_excluded(path: str) -> bool:
    return any(rx.match(path) for rx in EXCLUDE_RES)


def matches_any(path: str, regexes: list[re.Pattern]) -> bool:
    return any(rx.match(path) for rx in regexes)


def select(globs: list[str] | None) -> list[str]:
    if not globs:
        return [p for p in repo_files() if not is_excluded(p)]
    regexes = [glob_to_regex(g) for g in globs]
    return [p for p in repo_files() if matches_any(p, regexes) and not is_excluded(p)]


def read_text(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def write_text(rel: str, text: str) -> None:
    (ROOT / rel).write_text(text, encoding="utf-8")


# --------------------------------------------------------------- frozen protection


PROTECTED = sorted(CONFIG["frozen"]["literals"], key=len, reverse=True)


def split_protected(text: str) -> list[tuple[bool, str]]:
    """Split into (protected?, chunk) so text rules can only touch unlocked spans."""
    if not PROTECTED:
        return [(False, text)]
    spans: list[tuple[int, int]] = []
    for literal in PROTECTED:
        start = 0
        while True:
            hit = text.find(literal, start)
            if hit < 0:
                break
            spans.append((hit, hit + len(literal)))
            start = hit + 1
    if not spans:
        return [(False, text)]
    spans.sort()
    merged: list[tuple[int, int]] = []
    for start, end in spans:
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    chunks: list[tuple[bool, str]] = []
    pos = 0
    for start, end in merged:
        if pos < start:
            chunks.append((False, text[pos:start]))
        chunks.append((True, text[start:end]))
        pos = end
    if pos < len(text):
        chunks.append((False, text[pos:]))
    return chunks


def substitute(text: str, regex: re.Pattern, replacement: str) -> tuple[str, int]:
    total = 0
    pieces: list[str] = []
    for protected, chunk in split_protected(text):
        if protected:
            pieces.append(chunk)
            continue
        new, count = regex.subn(replacement, chunk)
        if new == chunk:
            count = 0
        total += count
        pieces.append(new)
    return "".join(pieces), total


# ------------------------------------------------------------- swift literal scan


def swift_literal_spans(text: str) -> list[tuple[int, int]]:
    """Byte offsets of string-literal *bodies* in a Swift source file.

    Used by rules with mode=swift-literals so UI copy changes never touch code
    identifiers, comments, or `import OsaurusCore`.
    """
    spans: list[tuple[int, int]] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and text.startswith("//", i):
            nl = text.find("\n", i)
            i = n if nl < 0 else nl + 1
            continue
        if c == "/" and text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        if c == '"':
            triple = text.startswith('"""', i)
            delim_len = 3 if triple else 1
            start = i + delim_len
            j = start
            while j < n:
                ch = text[j]
                if ch == "\\":
                    j += 2
                    continue
                if triple:
                    if text.startswith('"""', j):
                        break
                else:
                    if ch == '"' or ch == "\n":
                        break
                j += 1
            spans.append((start, min(j, n)))
            i = j + delim_len
            continue
        i += 1
    return spans


def substitute_in_literals(text: str, regex: re.Pattern, replacement: str) -> tuple[str, int]:
    spans = swift_literal_spans(text)
    if not spans:
        return text, 0
    total = 0
    for start, end in reversed(spans):
        body = text[start:end]
        new, count = substitute(body, regex, replacement)
        if count:
            text = text[:start] + new + text[end:]
            total += count
    return text, total


# ------------------------------------------------------------------------- rules


def load_rules(max_phase: int | None = None) -> list[dict]:
    rules: list[dict] = []
    for path in sorted(RULES_DIR.glob("*.json")):
        doc = load_json(path)
        phase = doc.get("phase", 0)
        if max_phase is not None and phase > max_phase:
            continue
        for rule in doc.get("rules", []):
            rule.setdefault("phase", phase)
            rule["_source"] = path.name
            rules.append(rule)
    # Anchored multi-line edits ("block") run before regex rewrites so a block rule
    # can anchor on the text as it exists today, before narrower replacements chip at it.
    rules.sort(key=lambda r: 0 if r["op"] == "block" else 1)
    return rules


def rule_files(rule: dict) -> list[str]:
    explicit = rule.get("files")
    files = select(explicit)
    if "path" in rule:
        target = rule["path"]
        files = [target] if not is_excluded(target) else []
    only = rule.get("only_existing", True)
    if only:
        files = [f for f in files if (ROOT / f).exists()]
    return files


def count_rule(rule: dict, dry: bool) -> tuple[int, list[str]]:
    """Return (matches, files-touched) without writing."""
    op = rule["op"]
    if op in {"pbx-setting", "insert-after", "block"}:
        return _apply_single(rule, dry)
    if op != "replace":
        die(f"unknown op {op!r} in rule {rule['id']}")
    regex = re.compile(lit(rule, "pattern"), re.MULTILINE)
    total = 0
    touched: list[str] = []
    for rel in rule_files(rule):
        text = read_text(rel)
        if rule.get("mode") == "swift-literals":
            new, count = substitute_in_literals(text, regex, lit(rule, "replace"))
        else:
            new, count = substitute(text, regex, lit(rule, "replace"))
        if count:
            total += count
            touched.append(f"{rel} ({count})")
            if not dry:
                write_text(rel, new)
    return total, touched


def _apply_single(rule: dict, dry: bool) -> tuple[int, list[str]]:
    op = rule["op"]
    rel = rule["path"]
    if not (ROOT / rel).exists():
        die(f"{rule['id']}: missing {rel}")
    if op == "pbx-setting":
        return _pbx_setting(rule, rel, dry)
    if op == "insert-after":
        return _insert_after(rule, rel, dry)
    if op == "block":
        return _block(rule, rel, dry)
    die(f"unknown op {op!r}")


def _pbx_blocks(text: str):
    for match in re.finditer(r"buildSettings = \{", text):
        i = match.end()
        depth = 1
        while i < len(text) and depth:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
            i += 1
        yield match.end(), i - 1


def _pbx_setting(rule: dict, rel: str, dry: bool) -> tuple[int, list[str]]:
    text = read_text(rel)
    setting = rule["setting"]
    wanted = None if rule.get("remove") else fmt(str(rule["value"]))
    scope = rule.get("scope", {})
    scoped_ids = scope.get("bundle_id")

    line_re = re.compile(rf"(?m)^([ \t]*){re.escape(setting)}[ \t]*=[ \t]*[^;\n]*;[ \t]*\n")
    edits: list[tuple[int, int, str]] = []
    for start, end in _pbx_blocks(text):
        block = text[start:end]
        if scoped_ids:
            if not any(f"PRODUCT_BUNDLE_IDENTIFIER = {bid};" in block for bid in scoped_ids):
                continue
        for match in line_re.finditer(text, start, end):
            indent = match.group(1)
            if rule.get("remove"):
                edits.append((match.start(), match.end(), ""))
                continue
            desired = f"{indent}{setting} = {wanted};"
            if match.group(0).rstrip("\n").rstrip() == desired:
                continue
            edits.append((match.start(), match.end(), desired + "\n"))

    if not edits:
        return 0, []
    for start, end, replacement in reversed(edits):
        text = text[:start] + replacement + text[end:]
    if not dry:
        write_text(rel, text)
    return len(edits), [f"{rel} ({len(edits)})"]


def _insert_after(rule: dict, rel: str, dry: bool) -> tuple[int, list[str]]:
    """Insert an exact literal right after an anchor literal.

    Textual on purpose: `plutil -replace` rewrites the whole plist in sorted key
    order, which turns every later upstream merge into a conflict on a file we
    barely change.
    """
    text = read_text(rel)
    find = lit(rule, "find")
    insert = lit(rule, "insert")
    if insert in text:
        return 0, []
    if find not in text:
        die(f"{rule['id']}: anchor not found in {rel}", code=3)
    if dry:
        return 1, [f"{rel} (insert after {find.strip()})"]
    write_text(rel, text.replace(find, find + insert, 1))
    return 1, [f"{rel} (insert after {find.strip()})"]


def _block(rule: dict, rel: str, dry: bool) -> tuple[int, list[str]]:
    """Anchored multi-line replacement, for edits a regex would make unreadable.

    Idempotent: if `find` is gone and `replace` is present, nothing to do. If neither
    is present the upstream merge changed the code under us -> hard conflict.
    """
    text = read_text(rel)
    find = lit(rule, "find")
    # Fork-owned files live in templates/ so the real content is editable and
    # diffable as a file instead of a JSON string.
    replace = read_text(rule["template"]) if rule.get("template") else lit(rule, "replace")
    if find not in text:
        if replace in text:
            return 0, []
        die(
            f"{rule['id']}: anchor not found in {rel} (upstream changed it?).\n"
            f"--- expected anchor ---\n{find}\n",
            code=3,
        )
    if dry:
        return 1, [f"{rel} (block)"]
    write_text(rel, text.replace(find, replace, 1))
    return 1, [f"{rel} (block)"]


# -------------------------------------------------------------------- commands


def cmd_apply(args) -> int:
    rules = load_rules(args.phase)
    total = 0
    changed: list[str] = []
    for rule in rules:
        if rule.get("enforced") is False and args.only_enforced:
            continue
        matches, files = count_rule(rule, dry=args.dry_run)
        if matches:
            total += matches
            changed.extend(files)
            print(f"  {'would apply' if args.dry_run else 'applied'} {rule['id']}: {matches}")
    if args.dry_run:
        print(f"brand: dry-run, {total} change(s) across {len(changed)} file(s)")
    else:
        print(f"brand: applied {total} change(s) across {len(changed)} file(s)")
    return 0


def contextual_count(rel: str, text: str) -> int:
    """Occurrences of the legacy brand that a user could plausibly see.

    For Swift we only count inside string literals: `import OsaurusCore` and
    `OsaurusPaths.root()` are code, not brand surface, and will never be renamed.
    """
    if rel.endswith(".swift"):
        spans = swift_literal_spans(text)
        if not spans:
            return 0
        return sum(len(re.findall(LEGACY_RE, text[s:e])) for s, e in spans)
    # Strip frozen literals before counting so contracts do not inflate the number.
    stripped = text
    for literal in PROTECTED:
        stripped = stripped.replace(literal, "\0")
    return len(re.findall(LEGACY_RE, stripped))


def strict_files() -> list[str]:
    return [p for p in repo_files() if matches_any(p, STRICT_RES) and not is_excluded(p)]


def cmd_snapshot(args) -> int:
    counts: dict[str, int] = {}
    for rel in strict_files():
        try:
            text = read_text(rel)
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        n = contextual_count(rel, text)
        if n:
            counts[rel] = n
    contracts = {}
    for item in CONFIG["frozen"]["contracts"]:
        literal = item["literal"]
        seen = 0
        for rel in repo_files():
            if rel.endswith((".png", ".jpg", ".tiff", ".pdf", ".zip", ".xcresult")):
                continue
            try:
                seen += read_text(rel).count(literal)
            except (UnicodeDecodeError, IsADirectoryError):
                continue
        contracts[literal] = seen

    baseline = {
        "version": CONFIG["version"],
        "commit": subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"], capture_output=True, text=True
        ).stdout.strip(),
        "strict": counts,
        "contracts": contracts,
    }
    print(f"brand: {len(counts)} strict file(s) still carry legacy brand, "
          f"{sum(counts.values())} occurrence(s)")
    if args.write:
        BASELINE_PATH.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"brand: wrote {BASELINE_PATH.relative_to(ROOT)}")
    return 0


def cmd_verify(args) -> int:
    failures: list[str] = []
    warnings: list[str] = []

    baseline = {}
    if BASELINE_PATH.exists():
        baseline = load_json(BASELINE_PATH)
    else:
        warnings.append("no baseline.json — run `scripts/brand/apply.sh --snapshot`")

    # 1. Enforced rules must be fully absorbed.
    for rule in load_rules(args.phase):
        if not rule.get("enforced"):
            continue
        matches, files = count_rule(rule, dry=True)
        if matches:
            failures.append(f"rule {rule['id']} still matches {matches}x: {', '.join(files[:3])}")

    # 2. Ratchet: strict paths may not gain new legacy brand.
    current: dict[str, int] = {}
    for rel in strict_files():
        try:
            text = read_text(rel)
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        n = contextual_count(rel, text)
        if n:
            current[rel] = n
    allowed = baseline.get("strict", {})
    for rel, n in sorted(current.items()):
        cap = allowed.get(rel, 0)
        if n > cap:
            failures.append(f"{rel}: {n} legacy occurrence(s) > baseline {cap}")

    # 3. Frozen contracts must still be present (a merge must not silently drop them).
    for item in CONFIG["frozen"]["contracts"]:
        literal = item["literal"]
        floor = item.get("min", 1)
        seen = baseline.get("contracts", {}).get(literal)
        if seen is None:
            continue
        if seen < floor:
            failures.append(f"contract {literal!r}: {seen} < {floor}")
        current_seen = 0
        for rel in repo_files():
            if rel.endswith((".png", ".jpg", ".tiff", ".pdf", ".zip")):
                continue
            try:
                current_seen += read_text(rel).count(literal)
            except (UnicodeDecodeError, IsADirectoryError):
                continue
        if current_seen < floor:
            failures.append(f"contract {literal!r} disappeared ({current_seen} < {floor})")

    for warning in warnings:
        print(f"brand-guard: warn: {warning}")
    if failures:
        print(f"brand-guard: FAIL ({len(failures)} issue(s))")
        for failure in failures:
            print(f"  - {failure}")
        print("brand-guard: run `scripts/brand/apply.sh` to replay the rules, or fix the code.")
        return 1
    print(f"brand-guard: OK ({len(current)} strict file(s) at or below baseline)")
    return 0


def cmd_inventory(args) -> int:
    buckets: dict[str, list[int]] = {}
    for rel in repo_files():
        if rel.endswith((".png", ".jpg", ".jpeg", ".tiff", ".pdf", ".zip", ".xcresult")):
            continue
        try:
            text = read_text(rel)
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        n = contextual_count(rel, text)
        if not n:
            continue
        top = rel.split("/")[0] if "/" in rel else rel
        buckets.setdefault(top, [0, 0])
        buckets[top][0] += 1
        buckets[top][1] += n
    print(f"{'area':32} {'files':>6} {'occurrences':>12}")
    for area, (files, total) in sorted(buckets.items(), key=lambda kv: -kv[1][1]):
        print(f"{area:32} {files:6} {total:12}")
    print(f"{'TOTAL':32} {sum(v[0] for v in buckets.values()):6} "
          f"{sum(v[1] for v in buckets.values()):12}")
    return 0


def cmd_status(args) -> int:
    current = {}
    for rel in strict_files():
        try:
            n = contextual_count(rel, read_text(rel))
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        if n:
            current[rel] = n
    pending = 0
    pending_files = 0
    for rel in repo_files():
        if not matches_any(rel, PENDING_RES) or is_excluded(rel):
            continue
        try:
            n = contextual_count(rel, read_text(rel))
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        if n:
            pending_files += 1
            pending += n
    enforced = [r["id"] for r in load_rules(None) if r.get("enforced")]
    print(f"strict   : {len(current):4} file(s), {sum(current.values()):5} occurrence(s)")
    print(f"pending  : {pending_files:4} file(s), {pending:5} occurrence(s)  (各个阶段的下一批)")
    print(f"rules    : {len(load_rules(None)):4} total, {len(enforced)} enforced")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="brand", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    apply_p = sub.add_parser("apply", help="apply rules")
    apply_p.add_argument("--phase", type=int, default=None, help="only rules with phase <= N")
    apply_p.add_argument("--dry-run", action="store_true")
    apply_p.add_argument("--only-enforced", action="store_true")
    apply_p.set_defaults(func=cmd_apply)

    verify_p = sub.add_parser("verify", help="guard")
    verify_p.add_argument("--phase", type=int, default=None)
    verify_p.set_defaults(func=cmd_verify)

    snap_p = sub.add_parser("snapshot", help="rewrite baseline.json")
    snap_p.add_argument("--write", action="store_true")
    snap_p.set_defaults(func=cmd_snapshot)

    inv_p = sub.add_parser("inventory", help="census of remaining occurrences")
    inv_p.set_defaults(func=cmd_inventory)

    status_p = sub.add_parser("status", help="strict vs pending summary")
    status_p.set_defaults(func=cmd_status)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
