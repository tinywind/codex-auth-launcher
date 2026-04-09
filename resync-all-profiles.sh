#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=./profile-common.sh
source "$SCRIPT_DIR/profile-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: codex-auth-resync-all

Resync shared Codex config from ~/.codex into every existing isolated profile.
Existing session and history state inside each profile is preserved.

Examples:
  codex-auth-resync-all
EOF
  exit 1
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
fi

REAL_HOME="${HOME:?HOME is required}"
LAUNCHER_HOME="${CODEX_AUTH_LAUNCHER_HOME:-$REAL_HOME/.codex-auth-launcher}"
BOOTSTRAP_HOME="${CODEX_AUTH_LAUNCHER_BOOTSTRAP_HOME:-$REAL_HOME/.codex}"
PROFILE_BASE_DIR="$(readlink -m "$LAUNCHER_HOME/profiles")"
LAUNCHER_HOME_CANONICAL="$(readlink -m "$LAUNCHER_HOME")"

if [ ! -d "$BOOTSTRAP_HOME" ]; then
  echo "Bootstrap home not found: $BOOTSTRAP_HOME" >&2
  exit 1
fi

case "$PROFILE_BASE_DIR" in
  "$LAUNCHER_HOME_CANONICAL"/*) ;;
  *)
    echo "Refusing to inspect a path outside the launcher home: $PROFILE_BASE_DIR" >&2
    exit 1
    ;;
esac

if [ ! -d "$PROFILE_BASE_DIR" ]; then
  echo "No isolated profiles found." >&2
  exit 0
fi

shopt -s nullglob
profile_roots=("$PROFILE_BASE_DIR"/*)
shopt -u nullglob

if [ "${#profile_roots[@]}" -eq 0 ]; then
  echo "No isolated profiles found." >&2
  exit 0
fi

resynced_count=0
for profile_root in "${profile_roots[@]}"; do
  [ -d "$profile_root" ] || continue

  profile_codex_home="$profile_root/codex-home"
  if [ ! -d "$profile_codex_home" ]; then
    continue
  fi

  sync_profile_home "$BOOTSTRAP_HOME" "$profile_codex_home"
  resynced_count=$((resynced_count + 1))
  echo "Resynced isolated Codex profile: $(basename "$profile_root")" >&2
done

if [ "$resynced_count" -eq 0 ]; then
  echo "No isolated profiles found." >&2
  exit 0
fi

echo "Resynced $resynced_count isolated Codex profile(s) from: $BOOTSTRAP_HOME" >&2
