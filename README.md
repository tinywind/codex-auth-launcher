# Codex Auth Launcher

This toolset lets you run Codex CLI with multiple `auth.json` files at the same time.

It supports two modes:

1. **Global auth link switch** for one default `CODEX_HOME`.
2. **Isolated per-auth launcher** for running multiple Codex sessions at the same time.

## Why there are two modes

Codex stores both authentication and session state under one `CODEX_HOME` directory.

- The default `CODEX_HOME` is usually `~/.codex`.
- The default auth file is usually `~/.codex/auth.json`.
- Session history, resumes, sqlite state, and logs also live under that same home.

If multiple auth files share one `CODEX_HOME`, resume history and session state are mixed together.

This launcher solves that by using:

- `codex-auth-link` → relinks the default `auth.json`
- `codex-auth` → runs Codex with a dedicated `CODEX_HOME` per auth file
- `codex-auth-home` → prints the isolated `CODEX_HOME` path for a profile

## First-use bootstrap behavior

When a profile is created for the first time, the launcher bootstraps its `CODEX_HOME` from the real user home at `~/.codex`.

- This preserves your existing Codex config, skills, plugins, and local state layout.
- The copied `auth.json` is removed immediately.
- The profile then links `auth.json` to the selected source auth file.

Later runs for the same auth file reuse the same profile home instead of copying again.

## No-copy guarantee for auth files

The launcher never copies your source auth file.

- Global mode creates a symlink at `~/.codex/auth.json`
- Isolated mode creates a symlink at `~/.codex-auth-launcher/profiles/<profile>/codex-home/auth.json`

Your source auth file remains the single source of truth, so refreshed tokens stay centralized.

## Quick start

1. Install the shell functions:

   ```bash
   bash ~/IdeaProjects/codex-auth-launcher/install-bashrc-command.sh
   source ~/.bashrc
   ```

2. Run Codex with a specific auth file:

   ```bash
   codex-auth ~/auth.json-work login status
   codex-auth ~/auth.json-work exec --skip-git-repo-check "Summarize this folder."
   ```

   After the auth file argument is parsed, the remaining arguments are forwarded to `codex`.
   The `--` separator is optional.

3. Reuse the same auth file path later:

   ```bash
   codex-auth ~/auth.json-work exec --skip-git-repo-check "What did I ask earlier?"
   codex-auth ~/auth.json-work exec resume --last --skip-git-repo-check "Continue from the last run."
   ```

   The same canonical auth file path resolves to the same isolated `CODEX_HOME`, so persisted sessions remain available.

4. Reset that profile when you want a clean start:

   ```bash
   codex-auth-reset --yes ~/auth.json-work
   ```

   The next run recreates the profile by copying `~/.codex` again and relinking `auth.json`.

## Commands

### 1) Switch the global auth link

```bash
codex-auth-link ~/auth.json-work
```

This rewires the default `~/.codex/auth.json` symlink.

Use this when you only want one active default auth at a time.

### 2) Run Codex with an isolated auth home

```bash
codex-auth ~/auth.json-work
codex-auth ~/auth.json-work exec --skip-git-repo-check "Summarize this folder."
codex-auth ~/auth.json-personal -- exec --skip-git-repo-check "Summarize this folder."
codex-auth --profile review ~/auth.json-work -- resume --last
```

Each auth file path gets its own isolated `CODEX_HOME`, so sessions, resumes, and history stay separate.

If you use the same auth file path again, the launcher reuses that same profile home.

### 3) Print the prepared CODEX_HOME for a profile

```bash
codex-auth-home ~/auth.json-work
CODEX_HOME="$(codex-auth-home ~/auth.json-work)" codex login status
```

This is useful when you want to launch Codex yourself after preparing the profile home.

### 4) Reset an existing isolated profile

```bash
codex-auth-reset ~/auth.json-work
codex-auth-reset --yes ~/auth.json-work
codex-auth-reset --profile review --yes ~/auth.json-work
```

This deletes the isolated profile directory for that auth file, including persisted sessions, history, and local Codex state.
The next `codex-auth` run recreates it from `~/.codex`.

### 5) Reuse config or shared assets from an existing CODEX_HOME

```bash
codex-auth --link-config ~/auth.json-work
codex-auth --link-config --share-path skills --share-path agents ~/auth.json-work
codex-auth --base-home ~/.codex-team --share-path trustedFolders.json ~/auth.json-team
```

Shared paths are symlinked into the isolated profile home. This is optional and off by default.

## Launcher command syntax

```bash
codex-auth [--profile <name>] [--base-home <path>] [--link-config] [--share-path <relative-path>]... [--print-home] <auth-file> [--] [codex args...]
codex-auth-link [--codex-home <path>] <auth-file>
codex-auth-home [--profile <name>] [--base-home <path>] [--link-config] [--share-path <relative-path>]... <auth-file>
codex-auth-reset [--profile <name>] [--yes] <auth-file>
```

## Files created by the launcher

```text
~/.codex-auth-launcher/
└── profiles/
    └── <profile>/
        ├── profile.json
        └── codex-home/
            ├── auth.json -> /path/to/your/auth.json
            ├── sessions/
            ├── history/
            ├── session_index.jsonl
            └── ... Codex-managed state files ...
```

## Notes

- The isolated mode keeps session state separate because each profile gets its own `CODEX_HOME`.
- The first run for a profile copies the current `~/.codex` into that isolated home before replacing `auth.json` with a symlink.
- The same canonical auth file path and the same optional `--profile` value resolve to the same isolated profile directory.
- `codex-auth-reset` deletes the isolated profile directory so the next run starts from a fresh bootstrap.
- `codex resume`, `codex fork`, and session history only see data inside the current profile home.
- `--link-config` is opt-in. If the linked config redirects `history`, `sqlite_home`, or `log_dir`, that can reduce isolation.
- `--share-path` should only be used for files or directories you intentionally want to share.
