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
- `codex-auth-resync` → refreshes one existing profile from `~/.codex`
- `codex-auth-resync-all` → refreshes every existing profile from `~/.codex`

## First-use bootstrap behavior

When a profile is created for the first time, the launcher bootstraps its `CODEX_HOME` from the real user home at `~/.codex`.

- This preserves your existing Codex config, skills, plugins, and local state layout.
- The copied `auth.json` is removed immediately.
- The profile then links `auth.json` to the selected source auth file.

Later runs for the same auth file reuse that same profile home instead of copying again.

If you want to refresh an existing profile from `~/.codex`, use `codex-auth-resync` or `codex-auth-resync-all`.
Those commands overwrite shared config copies such as `agents/`, `hooks/`, `skills/`, and `AGENTS.md`, while preserving existing profile-local session and history state.

If you create a named profile with `--profile`, that profile remembers its canonical auth file path in `profile.json`.
After the first run, you can reuse that profile by name without passing `--cred-file` again.

## No-copy guarantee for auth files

The launcher never copies your source auth file.

- Global mode creates a symlink at `~/.codex/auth.json`
- Isolated mode creates a symlink at `~/.codex-auth-launcher/profiles/<profile>/codex-home/auth.json`

Your source auth file remains the single source of truth, so refreshed tokens stay centralized.

## Quick start

1. Install the local commands:

   ```bash
   bash ~/IdeaProjects/codex-auth-launcher/install-bashrc-command.sh
   source ~/.bashrc
   ```

   The installer copies the runtime scripts into `~/.local/share/codex-auth-launcher`
   and installs standalone command files into `~/.local/bin`.
   It replaces any older `codex-auth-launcher` shell-function block in your rc file with a minimal PATH block.
   The copied commands continue to work even if the original repository directory is removed later.
   Re-run the installer after updating the repository when you want to refresh the copied command files.

2. Run Codex with a specific auth file:

   ```bash
   codex-auth --cred-file ~/auth.json-work login status
   codex-auth --cred-file ~/auth.json-work exec "Summarize this folder."
   ```

   `--cred-file` is explicit on first use.
   `codex-auth` errors and exits if `--cred-file` is missing and there is no stored auth path for the requested named profile.
    The remaining arguments are forwarded to `codex`.
    `codex-auth` automatically adds `--dangerously-bypass-approvals-and-sandbox` for interactive runs.
    It also adds `--skip-git-repo-check` when the forwarded Codex subcommand is `exec`.
   Launcher options can appear before or after Codex arguments.
   Use `--` only when you want everything after it to be passed to `codex` unchanged.

3. Create a reusable named profile:

   ```bash
     codex-auth --profile help --cred-file ~/auth.json-work exec "What did I ask earlier?"
     codex-auth-profile help --cred-file ~/auth.json-work exec "What did I ask earlier?"
     codex-auth exec "What did I ask earlier?" --profile help --cred-file ~/auth.json-work
   ```

   The profile stores the canonical auth path in its metadata.
   The first `codex-auth-profile <name>` run must include `--cred-file <path>` or the command exits with an error.
   `codex-auth-profile` reserves the first positional argument for the profile name.

4. Reuse that named profile later without passing the auth path again:

   ```bash
    codex-auth --profile help exec resume --last "Continue from the last run."
   codex-auth-home --profile help
   ```

   The same named profile resolves to the same isolated `CODEX_HOME`, so persisted sessions remain available.

5. Reset that profile when you want a clean start:

   ```bash
   codex-auth-reset --yes --profile help
   ```

   The next run recreates the profile by copying `~/.codex` again and relinking `auth.json`.

6. Reset every isolated profile at once:

   ```bash
   codex-auth-reset-all --yes
   ```

   This deletes all profile directories under `~/.codex-auth-launcher/profiles`.

## Commands

### 1) Switch the global auth link

```bash
codex-auth-link --cred-file ~/auth.json-work
```

This rewires the default `~/.codex/auth.json` symlink.

Use this when you only want one active default auth at a time.

### 2) Run Codex with an isolated auth home

```bash
codex-auth --cred-file ~/auth.json-work
codex-auth --cred-file ~/auth.json-work exec "Summarize this folder."
codex-auth --cred-file ~/auth.json-personal -- exec "Summarize this folder."
codex-auth --profile review --cred-file ~/auth.json-work exec "Summarize this folder."
codex-auth-profile review --cred-file ~/auth.json-work exec "Summarize this folder."
codex-auth exec "Summarize this folder." --profile review --cred-file ~/auth.json-work
codex-auth --profile review resume --last
```

Each auth file path gets its own isolated `CODEX_HOME`, so sessions, resumes, and history stay separate.

If you use the same auth file path again, the launcher reuses that same profile home.

If you create a named profile with `--profile`, that profile remembers its auth file path and can be reused later without `--cred-file`.
If you pass `--cred-file` again for an existing named profile, the launcher updates that profile's `auth.json` symlink and stored auth path without deleting the existing profile state.

`codex-auth-profile <name> ...` provides the same named-profile behavior, but it requires the profile name to be the first positional argument.
If that named profile does not already exist, omitting `--cred-file` is an error.

If you need to pass Codex's own `--profile` flag through to `codex`, put it after an explicit `--` so the launcher does not consume it.

```bash
codex-auth --profile review --cred-file ~/auth.json-work -- exec --profile fast
```

### 3) Print the prepared CODEX_HOME for a profile

```bash
codex-auth-home --cred-file ~/auth.json-work
codex-auth-home --profile review
CODEX_HOME="$(codex-auth-home --profile review)" codex login status
```

This is useful when you want to launch Codex yourself after preparing the profile home.

### 4) Reset an existing isolated profile

```bash
codex-auth-reset --cred-file ~/auth.json-work
codex-auth-reset --yes --cred-file ~/auth.json-work
codex-auth-reset --profile review --yes
codex-auth-reset --profile review --yes --cred-file ~/auth.json-work
```

This deletes the isolated profile directory for that auth file, including persisted sessions, history, and local Codex state.
The next `codex-auth` run recreates it from `~/.codex`.

### 5) Resync shared config from `~/.codex` into an existing profile

```bash
codex-auth-resync --cred-file ~/auth.json-work
codex-auth-resync --profile review
codex-auth-resync --profile review --cred-file ~/auth.json-work
```

This overwrites shared config copies from `~/.codex` in the selected profile.
Existing profile-local session and history state is preserved.

### 6) Resync every existing isolated profile

```bash
codex-auth-resync-all
```

This refreshes every existing profile from `~/.codex` while preserving each profile's local session and history state.

### 7) Reuse config or shared assets from an existing CODEX_HOME

```bash
codex-auth --link-config --cred-file ~/auth.json-work
codex-auth --link-config --share-path skills --share-path agents --cred-file ~/auth.json-work
codex-auth --base-home ~/.codex-team --share-path trustedFolders.json --cred-file ~/auth.json-team
```

Shared paths are symlinked into the isolated profile home. This is optional and off by default.

### 8) Reset every isolated profile

```bash
codex-auth-reset-all
codex-auth-reset-all --yes
```

This deletes every profile under `~/.codex-auth-launcher/profiles`.
Use it when you want to remove all persisted auth-specific session state at once.

## Launcher command syntax

```bash
codex-auth [--profile <name>] [--cred-file <path>] [--base-home <path>] [--link-config] [--share-path <relative-path>]... [--print-home] [--] [codex args...]
codex-auth-profile <profile-name> [launcher options] [--] [codex args...]
codex-auth-link [--codex-home <path>] --cred-file <auth-file>
codex-auth-home [--profile <name>] [--cred-file <path>] [--base-home <path>] [--link-config] [--share-path <relative-path>]...
codex-auth-resync [--profile <name>] [--cred-file <path>]
codex-auth-resync-all
codex-auth-reset [--profile <name>] [--cred-file <path>] [--yes]
codex-auth-reset-all [--yes]
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

~/.local/share/codex-auth-launcher/
├── profile-common.sh
├── run-with-auth.sh
├── run-with-profile.sh
├── link-global-auth.sh
├── resync-profile.sh
├── resync-all-profiles.sh
├── reset-profile.sh
└── reset-all-profiles.sh

~/.local/bin/
├── codex-auth
├── codex-auth-profile
├── codex-auth-link
├── codex-auth-home
├── codex-auth-resync
├── codex-auth-resync-all
├── codex-auth-reset
└── codex-auth-reset-all
```

## Notes

- The isolated mode keeps session state separate because each profile gets its own `CODEX_HOME`.
- `codex-auth` bootstraps a profile on first use, but it does not resync existing profiles automatically.
- `codex-auth-resync` and `codex-auth-resync-all` overwrite shared config copies from `~/.codex` while preserving existing profile-local session and history paths.
- Auto-generated profiles are keyed by the canonical auth file path.
- Named profiles created with `--profile` remember their auth file path and can be reused later without `--cred-file`.
- Passing `--cred-file` to an existing named profile rebinds that profile to the new auth file while keeping its existing sessions and local state.
- `codex-auth-profile` is a convenience wrapper that requires the profile name as the first positional argument.
- The installer copies standalone commands into the user-local command path instead of relying on shell function wrappers.
- `codex-auth-reset` deletes the isolated profile directory so the next run starts from a fresh bootstrap.
- `codex-auth-reset-all` deletes every isolated profile directory managed by the launcher.
- `codex resume`, `codex fork`, and session history only see data inside the current profile home.
- `--link-config` is opt-in. If the linked config redirects `history`, `sqlite_home`, or `log_dir`, that can reduce isolation.
- `--share-path` should only be used for files or directories you intentionally want to share.
