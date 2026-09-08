#!/usr/bin/env bash
# Locate and run the cOMtrol binary without hardcoding a single install path.
set -euo pipefail

find_bin() {
  if command -v cOMtrol >/dev/null 2>&1; then
    command -v cOMtrol
    return 0
  fi
  if [[ -n "${COMTROL_BIN:-}" && -x "${COMTROL_BIN}" ]]; then
    printf '%s\n' "$COMTROL_BIN"
    return 0
  fi

  local here
  here="$(cd "$(dirname "$0")" && pwd)"
  local candidate
  for candidate in \
    "$HOME/.local/bin/cOMtrol" \
    "$HOME/.cargo/bin/cOMtrol" \
    "$here/../../target/release/cOMtrol" \
    "$here/../../target/debug/cOMtrol"
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
      return 0
    fi
  done
  return 1
}

BIN="$(find_bin)" || {
  echo "cOMtrol binary not found. Put it on PATH or set COMTROL_BIN." >&2
  exit 127
}

exec "$BIN" "$@"
