#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=./profile-common.sh
source "$SCRIPT_DIR/profile-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: codex-auth-resync [--profile <name>] [--cred-file <path>]

Resync shared Codex config from ~/.codex into an existing isolated profile.
Existing session and history state inside the profile is preserved.

Options:
  --profile <name>  Profile hint used when the profile was created.
  --cred-file <path>
                    Auth file path. Optional when reusing an existing named profile.
  -h, --help        Show this help.

Examples:
  codex-auth-resync --cred-file ~/auth.json-work
  codex-auth-resync --profile review
  codex-auth-resync --profile review --cred-file ~/auth.json-work
EOF
  exit 1
}

PROFILE_HINT="${CODEX_AUTH_LAUNCHER_PROFILE:-}"
AUTH_FILE_INPUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || usage
      PROFILE_HINT="$2"
      shift 2
      ;;
    --cred-file)
      [ "$#" -ge 2 ] || usage
      AUTH_FILE_INPUT="$2"
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
      echo "Unexpected argument: $1" >&2
      usage
      ;;
  esac
done

REAL_HOME="${HOME:?HOME is required}"
LAUNCHER_HOME="${CODEX_AUTH_LAUNCHER_HOME:-$REAL_HOME/.codex-auth-launcher}"
BOOTSTRAP_HOME="${CODEX_AUTH_LAUNCHER_BOOTSTRAP_HOME:-$REAL_HOME/.codex}"
PROFILE_BASE_DIR="$LAUNCHER_HOME/profiles"
PROFILE_BASE_DIR_CANONICAL="$(readlink -m "$PROFILE_BASE_DIR")"
EXISTING_PROFILE_ROOT=""

if [ ! -d "$BOOTSTRAP_HOME" ]; then
  echo "Bootstrap home not found: $BOOTSTRAP_HOME" >&2
  exit 1
fi

if [ -n "$AUTH_FILE_INPUT" ] && [ ! -f "$AUTH_FILE_INPUT" ]; then
  echo "Auth file not found: $AUTH_FILE_INPUT" >&2
  exit 1
fi

if [ -n "$AUTH_FILE_INPUT" ]; then
  AUTH_FILE="$(readlink -f "$AUTH_FILE_INPUT")"
else
  AUTH_FILE=""
fi

if [ -n "$PROFILE_HINT" ]; then
  set +e
  EXISTING_PROFILE_ROOT="$(find_profile_root_by_hint "$PROFILE_BASE_DIR" "$PROFILE_HINT")"
  FIND_PROFILE_STATUS=$?
  set -e

  if [ "$FIND_PROFILE_STATUS" -eq 2 ]; then
    echo "Profile hint is ambiguous: $PROFILE_HINT" >&2
    echo "Reset duplicate profiles before reusing this profile hint." >&2
    exit 1
  fi

  if [ "$FIND_PROFILE_STATUS" -ne 0 ]; then
    exit "$FIND_PROFILE_STATUS"
  fi

  if [ -n "$EXISTING_PROFILE_ROOT" ]; then
    PROFILE_ROOT="$(readlink -m "$EXISTING_PROFILE_ROOT")"
    STORED_AUTH_FILE="$(load_profile_auth_source "$PROFILE_ROOT")"

    if [ -n "$AUTH_FILE" ] && [ -n "$STORED_AUTH_FILE" ] && [ "$AUTH_FILE" != "$STORED_AUTH_FILE" ]; then
      echo "Profile \"$PROFILE_HINT\" is already bound to a different auth.json:" >&2
      echo "  $STORED_AUTH_FILE" >&2
      echo "Use a different profile name or reset the profile first." >&2
      exit 1
    fi

    if [ -z "$AUTH_FILE" ]; then
      AUTH_FILE="$STORED_AUTH_FILE"
    fi
  else
    if [ -z "$AUTH_FILE" ]; then
      echo "Profile \"$PROFILE_HINT\" does not exist yet." >&2
      echo "Provide --cred-file only after that profile has been created, or create it first with codex-auth." >&2
      exit 1
    fi

    PROFILE_SLUG="$(sanitize_slug "$PROFILE_HINT")"
    PROFILE_ROOT="$(readlink -m "$PROFILE_BASE_DIR/${PROFILE_SLUG:-profile}")"
  fi
else
  if [ -z "$AUTH_FILE" ]; then
    echo "Missing required option: --cred-file" >&2
    usage
  fi

  AUTH_BASENAME="$(basename "$AUTH_FILE")"
  PROFILE_SLUG="$(printf '%s' "$AUTH_BASENAME" | tr '[:upper:]' '[:lower:]' | sed 's/\.[^.]*$//' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
  PROFILE_HASH="$(printf '%s' "$AUTH_FILE" | sha256sum | cut -c1-12)"
  PROFILE_ROOT="$(readlink -m "$PROFILE_BASE_DIR/${PROFILE_SLUG:-auth}-$PROFILE_HASH")"
fi

PROFILE_NAME="$(basename "$PROFILE_ROOT")"

case "$PROFILE_ROOT" in
  "$PROFILE_BASE_DIR_CANONICAL"/*) ;;
  *)
    echo "Refusing to resync a path outside the launcher home: $PROFILE_ROOT" >&2
    exit 1
    ;;
esac

if [ ! -e "$PROFILE_ROOT" ]; then
  echo "Profile not found: $PROFILE_NAME" >&2
  echo "Nothing to resync." >&2
  exit 1
fi

PROFILE_CODEX_HOME="$PROFILE_ROOT/codex-home"
if [ ! -d "$PROFILE_CODEX_HOME" ]; then
  echo "Profile Codex home not found: $PROFILE_CODEX_HOME" >&2
  exit 1
fi

sync_profile_home "$BOOTSTRAP_HOME" "$PROFILE_CODEX_HOME"

echo "Resynced isolated Codex profile: $PROFILE_NAME" >&2
echo "Source: $BOOTSTRAP_HOME" >&2
echo "Target: $PROFILE_CODEX_HOME" >&2
