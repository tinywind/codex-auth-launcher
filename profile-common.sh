#!/usr/bin/env bash

sanitize_slug() {
  local value="$1"

  printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'
}

find_profile_root_by_hint() {
  local profile_base_dir="$1"
  local profile_hint="$2"

  if [ ! -d "$profile_base_dir" ]; then
    return 0
  fi

  python3 - "$profile_base_dir" "$profile_hint" <<'PY'
import json
import os
import sys

base_dir, hint = sys.argv[1:3]
matches = []

for name in sorted(os.listdir(base_dir)):
    profile_root = os.path.join(base_dir, name)
    metadata_path = os.path.join(profile_root, "profile.json")

    if not os.path.isfile(metadata_path):
        continue

    try:
        with open(metadata_path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError):
        continue

    if payload.get("profileHint") == hint:
        matches.append(profile_root)

if len(matches) > 1:
    print(f'Multiple profiles matched hint {hint!r}:', file=sys.stderr)
    for match in matches:
        print(match, file=sys.stderr)
    sys.exit(2)

if matches:
    print(matches[0])
PY
}

load_profile_auth_source() {
  local profile_root="$1"
  local metadata_path="$profile_root/profile.json"

  if [ ! -f "$metadata_path" ]; then
    return 0
  fi

  python3 - "$metadata_path" <<'PY'
import json
import sys

metadata_path = sys.argv[1]

try:
    with open(metadata_path, encoding="utf-8") as handle:
        payload = json.load(handle)
except (OSError, json.JSONDecodeError):
    sys.exit(0)

auth_source = payload.get("authSource")
if auth_source:
    print(auth_source)
PY
}

sync_profile_home() {
  local source_home="$1"
  local target_home="$2"

  if [ ! -d "$source_home" ]; then
    return 0
  fi

  python3 - "$source_home" "$target_home" <<'PY'
import fnmatch
import os
import shutil
import stat
import sys
from pathlib import Path

source_home = Path(sys.argv[1]).resolve()
target_home = Path(sys.argv[2])

skip_root_names = {"auth.json"}
preserve_existing_root_names = {
    ".playwright-mcp",
    ".tmp",
    "cache",
    "chrome",
    "debug",
    "downloads",
    "file-history",
    "history",
    "history.jsonl",
    "log",
    "memories",
    "paste-cache",
    "plans",
    "projects",
    "projects.json",
    "session-data",
    "session-env",
    "session_index.jsonl",
    "sessions",
    "shell_snapshots",
    "shell-snapshots",
    "tasks",
    "telemetry",
    "tmp",
}
preserve_existing_root_patterns = (
    "logs_*.sqlite",
    "logs_*.sqlite-*",
    "models_cache.json",
    "mcp-needs-auth-cache.json",
    "state*.sqlite",
    "state*.sqlite-*",
    "state.json",
    "stats-cache.json",
)


def remove_path(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
        return

    if path.is_dir():
        shutil.rmtree(path)


def same_regular_file(source_path, target_path):
    try:
        source_stat = source_path.stat(follow_symlinks=False)
        target_stat = target_path.stat(follow_symlinks=False)
    except OSError:
        return False

    if not stat.S_ISREG(source_stat.st_mode) or not stat.S_ISREG(target_stat.st_mode):
        return False

    return (
        source_stat.st_size == target_stat.st_size
        and source_stat.st_mtime_ns == target_stat.st_mtime_ns
    )


def relative_parts(source_path):
    return source_path.relative_to(source_home).parts


def skip_source_copy(parts):
    return len(parts) == 1 and parts[0] in skip_root_names


def preserve_existing_target(parts):
    if not parts:
        return False

    root_name = parts[0]
    if root_name in preserve_existing_root_names:
        return True

    return len(parts) == 1 and any(
        fnmatch.fnmatch(root_name, pattern)
        for pattern in preserve_existing_root_patterns
    )


def ensure_target_directory(target_path):
    if target_path.is_symlink() or (target_path.exists() and not target_path.is_dir()):
        remove_path(target_path)

    target_path.mkdir(parents=True, exist_ok=True)


def copy_entry(source_path, target_path):
    parts = relative_parts(source_path)

    if skip_source_copy(parts):
        return

    if preserve_existing_target(parts) and (target_path.exists() or target_path.is_symlink()):
        return

    if source_path.is_symlink():
        target_path.parent.mkdir(parents=True, exist_ok=True)
        link_target = os.readlink(source_path)

        if target_path.is_symlink() and os.readlink(target_path) == link_target:
            return

        if target_path.exists() or target_path.is_symlink():
            remove_path(target_path)

        os.symlink(link_target, target_path)
        return

    if source_path.is_dir():
        ensure_target_directory(target_path)
        for child_name in sorted(os.listdir(source_path)):
            copy_entry(source_path / child_name, target_path / child_name)
        shutil.copystat(source_path, target_path, follow_symlinks=False)
        return

    target_path.parent.mkdir(parents=True, exist_ok=True)

    if target_path.is_symlink() or (target_path.exists() and not target_path.is_file()):
        remove_path(target_path)

    if target_path.exists() and same_regular_file(source_path, target_path):
        return

    shutil.copy2(source_path, target_path, follow_symlinks=False)


target_home.mkdir(parents=True, exist_ok=True)

for child_name in sorted(os.listdir(source_home)):
    copy_entry(source_home / child_name, target_home / child_name)
PY
}
