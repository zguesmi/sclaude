# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`sbxc` (sandbox-claude) is a host-side wrapper around the `sbx` CLI (sandbox manager). It automates
post-install configuration of a Claude Code sandbox so a fresh sandbox is immediately usable — no
manual `sbx settings set` / secret / prompt setup by hand. There is no build, no test suite, and no
package manager: this is a handful of bash scripts plus two `sbx` "kit" specs (YAML manifests
consumed by the `sbx` CLI, not by this repo's own tooling).

## Layout

```
sbxc.sh                                     host wrapper (entry point)
shell-prompt-kit/spec.yaml                  mixin: powerline PS1 (SBX | sandbox name | cwd)
statusline-kit/spec.yaml                    mixin: registers the Claude Code statusline at install
statusline-kit/files/home/.claude/
    statusline.sh                           → copied to /home/agent/.claude/statusline.sh in-sandbox
git-guardrails-kit/spec.yaml                mixin: registers a PreToolUse hook on Bash at install
git-guardrails-kit/files/home/.claude/hooks/
    git-guardrails.sh                       → /home/agent/.claude/hooks/git-guardrails.sh in-sandbox
access-audit-kit/spec.yaml                  mixin: registers PostToolUse + Notification hooks at install
access-audit-kit/files/home/.claude/hooks/
    access-audit.sh                         → hook that spots denials in tool results / prompts
    record-denial.sh                        → shared writer for <repo>/.sbx/access-denials.{jsonl,md}
```

A "kit" is an `sbx` mixin: a `spec.yaml` with `setup.install` commands (run once, at sandbox creation) plus
an optional `files/` tree that gets copied verbatim into the sandbox's home directory. `sbxc.sh`
always loads `shell-prompt-kit`, `statusline-kit`, `git-guardrails-kit` and `access-audit-kit` from
its own directory at creation time. By
default all of `sbxc`'s CLI args go to `claude` instead (see below) — a caller-supplied `--` splits
that: args before it go to `claude`, args after it (e.g. an extra `--kit ...`) go to `sbx create`,
which only matters the first time, before the sandbox exists.

## Running / testing changes

There's no local test runner — the only way to validate a change is to actually create/refresh a
sandbox with `sbx` and inspect the result:

```shell
./sbxc.sh                 # from a project directory; creates/enters "claude-<dirname>"
sbx exec -it <name> bash  # re-enter an existing sandbox without re-running setup
sbx kit add <name> <path-to-kit>   # apply a kit to an existing sandbox (restarts, preserves VM state)
```

Sandbox naming: `claude-<basename-of-cwd>`, non-alphanumeric characters in the basename replaced
with `-`, passed explicitly as `--name` at create. `sbxc.sh` derives the same name on every run,
which is how `sandbox_exists()` recognises an already-configured sandbox.

To check what actually landed in a sandbox after setup:

```shell
sbx exec <name> -- bash -lc 'git config list | grep name'
sbx exec <name> -- bash -lc 'jq . ~/.claude/settings.json'
```

(`sbxc.sh` has a `validate()` function that runs checks like this; it's currently disabled — the
call is commented out in `main()`.)

## Architecture / how the pieces fit together

**Two persistence mechanisms inside a sandbox, used for different things:**

1. `/etc/sandbox-persistent.sh` — sourced before *every* bash invocation in the sandbox. `sbxc.sh`
   Anything appending to it must append rather than overwrite, since multiple install steps and kits share
   this one file. This is also why shell completion scripts must never be appended here (they
   reference `COMP_WORDS`/`COMPREPLY`, which don't exist outside an actual completion context, and
   sourcing them on every command breaks bash entirely).
2. `~/.claude/settings.json` — must be merged via `jq`, never overwritten, since more than one kit
   (or the user) may set different top-level keys. `statusline-kit` does `jq '.statusLine = {...}'`
   into a temp file in the same directory, then `mv`s it over the original for an atomic replace.
   `git-guardrails-kit` and `access-audit-kit` merge into the same file, so their `jq` must also
   append to `.hooks.<Event>` rather than assign it — each first drops any entry already pointing at
   its own script (so re-applying a kit can't stack duplicates), then appends its own entry. Both
   kits plus the statusline have been verified to survive each other, applied twice each.

**Ordering constraints that matter when editing a kit's `spec.yaml`:**
- A mixin's `install` commands run *after* the agent's own seeding — that's why a `jq` merge done in
  `install` survives, while static `files/` / `initFiles` placed at the same path do not (those are
  applied earlier and get clobbered by the agent's own seed).
- `install` commands run *before* `files/` is copied in. A kit's install script cannot `chmod` or
  otherwise touch a file it ships in `files/` — set the executable bit in the file's own mode instead.

**`sbxc.sh` control flow**: `"$@"` is split up front on the first literal `--` into `CLAUDE_ARGS`
(before) and `SBX_CREATE_ARGS` (after) — both module-level arrays, read directly by the functions
below rather than passed around. `main()` (at the bottom) checks if the sandbox already exists
(`sandbox_exists`, via `sbx ls`) → if new, runs host config, GitHub token provisioning and
`create_sandbox` (bundled kits + `SBX_CREATE_ARGS`), in that order; if it
already exists and `SBX_CREATE_ARGS` is non-empty, warns that those args are being ignored (they only
mean something at creation) → always ends by `exec`-ing into
`sbx run --name <name> -- "${CLAUDE_ARGS[@]}"` (`run_sandbox`). Setup is one-shot per sandbox, not
idempotently re-applied on every invocation.

`sbxc` lands you directly in Claude Code, not a shell — `sbxc -r` becomes `claude -r`, `sbxc agents`
becomes `claude agents`, and so on; running plain `sbxc` again against the same project just starts
another Claude session in the same sandbox. For a plain shell (e.g. to run other commands), use
`sbx exec -it <name> bash` directly — `shell-prompt-kit` is still installed by default so that shell
gets the powerline prompt, even though it's no longer where `sbxc` lands you.

**Statusline script** (`statusline-kit/files/home/.claude/statusline.sh`) reads Claude Code's
statusline JSON payload from stdin and renders: cwd, git branch, model + effort, context
window usage %, 5-hour rate-limit usage, session cost, and an optional "caveman" plugin badge (driven
by flag files under `~/.claude/`, unrelated to this repo — read defensively, don't assume that plugin
exists). The cwd is shortened before display: `$HOME` becomes `~`, then leading path components are
dropped until it fits `SBX_STATUSLINE_MAX_DIR` (default 32), leaving `…/Obsidian/personal-obsidian-vault`
— the deepest components are the informative ones, so they are the ones kept. A single component longer
than the limit is still shown whole.

**Git guard hook** (`git-guardrails-kit/files/home/.claude/hooks/git-guardrails.sh`) is a `PreToolUse` hook on
`Bash`: it reads the payload from stdin, takes `.tool_input.command`, and `exit 2`s with a reason on
stderr to block the call (exit 2 is the block signal; the stderr text goes back to the model).
Everything it doesn't recognise — and every failure path, including missing `jq` or unparseable JSON —
exits 0, deliberately: a hook that errors out must not cut off the sandbox's shell access. Matching is
plain `grep -E` over the whitespace-normalised command string, with `[^;&|]*` inside patterns so a
match can't span two chained commands; it is textual, so `git log --grep 'reset --hard'` is blocked
too, which is accepted rather than worked around. `~/.claude/.git-guardrails-off` short-circuits the whole
hook — an accident guard, not a security boundary, since the agent can create that file itself. Each
deny is also handed to `record-denial.sh` when `access-audit-kit` is installed; that call is wrapped in
`[ -x ... ] && ... || true` so the two kits stay independent and a failing recorder can't change the
verdict.

**Access audit hooks** (`access-audit-kit/files/home/.claude/hooks/`) log what the sandbox refused,
into `<repo-root>/.sbx/access-denials.jsonl` plus a regenerated `access-denials.md` summary (counts per
target + copy-paste `sbx policy allow network` commands). `access-audit.sh` is registered on two events
and branches on `.hook_event_name`:
- `PostToolUse` (`Bash|WebFetch|WebSearch`) — where sbx proxy denials surface. The proxy answers a
  blocked request with HTTP 403 and the body `Blocked by network policy: domain <host>:<port>` (verified
  against v0.37.0/v0.38.0 by curling a blocked host from inside a sandbox), so the hook greps
  `Blocked by <word> policy: <word> <resource>` out of the flattened tool result and files each hit
  under the policy word as its kind — one `network` row per host:port.
- `Notification` — permission prompts. A call blocked at `PreToolUse` never reaches `PostToolUse`, so a
  prompt is the closest observable signal for a refused tool call; that asymmetry is why `git-guardrails.sh`
  calls the recorder directly instead of being detected.

`record-denial.sh` resolves the log location with `git rev-parse --show-toplevel` from the payload's
`.cwd` (falling back to `.cwd` itself), so events from a subdirectory still land at the repo root, and
it creates `.sbx/.gitignore` containing `*` on first write — this is sandbox-local audit output, not
repo content. Writes are serialised with `flock` on `.sbx/.lock`, since append + summary rebuild must
not interleave between two sessions in the same workspace. Both scripts exit 0 on every failure path
(missing `jq`, unparseable payload, unwritable directory): an audit hook must never disturb a session,
and a non-zero `PostToolUse` exit would feed noise back to the model.

Host-side ground truth for network denials is `sbx policy log <sandbox>` (host, rule, reason, count) —
the in-sandbox hook can't read it because `sbx` isn't in the sandbox, which is why detection is done on
tool output instead.

## Conventions in this codebase

- Bash, `set -euo pipefail` at the top of scripts.
- Small `title`/`ok`/`run`/`warn`/`error` printf helpers for colored, structured CLI output — reuse
  these rather than inlining new ANSI escapes in `sbxc.sh`.
- Idempotency is done ad hoc: `setting_is` / grep-ing `sbx secret ls` / `sandbox_exists` checks before
  each optional step, so re-running against an already-configured host stays silent.
- `sbx` seeds the sandbox's git identity itself: at create it writes `/home/agent/.gitconfig` with
  `user.name` / `user.email` copied from the host's global config, plus `core.excludesFile`,
  `core.checkStat` and a `safe.directory` for the workspace (verified on v0.38.0 in a bare sandbox
  created with no kits). So `sbxc.sh` has no git-identity step — don't add one back. Credential
  helpers are *not* copied, which is what the `github` secret covers.
- The kit spec's top-level key is `setup:` (v0.38.0). It was `commands:` in v0.37.0 and the YAML
  parser is strict — an outdated key fails `sbx create` with
  `field commands not found in type spec.specFileV2`, and unknown nested keys fail the same way.
  Run `sbx kit validate <kit-dir>` after touching a `spec.yaml`; it names the offending line.
- Everything here is validated against a specific `sbx` CLI version (currently v0.38.0, noted in
  README's Gotchas section) rather than derived from `sbx`'s own docs — if `sbx` behavior seems to
  contradict a comment, assume the comment is the more reliable source and flag the discrepancy
  rather than silently "fixing" it.
