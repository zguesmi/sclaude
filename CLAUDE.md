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
```

A "kit" is an `sbx` mixin: a `spec.yaml` with `install` commands (run once, at sandbox creation) plus
an optional `files/` tree that gets copied verbatim into the sandbox's home directory. `sbxc.sh`
always loads `shell-prompt-kit` and `statusline-kit` from its own directory at creation time —
there's no caller-supplied `--kit` passthrough; all of `sbxc`'s CLI args go to `claude` instead (see
below).

## Running / testing changes

There's no local test runner — the only way to validate a change is to actually create/refresh a
sandbox with `sbx` and inspect the result:

```shell
./sbxc.sh                 # from a project directory; creates/enters "claude-<dirname>"
sbx exec -it <name> bash  # re-enter an existing sandbox without re-running setup
sbx kit add <name> <path-to-kit>   # apply a kit to an existing sandbox (restarts, preserves VM state)
```

Sandbox naming: `claude-<basename-of-cwd>`, non-alphanumeric characters in the basename replaced with `-`.

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
   appends to it (git identity) rather than overwriting, since multiple install steps and kits share
   this one file. This is also why shell completion scripts must never be appended here (they
   reference `COMP_WORDS`/`COMPREPLY`, which don't exist outside an actual completion context, and
   sourcing them on every command breaks bash entirely).
2. `~/.claude/settings.json` — must be merged via `jq`, never overwritten, since more than one kit
   (or the user) may set different top-level keys. `statusline-kit` does `jq '.statusLine = {...}'`
   into a temp file in the same directory, then `mv`s it over the original for an atomic replace.

**Ordering constraints that matter when editing a kit's `spec.yaml`:**
- A mixin's `install` commands run *after* the agent's own seeding — that's why a `jq` merge done in
  `install` survives, while static `files/` / `initFiles` placed at the same path do not (those are
  applied earlier and get clobbered by the agent's own seed).
- `install` commands run *before* `files/` is copied in. A kit's install script cannot `chmod` or
  otherwise touch a file it ships in `files/` — set the executable bit in the file's own mode instead.

**`sbxc.sh` control flow** (`main()` at the bottom): check if the sandbox already exists
(`sandbox_exists`, via `sbx ls`) → if new, run host config, GitHub token provisioning, `sbx create`
(with the two bundled kits baked into the call), and git identity injection, in that order → always
end by `exec`-ing into `sbx run --name <name> -- "$@"` (`run_sandbox`), which forwards every argument
`sbxc` was called with straight through to the agent. If the sandbox already exists, all setup is
skipped entirely and it goes straight to launching Claude — setup is one-shot per sandbox, not
idempotently re-applied on every invocation.

`sbxc` lands you directly in Claude Code, not a shell — `sbxc -r` becomes `claude -r`, `sbxc agents`
becomes `claude agents`, and so on; running plain `sbxc` again against the same project just starts
another Claude session in the same sandbox. For a plain shell (e.g. to run other commands), use
`sbx exec -it <name> bash` directly — `shell-prompt-kit` is still installed by default so that shell
gets the powerline prompt, even though it's no longer where `sbxc` lands you.

**Statusline script** (`statusline-kit/files/home/.claude/statusline.sh`) reads Claude Code's
statusline JSON payload from stdin and renders: cwd basename, git branch, model + effort, context
window usage %, 5-hour rate-limit usage, session cost, and an optional "caveman" plugin badge (driven
by flag files under `~/.claude/`, unrelated to this repo — read defensively, don't assume that plugin
exists).

## Conventions in this codebase

- Bash, `set -euo pipefail` at the top of scripts.
- Small `title`/`ok`/`run`/`warn`/`error` printf helpers for colored, structured CLI output — reuse
  these rather than inlining new ANSI escapes in `sbxc.sh`.
- Idempotency is done ad hoc: `setting_is` / grep-ing `sbx secret ls` / `sandbox_exists` checks before
  each optional step, so re-running against an already-configured host stays silent.
- Everything here is validated against a specific `sbx` CLI version (currently v0.37.0, noted in
  README's Gotchas section) rather than derived from `sbx`'s own docs — if `sbx` behavior seems to
  contradict a comment, assume the comment is the more reliable source and flag the discrepancy
  rather than silently "fixing" it.
