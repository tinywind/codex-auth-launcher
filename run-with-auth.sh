#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: codex-auth [options] <auth-file> [-- codex args...]

Options:
  --profile <name>      Stable profile hint for the isolated CODEX_HOME.
  --base-home <path>    Existing CODEX_HOME used by --link-config and --share-path.
  --link-config         Link config.toml from the base home into the profile.
  --share-path <path>   Link an additional relative path from the base home.
  --print-home          Print the prepared CODEX_HOME and exit.
  -h, --help            Show this help.

Examples:
  codex-auth ~/auth.json-work
  codex-auth ~/auth.json-work -- exec --skip-git-repo-check "Summarize this folder."
  codex-auth --profile review ~/auth.json-work -- resume --last
  codex-auth --link-config --share-path skills ~/auth.json-work
EOF
  exit 1
}

sanitize_slug() {
  local value="$1"

  printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'
}

ensure_relative_share_path() {
  local relative_path="$1"

  if [[ "$relative_path" = /* ]]; then
    echo "Shared paths must be relative to the base home: $relative_path" >&2
    exit 1
  fi
}

ensure_auth_link() {
  local source_auth="$1"
  local target_auth="$2"

  if [ -e "$target_auth" ] && [ ! -L "$target_auth" ]; then
    local backup_path
    backup_path="$target_auth.backup.$(date +%Y%m%d%H%M%S)"
    mv "$target_auth" "$backup_path"
    echo "Backed up existing profile auth file to: $backup_path" >&2
  fi

  ln -sfn "$source_auth" "$target_auth"
}

ensure_shared_path_link() {
  local base_home="$1"
  local relative_path="$2"
  local source_path
  local target_path

  ensure_relative_share_path "$relative_path"

  source_path="$base_home/$relative_path"
  if [ ! -e "$source_path" ]; then
    echo "Shared path not found in base home, skipping: $relative_path" >&2
    return 0
  fi

  source_path="$(readlink -f "$source_path")"
  case "$source_path" in
    "$base_home"|"$base_home"/*) ;;
    *)
      echo "Shared path resolves outside the base home: $relative_path" >&2
      exit 1
      ;;
  esac

  target_path="$PROFILE_CODEX_HOME/$relative_path"
  mkdir -p "$(dirname "$target_path")"

  if [ -L "$target_path" ]; then
    ln -sfn "$source_path" "$target_path"
    return 0
  fi

  if [ -e "$target_path" ]; then
    echo "Leaving existing profile path untouched: $target_path" >&2
    return 0
  fi

  ln -s "$source_path" "$target_path"
}

PROFILE_HINT="${CODEX_AUTH_LAUNCHER_PROFILE:-}"
BASE_HOME_INPUT="${CODEX_AUTH_LAUNCHER_BASE_HOME:-$HOME/.codex}"
LINK_CONFIG=0
PRINT_HOME=0
AUTH_FILE_INPUT=""
declare -a SHARE_PATHS=()
declare -a CODEX_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || usage
      PROFILE_HINT="$2"
      shift 2
      ;;
    --base-home)
      [ "$#" -ge 2 ] || usage
      BASE_HOME_INPUT="$2"
      shift 2
      ;;
    --link-config)
      LINK_CONFIG=1
      shift
      ;;
    --share-path)
      [ "$#" -ge 2 ] || usage
      SHARE_PATHS+=("$2")
      shift 2
      ;;
    --print-home)
      PRINT_HOME=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      CODEX_ARGS=("$@")
      break
      ;;
    -* )
      echo "Unknown launcher option: $1" >&2
      usage
      ;;
    *)
      if [ -z "$AUTH_FILE_INPUT" ]; then
        AUTH_FILE_INPUT="$1"
      else
        CODEX_ARGS+=("$1")
      fi
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

if [ -n "$PROFILE_HINT" ]; then
  PROFILE_SLUG="$(sanitize_slug "$PROFILE_HINT")"
  PROFILE_HASH="$(printf '%s|%s' "$AUTH_FILE" "$PROFILE_HINT" | sha256sum | cut -c1-12)"
else
  AUTH_BASENAME="$(basename "$AUTH_FILE")"
  PROFILE_SLUG="$(printf '%s' "$AUTH_BASENAME" | tr '[:upper:]' '[:lower:]' | sed 's/\.[^.]*$//' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
  PROFILE_HASH="$(printf '%s' "$AUTH_FILE" | sha256sum | cut -c1-12)"
fi

PROFILE_NAME="${PROFILE_SLUG:-auth}-$PROFILE_HASH"
PROFILE_ROOT="$PROFILE_BASE_DIR/$PROFILE_NAME"
PROFILE_CODEX_HOME="$PROFILE_ROOT/codex-home"
PROFILE_METADATA_FILE="$PROFILE_ROOT/profile.json"
PROFILE_AUTH_FILE="$PROFILE_CODEX_HOME/auth.json"

mkdir -p "$PROFILE_BASE_DIR" "$PROFILE_ROOT" "$PROFILE_CODEX_HOME"
chmod 700 "$LAUNCHER_HOME" "$PROFILE_BASE_DIR" "$PROFILE_ROOT" "$PROFILE_CODEX_HOME" 2>/dev/null || true

ensure_auth_link "$AUTH_FILE" "$PROFILE_AUTH_FILE"

BASE_HOME=""
if [ "$LINK_CONFIG" -eq 1 ] || [ "${#SHARE_PATHS[@]}" -gt 0 ]; then
  if [ ! -d "$BASE_HOME_INPUT" ]; then
    echo "Base home not found: $BASE_HOME_INPUT" >&2
    exit 1
  fi
  BASE_HOME="$(readlink -f "$BASE_HOME_INPUT")"
fi

if [ "$LINK_CONFIG" -eq 1 ]; then
  ensure_shared_path_link "$BASE_HOME" "config.toml"
fi

if [ "${#SHARE_PATHS[@]}" -gt 0 ]; then
  for shared_path in "${SHARE_PATHS[@]}"; do
    ensure_shared_path_link "$BASE_HOME" "$shared_path"
  done
fi

SHARED_PATHS_SERIALIZED=""
if [ "${#SHARE_PATHS[@]}" -gt 0 ]; then
  SHARED_PATHS_SERIALIZED="$(printf '%s\n' "${SHARE_PATHS[@]}")"
fi

PROFILE_NAME="$PROFILE_NAME" \
PROFILE_HINT="$PROFILE_HINT" \
AUTH_FILE="$AUTH_FILE" \
PROFILE_ROOT="$PROFILE_ROOT" \
PROFILE_CODEX_HOME="$PROFILE_CODEX_HOME" \
PROFILE_AUTH_FILE="$PROFILE_AUTH_FILE" \
BASE_HOME="$BASE_HOME" \
LINK_CONFIG="$LINK_CONFIG" \
SHARED_PATHS_SERIALIZED="$SHARED_PATHS_SERIALIZED" \
python3 - "$PROFILE_METADATA_FILE" <<'PY'
import json
import os
import sys

metadata_path = sys.argv[1]
shared_paths = [line for line in os.environ.get("SHARED_PATHS_SERIALIZED", "").splitlines() if line]

payload = {
    "profileName": os.environ["PROFILE_NAME"],
    "profileHint": os.environ["PROFILE_HINT"],
    "authSource": os.environ["AUTH_FILE"],
    "profileRoot": os.environ["PROFILE_ROOT"],
    "codexHome": os.environ["PROFILE_CODEX_HOME"],
    "authLink": os.environ["PROFILE_AUTH_FILE"],
    "baseHome": os.environ.get("BASE_HOME") or None,
    "linkConfig": os.environ["LINK_CONFIG"] == "1",
    "sharedPaths": shared_paths,
}

with open(metadata_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY
chmod 600 "$PROFILE_METADATA_FILE"

if [ "$PRINT_HOME" -eq 1 ]; then
  printf '%s\n' "$PROFILE_CODEX_HOME"
  exit 0
fi

echo "Using isolated Codex profile: $PROFILE_NAME" >&2
echo "Auth symlink: $PROFILE_AUTH_FILE -> $AUTH_FILE" >&2
echo "CODEX_HOME: $PROFILE_CODEX_HOME" >&2

CODEX_HOME="$PROFILE_CODEX_HOME" command codex "${CODEX_ARGS[@]}"
