# CLAUDE.md

Host wrapper around `sbx`: one bash script, four kit specs. No build, no tests. See README.md.

Validate by creating a sandbox. `sbx kit validate <kit-dir>` checks a spec. Notes below are verified
against **sbx v0.38.0** — if `sbx` contradicts one, flag it, don't silently fix it.

## Wrapper

- Job is the kit list. Delete features rather than reimplement `sbx`. `"$@"` reaches `sbx run`
  unparsed; don't route flags host-side.
- `sbx` resolves sandboxes by *workspace*. Never pass `--name`.
- `--kit` is rejected on an existing sandbox. Hence `set --` prepends kits, then one `exec`. Don't use
  an array emptied on one path: empty `"${arr[@]}"` under `set -u` breaks bash 3.2 (macOS).
- Kits must be `git+<repo>#ref=master&dir=<kit>`. Other git syntaxes hit the OCI puller and fail. A kit
  edit only reaches new sandboxes once pushed.
- Kit prefixes need `kit.allowedSources`. It is shared — never drop entries.
- `sbx` seeds `/home/agent/.gitconfig`; add no git-identity step. It skips credential helpers — that's
  the global `github` secret.

## Kits

- Top-level key is `setup:`. Unknown keys fail `sbx create`.
- `install` runs after the agent seeds its files, so a `jq` merge survives and static `files/` does not.
  It also runs before `files/` is copied, so it cannot `chmod` a shipped file.
- Steps run under `sh`. `<<<` is a parse error and its exit 2 aborts `sbx create`. Step stdout is
  hidden; write a file and `sbx exec … cat` it.
- `~/.claude/settings.json` is shared by three kits: `jq` to a temp file in the same dir, then `mv`.
  Never overwrite. Hook kits append to `.hooks.<Event>` after dropping their own script's entry.
- `/etc/sandbox-persistent.sh` is shared and sourced before every bash: append only. Never completion
  scripts — `COMP_WORDS`/`COMPREPLY` break every shell.

## Claude config

- Install plugins with the CLI. `enabledPlugins` alone leaves them uninstalled.
- Add every marketplace explicitly, `claude-plugins-official` included: Claude registers it on first
  *interactive* start, which a new sandbox never had. A live sandbox lists it only because a session ran.
- `claude` is on PATH in an install step.
- Loops guard on `--json` (`.[].repo`, `.[].id`) and are best-effort: an outage costs a plugin, not the
  sandbox. The settings merge is strict and runs first, since `plugin install` rewrites its own keys.

## Hooks

- `git-guardrails.sh` (`PreToolUse`, Bash) `exit 2`s to block. Every other path exits 0 — a broken hook
  must not cut off shell access. `~/.claude/.git-guardrails-off` disables it. Patterns use `[^;&|]*` so
  no match spans chained commands.

## Conventions

Bash, `set -euo pipefail`. The kit list is explicit, not globbed.
