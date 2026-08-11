# sbxc

Thin wrapper over `sbx run`: launches Claude Code in the sandbox for the current directory, applying
this repo's kits when that sandbox is created. `sbxc.sh` is self-contained — it fetches the kits from
this repo's `master` over git, so a kit change takes effect on the next sandbox created *after* it is
pushed.

| Kit                  | Adds                                                                  |
| -------------------- | --------------------------------------------------------------------- |
| `shell-prompt-kit`   | powerline `PS1` (`SBX`, sandbox name, cwd)                            |
| `statusline-kit`     | statusline: cwd, branch, model, context %, rate limit, session cost   |
| `git-guardrails-kit` | `PreToolUse` hook blocking destructive git commands                   |
| `access-audit-kit`   | logs refused access to `<repo>/.sbx/access-denials.md`                |

## Install

Needs `sbx`, `jq`, and `gh` on the host, plus git access to this repo (sbx fetches the kits with the
host's credentials, so a private repo works).

```shell
curl -fsSL https://raw.githubusercontent.com/zguesmi/sbx-test/master/sbxc.sh -o ~/.local/bin/sbxc
chmod +x ~/.local/bin/sbxc
sbxc setup   # host-wide sbx settings + the github secret, once per machine
```

`sbxc setup` appends `github.com/zguesmi/` to `kit.allowedSources`, without which sbx refuses the kits.

## Usage

Arguments go to `sbx run` verbatim; Claude's own go after `--`.

```shell
sbxc                      # claude here, creating the sandbox on first run
sbxc -- -r                # claude -r
sbxc --kit /path/to/kit   # extra kit, only when creating
sbxc /path/to/docs:ro     # extra read-only workspace
```

Kits apply at creation only; add one to a live sandbox with `sbx kit add <sandbox> <kit>`.

## Guardrails

Blocked: `push --force` (without `--force-with-lease`), `push --mirror/--delete/:branch`,
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

## Credentials

Every sandbox uses the global Anthropic subscription; `sbx secret set anthropic --sandbox <sandbox>`
gives one its own API key instead. A second *subscription* can't be scoped that way — sbx stores OAuth
secrets globally only.
