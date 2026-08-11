# CLAUDE.md

Host-side wrapper around the `sbx` CLI. Bash scripts plus four `sbx` kit specs — no build, no tests,
no package manager. See README.md for what each kit does and how `sbxc` is invoked.

Validate a change by actually creating a sandbox; `sbx kit validate <kit-dir>` checks a spec and names
the offending line. Everything below is verified against **sbx v0.38.0**, not derived from its docs —
if `sbx` seems to contradict a note here, flag the discrepancy rather than silently "fixing" it.

## Wrapper invariants

- The wrapper's whole job is the kit list plus `sbxc setup`. Prefer deleting a feature over
  reimplementing what `sbx` does; `"$@"` is forwarded to `sbx run` unparsed, deliberately — host-side
  flag routing would mean tracking `sbx`'s flag list.
- `sbx` owns sandbox naming (`<agent>-<workdir>`) and resolves by *workspace*. Never pass `--name` or
  re-derive one: `sandbox_exists()` asks `sbx ls --json` whether a `claude` sandbox lists `$PWD`.
- `--kit` is rejected on an existing sandbox, which is the only reason the wrapper branches at all.
- Kits are remote git references, `git+<repo>#ref=master&dir=<kit>` — the only syntax v0.38.0 accepts
  for git (plain `https://…//subdir`, `git::…`, and `git@…` all fall through to the OCI puller and
  fail). So `sbxc.sh` is self-contained, and a kit edit only reaches a new sandbox once pushed.
- Remote kits need their prefix in `kit.allowedSources` (default `["docker.io/"]`); `setup()` merges
  `github.com/zguesmi/` in rather than assigning, since the list is shared.
- `sbx` seeds `/home/agent/.gitconfig` (identity, `core.excludesFile`, `core.checkStat`,
  `safe.directory`) at create — don't add a git-identity step back. It does *not* copy credential
  helpers; that's what the `github` secret in `setup()` covers.
- Launch path prints nothing and has no output helpers; `setup()` uses plain `echo`.

## Kit invariants

- Top-level spec key is `setup:` (was `commands:` in v0.37.0). The parser is strict — an outdated or
  unknown key fails `sbx create` outright.
- `install` runs *after* the agent seeds its own files, so a `jq` merge there survives; static
  `files/`/`initFiles` at the same path do not. `install` also runs *before* `files/` is copied, so it
  cannot `chmod` a file the kit ships — set the mode on the file itself.
- `~/.claude/settings.json` is shared by three kits: merge with `jq` into a temp file and `mv`, never
  overwrite. Hook kits must *append* to `.hooks.<Event>` after dropping any entry pointing at their own
  script, so re-applying a kit can't stack duplicates.
- `/etc/sandbox-persistent.sh` is sourced before every bash invocation and shared by all kits: append,
  never overwrite. Never append completion scripts — they reference `COMP_WORDS`/`COMPREPLY` and break
  every shell.

## Hook invariants

- `git-guardrails.sh` (`PreToolUse` on Bash) `exit 2`s to block, stderr going back to the model.
  Every other path, including missing `jq` or unparseable JSON, exits 0: a broken hook must not cut off
  shell access. `~/.claude/.git-guardrails-off` short-circuits it. Patterns use `[^;&|]*` so a match
  can't span chained commands.
- `access-audit.sh` branches on `.hook_event_name`. `PostToolUse` greps
  `Blocked by <word> policy: <word> <resource>` out of the tool result — that's the sbx proxy's 403 body.
  `Notification` catches permission prompts, the closest signal for calls blocked at `PreToolUse`, which
  never reach `PostToolUse`; that asymmetry is why `git-guardrails.sh` calls `record-denial.sh` directly,
  wrapped in `[ -x ... ] && ... || true` so the two kits stay independent.
- `record-denial.sh` resolves the log path with `git rev-parse --show-toplevel` from the payload's
  `.cwd`, serialises with `flock`, and writes `.sbx/.gitignore` containing `*` — this is sandbox-local
  output, not repo content. Both audit scripts exit 0 on every failure path.

## Conventions

Bash, `set -euo pipefail`. Idempotency ad hoc (`setting_is`, grepping `sbx secret ls`). The kit list is
explicit, not globbed, so a stray directory can't become a kit.
