# sclaude

Thin wrapper over `sbx run`: launches Claude Code in the sandbox for the current directory, applying
this repo's kits when that sandbox is created. `sclaude` is self-contained — it fetches the kits from
this repo's `master` over git, so a kit change takes effect on the next sandbox created _after_ it is
pushed.

| Kit                       | Adds                                                                 |
| ------------------------- | -------------------------------------------------------------------- |
| `shell-prompt-kit`        | powerline `PS1` (`SBX`, sandbox name, cwd)                           |
| `statusline-kit`          | statusline: cwd, branch, model, context %, rate limit, session cost  |
| `git-guardrails-kit`      | `PreToolUse` hook blocking destructive git commands                  |
| `denied-access-stats-kit` | logs refused access to `<repo>/.sbx/access-denials.md`               |
| `claude-config-kit`       | settings (recap off, default TUI, opus), global `CLAUDE.md`, plugins |

## Install

Needs `sbx` and `jq` on the host (plus `gh`, for the last setting below), and git access to this repo
(sbx fetches the kits with the host's credentials, so a private repo works).

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

## Audit

`<repo>/.sbx/access-denials.md` counts each refused target and ends with the `sbx policy allow
network` commands to grant them. Host-side ground truth is `sbx policy log <sandbox>`.

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

## Credentials

Every sandbox uses the global Anthropic subscription; `sbx secret set anthropic --sandbox <sandbox>`
gives one its own API key instead. A second _subscription_ can't be scoped that way — sbx stores OAuth
secrets globally only.
