# CLAUDE.md

Host wrapper around `sbx`: one bash script, four kit specs. No build, no tests. See README.md.

Validate by creating a sandbox. `sbx kit validate <kit-dir>` checks a spec. Notes below are verified
against **sbx v0.38.0** — if `sbx` contradicts one, flag it, don't silently fix it.

## Wrapper

- Job is the kit list and the account. Delete features rather than reimplement `sbx`. `"$@"` reaches
  `sbx run` unparsed; don't route flags host-side — that is why the account is an env var, not a flag.
- `sbx run` resolves by *name*, defaulting to `<agent>-<workdir>` — **not** by which sandbox already
  holds the workspace. Omit `--name` and it builds a second, unsuffixed sandbox next to ours (seen:
  `claude-tmp.X` and `claude-tmp.X-personal` sharing one workspace). So `--name` goes on both paths,
  and existence is tested on the name, not the workspace.
- `--kit` is rejected on an existing sandbox, so only kits are conditional. Hence `set --` prepends
  them, then one `exec`. Don't use an array emptied on one path: empty `"${arr[@]}"` under `set -u`
  breaks bash 3.2 (macOS).
- Kits must be `git+<repo>#ref=master&dir=<kit>`. Other git syntaxes hit the OCI puller and fail. A kit
  edit only reaches new sandboxes once pushed.
- Kit prefixes need `kit.allowedSources`. It is shared — never drop entries.
- `sbx` seeds `/home/agent/.gitconfig`; add no git-identity step. It skips credential helpers — that's
  the global `github` secret.

## Accounts

- The account is the sandbox name suffix, `claude-<dir>-<account>`. `sbx` is write-only, so `sbx ls`
  is the only record of it. The prompt therefore runs on *every* run — the name has to be rebuilt to
  attach. Only the keyring read is create-only.
- The secret must exist *before* creation: the env var is injected then and never again. Storing
  against a running sandbox updates the proxy mapping but adds no env var, whatever the CLI prints.
- The menu is `ACCOUNTS`; adding one means that array plus its keyring entry. The answer is matched
  whole against the index or the name — no pattern, so a typo re-asks instead of resolving.
- Existence is read once into a space-padded string and matched with `*" $account "*`; it drives both
  the default and create-vs-attach. Unpadded, `work` would match a `workspace` suffix.
- The menu goes to stderr, the chosen name to stdout — `select_account` is captured in `$(...)`, and
  stdout past the `exec` belongs to Claude. No tty is fatal: nothing may pick an account silently.
- Always `--sandbox`. A global anthropic secret forces api-key mode, which seeds an `apiKeyHelper` and
  kills the claude.ai MCP connectors — `sclaude` refuses to run at all while one exists.
- `set-custom` upserts on `--placeholder`. Omit it for a fresh mapping; pass one back only after
  reading it from `sbx secret ls --sandbox <name>`, matched on a whole field. A substring match would
  hand over a sibling's placeholder and silently overwrite it.
- The sandbox only ever sees the `sbx-cs-…` placeholder. Never inject the real token.
- Token reaches `sbx` through a `printf` builtin pipe: not argv, not exported, not a file. Keep it
  that way — no `--value`, no temp file, no `export`.
- Keyring reads happen on the create path only. A dedicated collection is used rather than `login`
  so it starts locked at login; `sclaude` does not relock it.
- `secret-tool` looks items up by *attribute* (`service sclaude account <name>`), not by label.
  Seahorse can create the collection but cannot set attributes, so enrolment needs the CLI.
- `store` accepts `--collection` even though its usage line omits it (verified, libsecret 0.21.7), but
  only as an alias or a D-Bus object path — `--collection=sclaude` fails on
  `/org/freedesktop/secrets/aliases/sclaude`. Hence `KEYRING_PATH`; its last segment is the keyring
  filename, not the Seahorse label. `secret-tool lock --collection=<path>` relocks, no `gdbus` needed.

## Kits

- Top-level key is `setup:`. Unknown keys fail `sbx create`.
- `install` runs after the agent seeds its files, so a `jq` merge survives and static `files/` does not.
  It also runs before `files/` is copied, so it cannot `chmod` a shipped file.
- `files/` lands mode 644 whatever the mode in git. A shipped script is therefore never executable, and
  nothing in the kit can make it so. Register it as `/bin/bash <path>`, never as the bare path — run
  directly it is `Permission denied`, which Claude Code reports as no statusline and as a hook that
  silently guards nothing. Dedup a re-registered hook on the script path, not the command string, or
  the bare-path entry from an older revision survives beside the new one.
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

Wrapper output borrows `sbx`'s glyphs (`→` step, `✓` result, `✗` failure) but prefixes a coral
`[sclaude]` tag flush left, so the two logs stay tellable apart in one scrollback. `log()` wraps the
message in grey; values inside it are `$WHITE` and return to `$GREY` after, so a line reads as a
shape before it reads as words. Everything goes to stderr and drops colour off a tty; every line
after the first — menu entries, wrapped errors — indents by `$INDENT`, four spaces. `sbx secret set-custom` narrates in
three lines — capture it and show it only when it fails. The statusline reads only the account out of
`claude-<dir>-<account>` and renders it as `[SBX] <Account>`, the account bare and bold in its own
hue behind the badge; an unknown suffix leaves `[SBX]` standing alone. The name itself is never shown
— `<dir>` is the workspace directory, which the line already carries. It never measures the terminal,
so the two unbounded segments are capped instead: dir 24 (`.../` prefix, whole components only),
branch 20 (`...` suffix), both overridable with `SBX_STATUSLINE_MAX_DIR` and
`SBX_STATUSLINE_MAX_BRANCH`. Ellipses are ASCII, not
`…`, so a cropped name never reads as one character.
