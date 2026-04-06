#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
RUNNER_PATH="$SCRIPT_DIR/run-with-auth.sh"

usage() {
  cat >&2 <<'EOF'
Usage: codex-auth-profile <profile-name> [launcher options] [--] [codex args...]

The profile name must be the first positional argument.
On first use of a profile, you must pass --auth.json <path>.
This command is a wrapper around:
  codex-auth --profile <profile-name> ...

Examples:
  codex-auth-profile help --auth.json ~/auth.json-work login status
  codex-auth-profile help exec --skip-git-repo-check "Summarize this folder."
  codex-auth-profile help -- exec --profile fast
EOF
  exit 1
}

if [ "$#" -eq 0 ]; then
  usage
fi

case "$1" in
  -h|--help)
    usage
    ;;
esac

PROFILE_NAME="$1"
shift

if [ -z "$PROFILE_NAME" ]; then
  usage
fi

SCAN_REMAINING=1
for argument in "$@"; do
  if [ "$SCAN_REMAINING" -eq 1 ] && [ "$argument" = "--" ]; then
    SCAN_REMAINING=0
    continue
  fi

  if [ "$SCAN_REMAINING" -eq 1 ] && [ "$argument" = "--profile" ]; then
    echo "codex-auth-profile already consumes the profile name as the first argument." >&2
    echo "Remove the extra --profile option from the remaining launcher arguments." >&2
    exit 1
  fi
done

exec bash "$RUNNER_PATH" --profile "$PROFILE_NAME" "$@"
