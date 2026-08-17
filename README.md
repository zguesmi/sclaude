# sclaude

Thin wrapper over `sbx run`: launches Claude Code in the sandbox for the current directory, applying
this repo's kits and an explicitly chosen Claude account when that sandbox is created. `sclaude` is
self-contained — it fetches the kits from this repo's `master` over git, so a kit change takes effect
on the next sandbox created _after_ it is pushed.

| Kit                  | Adds                                                                     |
| -------------------- | ------------------------------------------------------------------------ |
| `shell-prompt-kit`   | powerline `PS1` (`SBX`, sandbox name, cwd)                               |
| `statusline-kit`     | statusline: sandbox + account, cwd, branch, model, context %, rate limit |
| `git-guardrails-kit` | `PreToolUse` hook blocking destructive git commands                      |
| `claude-config-kit`  | settings (recap off, default TUI, opus), global `CLAUDE.md`, plugins     |

## Install

Needs `sbx`, `jq` and `secret-tool` (`libsecret-tools`) on the host, plus `gh` for the last setting
below, and git access to this repo (sbx fetches the kits with the host's credentials, so a private
repo works).

```shell
curl -fsSL https://raw.githubusercontent.com/zguesmi/sclaude/master/sclaude -o ~/.local/bin/sclaude
chmod +x ~/.local/bin/sclaude
```

Then three host-wide `sbx` settings, once per machine. They are yours to run, not wrapped by `sclaude`:

```shell
# Add github repo as kits source
sbx settings set kit.allowedSources '["docker.io/","github.com/zguesmi/"]'

# Paste images into Claude from the host clipboard.
sbx settings set clipboard.imagePaste true

# Provide a GitHub auth token to sbx sandboxes.
gh auth token | sbx secret set -g github
```

Check them with `sbx settings get ...` and `sbx secret ls`.

## Usage

Every run opens with the account menu; the answer picks the sandbox:

```shell
[sclaude]  →  select Claude account
    1. personal (sandbox exists)
    2. work
    [personal] > _
```

Answer with the number or the name. When exactly one of the two sandboxes exists for the directory
its account is the default, shown in brackets and taken by a bare Enter; with none or both there is
no default. Anything else re-asks, and a run with no terminal fails instead of guessing.

Arguments go to `sbx run` verbatim; Claude's own go after `--`.

```shell
sclaude                      # claude here, creating the sandbox on first run
sclaude -- -r                # claude -r
sclaude --kit /path/to/kit   # extra kit, only when creating
sclaude /path/to/docs:ro     # extra read-only workspace
```

Kits apply at creation only; add one to a live sandbox with `sbx kit add <sandbox> <kit>`.

## Guardrails

Blocked: `push --force`/`-f`/`--force-with-lease`/`--force-if-includes`, `push --mirror/--delete/:branch`,
`reset --hard`, `clean -f`, `checkout -- <path>`, `restore <path>`, `switch --discard-changes`,
`branch -D`, `stash drop/clear`, `reflog expire`, `gc --prune`, `update-ref -d`,
`filter-branch`/`filter-repo`, `worktree remove --force`. Matching is textual on the whole command, so
`git log --grep 'reset --hard'` is blocked too.

An accident guard, not a security boundary — turn it off with:

```shell
sbx exec <sandbox> -- touch /home/agent/.claude/.git-guardrails-off
```

## Skills

`claude-config-kit` registers both marketplaces (`anthropics/claude-plugins-official` and
`juliusbrussee/caveman` — a fresh sandbox knows neither) and installs `superpowers`,
`mattpocock-skills` and `caveman` with `claude plugin install` at creation. Add one by editing the
two lists in the kit; every step is skipped when already present, and installs are best-effort, so a
marketplace outage costs you a plugin, not the sandbox.

It also ships `/home/agent/.claude/CLAUDE.md`, a project's own `CLAUDE.md` still applies on top of it.

Project-specific skills belong in the project's own `.claude/skills/<name>/SKILL.md`, committed with
its code: the workspace is bind-mounted, so the sandbox picks them up with nothing installed. Loose
host skills in `~/.claude/skills` reach the sandbox through sbx's own store — `sbx skills import`
copies them in, and the store is mounted read-write at `/home/agent/.claude/skills` in _every_
sandbox.

## Accounts

Each sandbox authenticates as one Claude account, chosen at the prompt. `personal` and `work` are the
only two offered. The account is part of the sandbox name — `claude-<dir>-<account>` — so `sbx ls` is
the only record of which account a sandbox belongs to. There is no state file to lose.

The prompt therefore runs on **every** run, not just the first: `sbx run` resolves a sandbox by name,
so the name has to be rebuilt each time to attach to the right one. Answering with the other account
in a directory that already has one builds a second sandbox rather than switching the first.

Create the keyring once, in Seahorse (_Passwords and Keys_): **+** → **Password Keyring**, named
`sclaude`. Then enroll each account. `sclaude` never writes the token; it prints these two commands
when the keyring has no entry:

```shell
claude setup-token
secret-tool store --collection=/org/freedesktop/secrets/collection/sclaude \
  --label='sclaude - personal' service sclaude account personal
```

`--collection` takes a D-Bus object path or an alias, never the label Seahorse shows — passing
`sclaude` fails with `Object does not exist at path “/org/freedesktop/secrets/aliases/sclaude”`. The
last path segment is the keyring **filename**; check it with `ls ~/.local/share/keyrings/`.

The item is found by its attributes (`service sclaude account personal`), not by its label, which is
why it has to be created from the CLI — Seahorse can make the keyring but cannot set attributes.

The token lives in a dedicated `sclaude` keyring collection rather than `login`, so it starts locked
at login instead of being auto-unlocked. `sclaude` reads it only when creating a sandbox; attaching to
an existing one never touches the keyring. Close it again before logout with:

```shell
secret-tool lock --collection=/org/freedesktop/secrets/collection/sclaude
```

The sandbox never sees the token. `sbx` stores it as a sandbox-scoped custom secret and hands the
sandbox a `sbx-cs-…` placeholder; the proxy substitutes the real value on requests to
`api.anthropic.com`. Verify with:

```shell
sbx exec <sandbox> printenv CLAUDE_CODE_OAUTH_TOKEN   # sbx-cs-…, never the token
sbx exec <sandbox> printenv SBX_CRED_ANTHROPIC_MODE   # none
sbx exec <sandbox> grep -c apiKeyHelper /home/agent/.claude/settings.json   # 0
```

A **global** anthropic secret would force api-key mode, which seeds an `apiKeyHelper` and disables the
claude.ai MCP connectors. `sclaude` refuses to create a sandbox while one exists.

The env var is injected at creation and nothing later can change it, so a sandbox keeps its account
for life. Switching accounts in a directory just means answering with the other one, which builds a
second sandbox. Renewing a token means removing the sandbox so it is rebuilt with the new one:

```shell
sbx rm claude-<dir>-personal && sclaude
```

Removing an account's secret is keyed on the placeholder, and touches only that sandbox:

```shell
sbx secret ls --sandbox claude-<dir>-personal                             # read PLACEHOLDER
sbx secret rm --sandbox claude-<dir>-personal --placeholder sbx-cs-… -f
secret-tool clear service sclaude account personal                        # only to retire the account
```

Sandboxes named `claude-<dir>` with no suffix predate this and `sclaude` no longer reaches them —
it only ever resolves the suffixed name. Reach one with `sbx run claude . --name claude-<dir>`, or
`sbx rm` it and let `sclaude` rebuild it.
