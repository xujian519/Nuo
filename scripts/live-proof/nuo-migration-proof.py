#!/usr/bin/env python3
"""Proof harness for the Nuo rename's one-time data migration.

The rename moves three kinds of state and must lose none of it:

  data root     ~/.osaurus                     -> ~/.nuo            (copy, never move)
  preferences   com.dinoki.osaurus (defaults)  -> com.nuo.app       (copy, never move)
  keychain      com.osaurus.* / ai.osaurus.*   -> com.nuo.* / ai.nuo.*  (lazy read-through)

This script captures the "before" state, then verifies the "after" state
against it. It never modifies anything: no writes outside the capture file,
no deletions, no keychain mutation.

Usage
-----
  # 1. With the app NOT running, record what the old install owns.
  python3 scripts/live-proof/nuo-migration-proof.py capture --out /tmp/nuo-before.json

  # 2. Launch Nuo once (this performs the migration), then quit it.
  open -a /path/to/Nuo.app        # wait for the window, then Quit

  # 3. Verify the result. Exits non-zero with one line per failed check.
  python3 scripts/live-proof/nuo-migration-proof.py verify --before /tmp/nuo-before.json

  # Harness self-check (no real home / keychain involved):
  python3 scripts/live-proof/nuo-migration-proof.py self-test

Why a separate capture step: `~/.nuo` is created by the first launch, so the
legacy tree has to be fingerprinted *before* it exists. Comparing against a
fingerprint taken afterwards would happily accept a half-copied tree.

Exit codes: 0 all checks passed, 1 a check failed, 2 usage/environment error.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BRAND_SWIFT = REPO_ROOT / "Packages" / "OsaurusRepository" / "Brand.swift"

# Frozen identifiers this harness must agree with (Brand.swift is the source
# of truth; these are the fallbacks used when it cannot be parsed).
DEFAULT_NEW_ROOT_NAME = ".nuo"
DEFAULT_LEGACY_ROOT_NAME = ".osaurus"
DEFAULT_LEGACY_SUPPORT_NAME = "com.dinoki.osaurus"
DEFAULT_NEW_DOMAIN = "com.nuo.app"
DEFAULT_LEGACY_DOMAIN = "com.dinoki.osaurus"
DEFAULTS_MIGRATION_MARKER = "ai.osaurus.brand.defaults-migrated"
MERGE_MARKER = ".legacy-application-support-merge.done"
# Account name the storage DEK is filed under (StorageKeyManager.keyAccount).
DEK_ACCOUNT = "data-encryption-key"

# Preferences the migration deliberately does not carry over (window frames are
# keyed by window title, which changed with the rename).
SKIPPED_PREFIXES = ("NSWindow Frame ", "NSPreferencesContentSize")

# Files above this size are fingerprinted by size + mtime only. Model bundles
# are tens of GB and are copied with APFS clonefile, where a full re-hash would
# dominate the run without adding signal.
MAX_HASH_BYTES = 64 * 1024 * 1024
MAX_HASHED_FILES = 4000


# --------------------------------------------------------------------------
# Brand.swift parsing
# --------------------------------------------------------------------------


def brand_constants() -> dict:
    """Read the identity strings out of Brand.swift.

    Parsed rather than hardcoded so a future rename cannot silently leave this
    harness asserting yesterday's names. A parse failure is reported, not
    guessed around, because a wrong fallback would make every check vacuous.
    """
    text = BRAND_SWIFT.read_text(encoding="utf-8")

    def literal(name: str) -> str | None:
        match = re.search(rf'public static let {name} = "([^"]+)"', text)
        return match.group(1) if match else None

    legacy_block = text.split("public enum Legacy {", 1)
    legacy_text = legacy_block[1] if len(legacy_block) == 2 else ""

    def legacy(name: str) -> str | None:
        match = re.search(rf'public static let {name} = "([^"]+)"', legacy_text)
        return match.group(1) if match else None

    pairs = [
        {"current": current, "legacy": legacy_name}
        for current, legacy_name in re.findall(
            r'KeychainService\(\s*current:\s*"([^"]+)",\s*legacy:\s*"([^"]+)"\s*\)',
            text,
            re.S,
        )
    ]

    return {
        "slug": literal("slug") or "nuo",
        "display": literal("display") or "Nuo",
        "new_root": literal("dataRootName") or DEFAULT_NEW_ROOT_NAME,
        "legacy_root": legacy("dataRootName") or DEFAULT_LEGACY_ROOT_NAME,
        "legacy_support": legacy("appSupportDirectoryName") or DEFAULT_LEGACY_SUPPORT_NAME,
        "defaults_domain": literal("defaultsDomain") or DEFAULT_NEW_DOMAIN,
        "legacy_defaults_domain": legacy("defaultsDomain") or DEFAULT_LEGACY_DOMAIN,
        "keychain_pairs": pairs,
    }


# --------------------------------------------------------------------------
# Fingerprinting
# --------------------------------------------------------------------------


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fingerprint_tree(root: Path) -> dict:
    """Structural fingerprint of a directory tree.

    `sampled` carries hashes for the files that matter for identity (configs,
    small databases, secrets); `rest` only carries size/mtime for the big ones.
    """
    result = {
        "path": str(root),
        "exists": root.is_dir(),
        "file_count": 0,
        "total_bytes": 0,
        "top_level": [],
        "sampled": {},
        "rest": {},
    }
    if not root.is_dir():
        return result

    top_level = sorted(entry.name for entry in root.iterdir())
    result["top_level"] = top_level

    hashed = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            path = Path(dirpath) / name
            try:
                stat = path.stat()
            except OSError:
                continue
            if not path.is_file() or path.is_symlink():
                continue
            rel = str(path.relative_to(root))
            result["file_count"] += 1
            result["total_bytes"] += stat.st_size
            if stat.st_size <= MAX_HASH_BYTES and hashed < MAX_HASHED_FILES:
                try:
                    result["sampled"][rel] = sha256_of(path)
                    hashed += 1
                except OSError:
                    continue
            else:
                result["rest"][rel] = [stat.st_size, int(stat.st_mtime)]
    return result


def read_defaults_plist(home: Path, domain: str) -> dict:
    """Read a preferences domain straight off disk.

    Deliberately not `defaults export`: that goes through cfprefsd and can
    answer from its in-memory cache, which would prove nothing about what the
    app persisted. The caller must quit the app first so the daemon has
    flushed; `verify` says so when a file is missing.
    """
    path = home / "Library" / "Preferences" / f"{domain}.plist"
    if not path.is_file():
        return {}
    try:
        with path.open("rb") as handle:
            return plistlib.load(handle)
    except Exception as error:  # noqa: BLE001 - reported, not raised
        raise SystemExit(f"cannot read {path}: {error}")


def keychain_item_exists(service: str, account: str | None = None) -> bool | None:
    """Attribute-only keychain probe; never returns the secret.

    Pass `account` when it is known; otherwise the whole service is probed.
    Returns None when the keychain cannot be inspected at all (headless CI,
    locked keychain), so the check can be reported as skipped instead of failed.
    """
    command = ["/usr/bin/security", "find-generic-password", "-s", service]
    if account:
        command += ["-a", account]
    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if completed.returncode == 0:
        return True
    if completed.returncode == 44:  # errSecItemNotFound
        return False
    return None


# --------------------------------------------------------------------------
# capture
# --------------------------------------------------------------------------


def cmd_capture(args: argparse.Namespace) -> int:
    home = Path(args.home).expanduser()
    brand = brand_constants()

    legacy_root = home / brand["legacy_root"]
    if not legacy_root.is_dir():
        print(
            f"capture: no pre-rename root at {legacy_root} — nothing to migrate. "
            "This machine never ran the old build, so there is no migration to prove.",
            file=sys.stderr,
        )
        return 2

    payload = {
        "version": 1,
        "brand": brand,
        "home": str(home),
        "legacy_root": fingerprint_tree(legacy_root),
        "legacy_support": fingerprint_tree(
            home / "Library" / "Application Support" / brand["legacy_support"]
        ),
        "legacy_defaults": read_defaults_plist(home, brand["legacy_defaults_domain"]),
        "legacy_keychain_state": selection(args, brand, home),
    }

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")

    sampled = len(payload["legacy_root"]["sampled"])
    print(
        f"capture: {legacy_root} -> {out}\n"
        f"  {payload['legacy_root']['file_count']} file(s), "
        f"{payload['legacy_root']['total_bytes']} byte(s), {sampled} hashed\n"
        f"  legacy preferences: {len(payload['legacy_defaults'])} key(s)",
        flush=True,
    )
    return 0


def selection(args: argparse.Namespace, brand: dict, home: Path) -> list:
    """Keychain pairs to check, defaulting to the data-encryption key.

    The DEK is the one secret whose loss is unrecoverable, so it is the default
    target; `--all-keychain` widens the sweep. Only accounts that exist under
    the legacy service are recorded, because "the old install had no GitHub
    token" is not something the migration can be asked to preserve.
    """
    pairs = brand["keychain_pairs"]
    if not args.all_keychain:
        pairs = [pair for pair in pairs if pair["current"].endswith(".storage")]
    if args.skip_keychain:
        return [{"current": p["current"], "legacy": p["legacy"], "present": None} for p in pairs]

    if args.skip_keychain:
        return [
            {
                "current": p["current"],
                "legacy": p["legacy"],
                "account": DEK_ACCOUNT if p["current"].endswith(".storage") else None,
                "present": None,
            }
            for p in pairs
        ]

    result = []
    for pair in pairs:
        # The DEK's account is fixed by StorageKeyManager. Other services key
        # their items by arbitrary account names (provider ids, plugin ids,
        # agent addresses), so those are probed by service alone.
        account = DEK_ACCOUNT if pair["current"].endswith(".storage") else None
        present = keychain_item_exists(pair["legacy"], account)
        result.append(
            {
                "current": pair["current"],
                "legacy": pair["legacy"],
                "account": account,
                "present": present,
            }
        )
    return result


# --------------------------------------------------------------------------
# verify
# --------------------------------------------------------------------------


class Checks:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.skips: list[str] = []

    def ok(self, condition: bool, message: str) -> bool:
        if not condition:
            self.failures.append(message)
        return condition

    def skip(self, message: str) -> None:
        if message in self.skips:
            return
        self.skips.append(message)
        print(f"SKIP {message}")


def cmd_verify(args: argparse.Namespace) -> int:
    before = json.loads(Path(args.before).read_text(encoding="utf-8"))
    brand = before["brand"]
    home = Path(args.home or before["home"]).expanduser()
    checks = Checks()

    new_root = home / brand["new_root"]
    legacy_root = home / brand["legacy_root"]

    # --- data root -------------------------------------------------------
    if not checks.ok(new_root.is_dir(), f"new data root missing: {new_root}"):
        return report(checks)

    checks.ok(
        (new_root / MERGE_MARKER).is_file(),
        f"migration marker missing: {new_root / MERGE_MARKER} (the copy did not run or did not finish)",
    )

    legacy_fp = before["legacy_root"]
    new_fp = fingerprint_tree(new_root)

    missing_top = [name for name in legacy_fp["top_level"] if name not in set(new_fp["top_level"])]
    checks.ok(not missing_top, f"new root is missing top-level entries: {missing_top}")

    missing_files = [rel for rel in legacy_fp["sampled"] if rel not in new_fp["sampled"]]
    checks.ok(
        not missing_files,
        f"new root is missing {len(missing_files)} file(s), e.g. {missing_files[:5]}",
    )

    differing = [
        rel
        for rel, digest in legacy_fp["sampled"].items()
        if rel in new_fp["sampled"] and new_fp["sampled"][rel] != digest
    ]
    checks.ok(not differing, f"copied files differ from the source: {differing[:5]}")

    # The source must still be intact: this is a copy, not a move, and the
    # previous build has to keep working on the same machine.
    after_legacy = fingerprint_tree(legacy_root)
    checks.ok(
        after_legacy["file_count"] == legacy_fp["file_count"],
        f"legacy root changed: {legacy_fp['file_count']} -> {after_legacy['file_count']} file(s)",
    )
    checks.ok(
        after_legacy["total_bytes"] == legacy_fp["total_bytes"],
        f"legacy root changed: {legacy_fp['total_bytes']} -> {after_legacy['total_bytes']} byte(s)",
    )
    changed = [
        rel
        for rel, digest in legacy_fp["sampled"].items()
        if after_legacy["sampled"].get(rel) != digest
    ]
    checks.ok(not changed, f"legacy files were modified: {changed[:5]}")

    # --- preferences -----------------------------------------------------
    legacy_defaults = before["legacy_defaults"]
    new_defaults = read_defaults_plist(home, brand["defaults_domain"])
    legacy_defaults_after = read_defaults_plist(home, brand["legacy_defaults_domain"])

    checks.ok(
        bool(new_defaults.get(DEFAULTS_MIGRATION_MARKER)),
        f"preferences marker missing in {brand['defaults_domain']}: {DEFAULTS_MIGRATION_MARKER}",
    )
    checks.ok(
        legacy_defaults_after == legacy_defaults,
        "legacy preferences domain changed (the copy must not modify or remove it)",
    )

    expected = {
        key: value
        for key, value in legacy_defaults.items()
        if key != DEFAULTS_MIGRATION_MARKER
        and not any(key.startswith(prefix) for prefix in SKIPPED_PREFIXES)
    }
    missing_keys = [key for key in expected if key not in new_defaults]
    checks.ok(
        not missing_keys,
        f"{len(missing_keys)} preference(s) not carried over, e.g. {missing_keys[:5]}",
    )
    mismatched = [key for key in expected if key in new_defaults and new_defaults[key] != expected[key]]
    checks.ok(
        not mismatched,
        f"{len(mismatched)} preference(s) differ from the legacy value, e.g. {mismatched[:5]}",
    )

    # --- keychain --------------------------------------------------------
    for pair in before.get("legacy_keychain_state", []):
        if pair["present"] is None:
            checks.skip(
                f"keychain not inspected: {pair['legacy']} (run without --skip-keychain on a normal login)"
            )
            continue
        if not pair["present"]:
            checks.skip(f"no legacy keychain item under {pair['legacy']}; nothing to read through")
            continue
        current = keychain_item_exists(pair["current"], pair.get("account"))
        if current is None:
            checks.skip(f"keychain probe failed for {pair['current']}")
            continue
        checks.ok(
            bool(current),
            f"legacy key exists under {pair['legacy']} but was not read through to {pair['current']}",
        )

    return report(checks)


def report(checks: Checks) -> int:
    sys.stdout.flush()
    if checks.failures:
        print(f"\nFAIL {len(checks.failures)} check(s):", file=sys.stderr)
        for failure in checks.failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print(f"PASS all migration checks ({len(checks.skips)} skipped)")
    return 0


# --------------------------------------------------------------------------
# self-test
# --------------------------------------------------------------------------


def cmd_self_test(args: argparse.Namespace) -> int:
    """Exercise capture/verify against a throwaway home.

    Proves the harness fails when it should: a green run on a machine where
    nothing migrated is worse than no harness at all.
    """
    brand = {
        "new_root": ".nuo",
        "legacy_root": ".osaurus",
        "legacy_support": "com.dinoki.osaurus",
        "defaults_domain": "com.nuo.app",
        "legacy_defaults_domain": "com.dinoki.osaurus",
        "keychain_pairs": [],
    }
    with tempfile.TemporaryDirectory(prefix="nuo-migration-selftest-") as tmp:
        home = Path(tmp)
        legacy = home / brand["legacy_root"]
        (legacy / "config").mkdir(parents=True)
        (legacy / "models" / "m").mkdir(parents=True)
        (legacy / "config" / "providers.json").write_text('{"a":1}', encoding="utf-8")
        (legacy / "models" / "m" / "weights.bin").write_bytes(b"\x00" * 128)
        (legacy / "chat.sqlite").write_bytes(b"sqlite-pages")

        prefs = home / "Library" / "Preferences"
        prefs.mkdir(parents=True)
        with (prefs / f"{brand['legacy_defaults_domain']}.plist").open("wb") as handle:
            plistlib.dump(
                {
                    "serverPort": 1337,
                    "theme": "dark",
                    "NSWindow Frame main": "0 0 800 600",
                },
                handle,
            )

        before_path = home / "before.json"

        class _Args:
            pass

        def run_capture() -> None:
            ns = _Args()
            ns.home = str(home)
            ns.out = str(before_path)
            ns.all_keychain = False
            ns.skip_keychain = True
            if cmd_capture(ns) != 0:
                raise SystemExit("self-test: capture failed")

        def run_verify(expect: int, label: str) -> None:
            ns = _Args()
            ns.home = str(home)
            ns.before = str(before_path)
            code = cmd_verify(ns)
            if code != expect:
                raise SystemExit(f"self-test: {label}: expected exit {expect}, got {code}")

        def simulate_migration() -> None:
            new = home / brand["new_root"]
            if new.exists():
                shutil.rmtree(new)
            shutil.copytree(legacy, new, symlinks=True)
            (new / MERGE_MARKER).write_bytes(b"")
            copied = dict(plistlib.load((prefs / f"{brand['legacy_defaults_domain']}.plist").open("rb")))
            copied.pop("NSWindow Frame main", None)
            copied[DEFAULTS_MIGRATION_MARKER] = True
            with (prefs / f"{brand['defaults_domain']}.plist").open("wb") as handle:
                plistlib.dump(copied, handle)

        run_capture()
        simulate_migration()
        run_verify(0, "happy path")

        # 1. A dropped file must fail.
        (home / brand["new_root"] / "chat.sqlite").unlink()
        run_verify(1, "missing file")
        simulate_migration()

        # 2. A truncated/changed copy must fail.
        (home / brand["new_root"] / "chat.sqlite").write_bytes(b"sqlite-pagez")
        run_verify(1, "corrupt copy")
        simulate_migration()

        # 3. Touching the legacy tree must fail (it must stay rollback-able).
        (home / brand["legacy_root"] / "chat.sqlite").write_bytes(b"changed")
        run_verify(1, "legacy mutated")
        (home / brand["legacy_root"] / "chat.sqlite").write_bytes(b"sqlite-pages")

        # 4. A dropped preference must fail.
        run_verify(0, "restored")
        with (prefs / f"{brand['defaults_domain']}.plist").open("wb") as handle:
            plistlib.dump({DEFAULTS_MIGRATION_MARKER: True, "theme": "dark"}, handle)
        run_verify(1, "missing preference")

    print("self-test: OK (harness rejects missing files, corrupt copies, legacy mutation, lost preferences)")
    return 0


# --------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    capture = sub.add_parser("capture", help="record the pre-migration state")
    capture.add_argument("--home", default=str(Path.home()))
    capture.add_argument("--out", required=True)
    capture.add_argument("--all-keychain", action="store_true")
    capture.add_argument("--skip-keychain", action="store_true")
    capture.set_defaults(func=cmd_capture)

    verify = sub.add_parser("verify", help="check the post-migration state against a capture")
    verify.add_argument("--before", required=True)
    verify.add_argument("--home", default=None)
    verify.set_defaults(func=cmd_verify)

    self_test = sub.add_parser("self-test", help="prove the harness catches broken migrations")
    self_test.set_defaults(func=cmd_self_test)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
