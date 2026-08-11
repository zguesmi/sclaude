# sbx claude setup

Automates the post-install configuration of a Claude Code sandbox, so no manual setup is needed.
A sandbox is created and Claude is launched directly in it by default.

- **`sbxc.sh`** — host wrapper. Creates the sandbox if missing, configures it, launches Claude.
- **`shell-prompt-kit/`** — kit that ships the powerline shell prompt, for when you drop into a plain shell instead.
- **`statusline-kit/`** — kit that ships the Claude Code statusline and registers it at sandbox creation.
- **`git-guardrails-kit/`** — kit that ships a `PreToolUse` hook blocking destructive git commands.
- **`access-audit-kit/`** — kit that logs every denied access into `<repo>/.sbx/access-denials.md`.

## Layout

```text
├── sbxc.sh                     host wrapper
├── shell-prompt-kit/
│   └── spec.yaml               kit spec, appends PS1 to /etc/sandbox-persistent.sh at install
├── statusline-kit/
│   ├── spec.yaml               kit spec, registers statusLine at install
│   └── files/home/.claude/
│       └── statusline.sh       → /home/agent/.claude/statusline.sh
├── git-guardrails-kit/
│   ├── spec.yaml               kit spec, registers the PreToolUse hook at install
│   └── files/home/.claude/hooks/
│       └── git-guardrails.sh   → /home/agent/.claude/hooks/git-guardrails.sh
└── access-audit-kit/
    ├── spec.yaml               kit spec, registers PostToolUse + Notification hooks at install
    └── files/home/.claude/hooks/
        ├── access-audit.sh     → detects denials in tool results and permission prompts
        └── record-denial.sh    → writes <repo>/.sbx/access-denials.{jsonl,md}
```

## Destructive git guard

`git-guardrails-kit` registers `git-guardrails.sh` as a Claude Code `PreToolUse` hook on `Bash`. It reads the
command from the hook payload and exits 2 (block, reason handed back to the model) when it matches:

`push --force` without `--force-with-lease`, `push --mirror/--delete/:branch`, `reset --hard`,
`clean -f`, `checkout -- <path>` / `checkout .`, `restore <path>` (bare `--staged` is allowed),
`switch --discard-changes`, `branch -D`, `stash drop/clear`, `reflog expire`, `gc --prune`,
`update-ref -d`, `filter-branch`/`filter-repo`, `worktree remove --force`.

Everything else, including a malformed payload or a missing `jq`, exits 0 — a broken hook must never
wedge the sandbox's shell access. Matching is textual on the whole command string, so a command that
merely *mentions* one of these (e.g. `git log --grep 'reset --hard'`) is blocked too.

Turn it off in one sandbox from the host:

```shell
sbx exec <sandbox> -- touch /home/agent/.claude/.git-guardrails-off
```

It is an accident guard, not a security boundary: the agent can create that file itself.

## Denied access audit

`access-audit-kit` records what the sandbox refused, so you can decide what to grant instead of
guessing. Two hooks, both silent and always exit 0:

| Event                            | Catches                                                            |
| -------------------------------- | ------------------------------------------------------------------ |
| `PostToolUse` (Bash/WebFetch/…)  | sbx proxy denials — `Blocked by network policy: domain host:port`  |
| `Notification`                   | Claude Code permission prompts                                     |
| (direct call)                    | `git-guardrails-kit` blocks, reported by that hook itself          |

Output lands in the workspace, at the git root:

```text
<repo>/.sbx/access-denials.jsonl   one JSON object per event
<repo>/.sbx/access-denials.md      counts per target + the commands to grant them
<repo>/.sbx/.gitignore             "*", created on first write — this is not repo content
```

`access-denials.md` ends with ready-to-run host commands, e.g.:

```shell
sbx policy allow network --sandbox claude-my-project "registry.npmjs.org:443"
```

For network denials the host-side ground truth is the proxy's own log — the in-sandbox hook cannot
read it, since `sbx` is not installed in the sandbox:

```shell
sbx policy log <sandbox>
```

A call blocked at `PreToolUse` never reaches `PostToolUse`, so tool calls Claude Code refuses itself
show up as permission *prompts* rather than as denials. Network blocks are exact.

## Install

Clone the repo and symlink the script onto your PATH:

```shell
git clone <this-repo> ~/.local/share/sbxc
ln -s ~/.local/share/sbxc/sbxc.sh ~/.local/bin/sbxc
command -v sbxc || echo 'add ~/.local/bin to PATH in your shell rc'
```

## Usage

```shell
cd ~/my-project
sbxc
```

The sandbox is named `claude-<directory>` and `shell-prompt-kit/`, `statusline-kit/`,
`git-guardrails-kit/` and `access-audit-kit/` are applied at creation. Every argument is forwarded straight
through to `claude` (via `sbx run -- ...`):

```shell
sbxc -r        # -> claude -r
sbxc agents    # -> claude agents
```

A `--` in `sbxc`'s own args splits that from a second group forwarded to
`sbx create` instead — only meaningful the first time, while the sandbox is
still being created:

```shell
sbxc -r -- --kit /path/to/other-kit   # claude -r, plus an extra kit at create time
```

If the sandbox already exists, setup is skipped and you go straight to Claude.

You land directly in **Claude Code**, launched with `--dangerously-skip-permissions`.
Running `sbxc` again reuses the same sandbox and starts another Claude session in it.

If you want a plain shell instead (e.g. to run other commands), open one manually:

```shell
sbx exec -it <sandbox-name> bash
```

## What it does

On a **new** sandbox, `sbxc.sh` runs these steps (steps already satisfied stay silent):

| Step                | How                                                                              |
| ------------------- | -------------------------------------------------------------------------------- |
| Image paste allowed | `sbx settings set clipboard.imagePaste true`                                     |
| Local kits allowed  | `sbx settings set kit.allowLocalKits true`                                       |
| GitHub over HTTPS   | `gh auth token \| sbx secret set -g github`                                      |
| Git identity        | `git config --global user.{name,email}` appended to `/etc/sandbox-persistent.sh` |
| Shell prompt        | powerline `PS1` with: `SBX`, sandbox name, cwd                                    |

`/etc/sandbox-persistent.sh` is sourced before every bash invocation in the
sandbox.

The statusline is the kit's job rather than the script's, so it travels with the
kit and applies to any sandbox that loads it.

Its cwd segment is shortened when long: `$HOME` → `~`, then leading components are dropped until the
path fits, keeping the deepest ones (`…/Obsidian/personal-obsidian-vault`). The limit is 32 characters,
override with `SBX_STATUSLINE_MAX_DIR`.

## Gotchas

Verified against `sbx v0.38.0`, not inferred from the docs.

- **The kit spec's top-level key is `setup:`, not `commands:`** — v0.38.0 renamed it and the parser
  is strict, so a v0.37.0 spec fails sandbox creation outright with
  `field commands not found in type spec.specFileV2`. Nesting is unchanged:
  `setup.install[].{description,command,user}`. `sbx kit validate <dir>` reports the exact offending
  line, and it rejects unknown nested fields too.

- **`~/.claude/settings.json` must be _merged_, never overwritten** — the kit does a `jq` merge.
- **A mixin's install commands run after the agent's own**, which is where that
  seeding happens — so an install-time merge survives. Static `files/` and
  `initFiles` at that path do *not*: they're applied earlier and get overwritten.
- **Install commands run before `files/` is copied in**, so they can't `chmod` or
  read a kit-shipped file. Ship the executable bit in the file's own mode instead.
