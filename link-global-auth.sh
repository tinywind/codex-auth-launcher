#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: codex-auth-link [--codex-home <path>] <auth-file>

Examples:
  codex-auth-link ~/auth.json-work
  codex-auth-link --codex-home ~/.codex-team ~/auth.json-team
EOF
  exit 1
}

TARGET_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AUTH_FILE_INPUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --codex-home)
      [ "$#" -ge 2 ] || usage
      TARGET_CODEX_HOME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [ -n "$AUTH_FILE_INPUT" ]; then
        usage
      fi
      AUTH_FILE_INPUT="$1"
      shift
      ;;
  esac
done

if [ -z "$AUTH_FILE_INPUT" ]; then
  usage
fi

if [ ! -f "$AUTH_FILE_INPUT" ]; then
  echo "Auth file not found: $AUTH_FILE_INPUT" >&2
  exit 1
fi

AUTH_FILE="$(readlink -f "$AUTH_FILE_INPUT")"
TARGET_CODEX_HOME="$(readlink -m "$TARGET_CODEX_HOME")"
GLOBAL_AUTH_FILE="$TARGET_CODEX_HOME/auth.json"

mkdir -p "$TARGET_CODEX_HOME"
chmod 700 "$TARGET_CODEX_HOME" 2>/dev/null || true

if [ -e "$GLOBAL_AUTH_FILE" ] && [ ! -L "$GLOBAL_AUTH_FILE" ]; then
  BACKUP_PATH="$GLOBAL_AUTH_FILE.backup.$(date +%Y%m%d%H%M%S)"
  mv "$GLOBAL_AUTH_FILE" "$BACKUP_PATH"
  echo "Backed up existing auth file to: $BACKUP_PATH" >&2
fi

ln -sfn "$AUTH_FILE" "$GLOBAL_AUTH_FILE"

echo "Linked Codex auth file:" >&2
echo "  $GLOBAL_AUTH_FILE -> $AUTH_FILE" >&2
echo "Only one auth link can be active in a single CODEX_HOME." >&2
echo "For simultaneous multi-auth sessions, use codex-auth." >&2
