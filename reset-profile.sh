#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: codex-auth-reset [--profile <name>] [--yes] <auth-file>

Delete the isolated Codex profile for the given auth file.
The next run recreates it by copying ~/.codex and relinking auth.json.

Options:
  --profile <name>  Profile hint used when the profile was created.
  --yes             Delete without confirmation.
  -h, --help        Show this help.

Examples:
  codex-auth-reset ~/auth.json-work
  codex-auth-reset --yes ~/auth.json-work
  codex-auth-reset --profile review --yes ~/auth.json-work
EOF
  exit 1
}

sanitize_slug() {
  local value="$1"

  printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'
}

PROFILE_HINT="${CODEX_AUTH_LAUNCHER_PROFILE:-}"
ASSUME_YES=0
AUTH_FILE_INPUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || usage
      PROFILE_HINT="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
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
REAL_HOME="${HOME:?HOME is required}"
LAUNCHER_HOME="${CODEX_AUTH_LAUNCHER_HOME:-$REAL_HOME/.codex-auth-launcher}"
PROFILE_BASE_DIR="$LAUNCHER_HOME/profiles"
PROFILE_BASE_DIR_CANONICAL="$(readlink -m "$PROFILE_BASE_DIR")"

if [ -n "$PROFILE_HINT" ]; then
  PROFILE_SLUG="$(sanitize_slug "$PROFILE_HINT")"
  PROFILE_HASH="$(printf '%s|%s' "$AUTH_FILE" "$PROFILE_HINT" | sha256sum | cut -c1-12)"
else
  AUTH_BASENAME="$(basename "$AUTH_FILE")"
  PROFILE_SLUG="$(printf '%s' "$AUTH_BASENAME" | tr '[:upper:]' '[:lower:]' | sed 's/\.[^.]*$//' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
  PROFILE_HASH="$(printf '%s' "$AUTH_FILE" | sha256sum | cut -c1-12)"
fi

PROFILE_NAME="${PROFILE_SLUG:-auth}-$PROFILE_HASH"
PROFILE_ROOT="$(readlink -m "$PROFILE_BASE_DIR/$PROFILE_NAME")"

case "$PROFILE_ROOT" in
  "$PROFILE_BASE_DIR_CANONICAL"/*) ;;
  *)
    echo "Refusing to remove a path outside the launcher home: $PROFILE_ROOT" >&2
    exit 1
    ;;
esac

if [ ! -e "$PROFILE_ROOT" ]; then
  echo "Profile not found: $PROFILE_NAME" >&2
  echo "Nothing to reset." >&2
  exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  if [ ! -t 0 ]; then
    echo "Refusing to reset without --yes in non-interactive mode." >&2
    exit 1
  fi

  printf 'Delete isolated Codex profile "%s" and all persisted sessions? [y/N] ' "$PROFILE_NAME" >&2
  read -r confirmation
  case "$confirmation" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted." >&2
      exit 1
      ;;
  esac
fi

rm -rf "$PROFILE_ROOT"

echo "Removed isolated Codex profile: $PROFILE_NAME" >&2
echo "Removed path: $PROFILE_ROOT" >&2
