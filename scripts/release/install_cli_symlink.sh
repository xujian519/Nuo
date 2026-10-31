#!/bin/bash
set -euo pipefail

# install_cli_symlink.sh
# Creates/updates a convenient `nuo` symlink to either:
#   1) the app's embedded CLI at Nuo.app/Contents/Helpers/nuo, or
#   2) a locally built CLI binary in DerivedData (dev mode).
#
# The legacy `osaurus` name is also installed as a symlink, but only when that
# path does not exist yet: an operator who already has `osaurus` on PATH keeps
# whatever they installed, and we never overwrite an unrelated file.
#
# Usage:
#   scripts/release/install_cli_symlink.sh [--dev] [--prefix <dir>] [<path-to-Nuo.app>]
#
# Notes:
# - When no path is provided, common install locations are checked (Nuo.app
#   first, then a legacy Osaurus.app from before the rename).
# - Default target is /usr/local/bin, falling back to ~/.local/bin. Homebrew's
#   prefix is never used automatically (see resolve_target_bin_dir below) —
#   use --prefix to target it explicitly if that's what you want.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

DEV_MODE=0
PREFIX_OVERRIDE=""
APP_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev)
      DEV_MODE=1
      shift
      ;;
    --prefix)
      PREFIX_OVERRIDE="${2:-}"
      if [[ -z "$PREFIX_OVERRIDE" ]]; then
        echo "--prefix requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      # Positional: optional path to .app
      APP_PATH="$1"
      shift
      ;;
  esac
done

resolve_cli_from_app() {
  local app_path="$1"
  local candidate
  for candidate in \
    "$app_path/Contents/Helpers/nuo" \
    "$app_path/Contents/Helpers/osaurus" \
    "$app_path/Contents/MacOS/Nuo" \
    "$app_path/Contents/MacOS/osaurus"
  do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

resolve_cli_from_dev() {
  # Try common DerivedData product locations
  local base="$REPO_ROOT/build/DerivedData/Build/Products/Release"
  for candidate in \
    "$base/Nuo.app/Contents/Helpers/nuo" \
    "$base/Nuo.app/Contents/MacOS/Nuo" \
    "$base/Nuo" \
    "$base/osaurus-cli" \
    "$base/osaurus.app/Contents/Helpers/osaurus" \
    "$base/osaurus.app/Contents/MacOS/osaurus" \
    "$REPO_ROOT/build/DerivedData/Build/Products/Debug/Nuo.app/Contents/Helpers/nuo" \
    "$REPO_ROOT/build/DerivedData/Build/Products/Debug/Nuo.app/Contents/MacOS/Nuo" \
    "$REPO_ROOT/build/DerivedData/Build/Products/Debug/Nuo" \
    "$REPO_ROOT/build/DerivedData/Build/Products/Debug/osaurus-cli" \
    "$REPO_ROOT/build/DerivedData/Build/Products/Debug/osaurus.app/Contents/Helpers/osaurus" \
    "$REPO_ROOT/build/DerivedData/Build/Products/Debug/osaurus.app/Contents/MacOS/osaurus"
  do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

resolve_target_bin_dir() {
  # Priority: explicit --prefix, /usr/local/bin, ~/.local/bin.
  #
  # Homebrew's prefix is intentionally NOT used as a default: it's a
  # directory Homebrew owns and manages, and Nuo isn't distributed via
  # a Homebrew formula — brew being present on a user's machine for
  # unrelated packages isn't a reason for this app to write into it.
  # See osaurus-ai/osaurus#2137.
  if [[ -n "$PREFIX_OVERRIDE" ]]; then
    echo "$PREFIX_OVERRIDE/bin"
    return 0
  fi

  if [[ -d "/usr/local/bin" ]]; then
    echo "/usr/local/bin"
    return 0
  fi

  echo "$HOME/.local/bin"
}

# Determine CLI source
CLI_SRC=""
if [[ "$DEV_MODE" == "1" ]]; then
  if CLI_SRC="$(resolve_cli_from_dev)"; then :; else
    echo "Could not locate a built CLI in DerivedData. Build it first: 'make cli'" >&2
    exit 1
  fi
else
  if [[ -z "$APP_PATH" ]]; then
    CANDIDATES=(
      "/Applications/Nuo.app"
      "$HOME/Applications/Nuo.app"
      "/Applications/Osaurus.app"
      "$HOME/Applications/Osaurus.app"
      "/Applications/osaurus.app"
      "$HOME/Applications/osaurus.app"
    )
    for c in "${CANDIDATES[@]}"; do
      if CLI_SRC="$(resolve_cli_from_app "$c")"; then
        APP_PATH="$c"
        break
      fi
    done
  else
    if CLI_SRC="$(resolve_cli_from_app "$APP_PATH")"; then :; else
      echo "CLI binary not found in: $APP_PATH" >&2
      echo "Expected at: $APP_PATH/Contents/Helpers/nuo (or Contents/MacOS/Nuo)" >&2
      exit 1
    fi
  fi

  if [[ -z "$CLI_SRC" ]]; then
    echo "Could not locate Nuo.app automatically. Provide the path explicitly." >&2
    echo "Example: scripts/release/install_cli_symlink.sh '/Applications/Nuo.app'" >&2
    exit 1
  fi
fi

TARGET_DIR="$(resolve_target_bin_dir)"

install_link() {
  local dir="$1"
  local link="$dir/nuo"
  local legacy="$dir/osaurus"

  mkdir -p "$dir"
  # `nuo` is ours: always repoint it at the CLI we just resolved.
  ln -sf "$CLI_SRC" "$link"
  echo "Installed symlink: $link -> $CLI_SRC"

  # `osaurus` may already belong to something else on this machine. Only fill
  # the gap when nothing exists there.
  if [[ ! -e "$legacy" && ! -L "$legacy" ]]; then
    ln -s "$CLI_SRC" "$legacy"
    echo "Installed legacy symlink: $legacy -> $CLI_SRC (one release only)"
  fi
}

if [[ -w "$TARGET_DIR" ]]; then
  install_link "$TARGET_DIR"
else
  # Fallback to user-local, avoid sudo prompts
  TARGET_DIR="$HOME/.local/bin"
  install_link "$TARGET_DIR"
  echo "Make sure $TARGET_DIR is on your PATH (e.g., add to your shell profile)."
fi
