# sbx claude setup

Automates the post-install configuration of a Claude Code sandbox, so no manual setup is needed.
A sandbox is created and a shell is opened by default so Claude commands could be run as wished.

- **`sbxc.sh`** — host wrapper. Creates the sandbox if missing, configures it, opens a shell.
- **`statusline-kit/`** — kit that ships the Claude Code statusline and registers it at sandbox creation.

## Layout

```text
├── sbxc.sh                     host wrapper
└── statusline-kit/
    ├── spec.yaml               kit spec, registers statusLine at install
    └── files/home/.claude/
        └── statusline.sh       → /home/agent/.claude/statusline.sh
```

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

The sandbox is named `claude-<directory>` and `statusline-kit/` is applied by
default. Every argument is forwarded straight to `sbx create`, so extra mounts
work too:

```shell
sbxc ../docs:ro                   # extra read-only mount
sbxc --kit /path/to/other-kit     # adds to the default kit
```

If the sandbox already exists, setup is skipped and you go straight to the shell.

You land in a **shell**, not in Claude Code. That's deliberate: you decide when to
start `claude`, can run it more than once, and keep using the same sandbox for
the same project. The `claude` command is wrapped so it always carries
`--dangerously-skip-permissions`.

## What it does

On a **new** sandbox, `sbxc.sh` runs these steps (steps already satisfied stay silent):

| Step                | How                                                                              |
| ------------------- | -------------------------------------------------------------------------------- |
| Image paste allowed | `sbx settings set clipboard.imagePaste true`                                     |
| Local kits allowed  | `sbx settings set kit.allowLocalKits true`                                       |
| GitHub over HTTPS   | `gh auth token \| sbx secret set -g github`                                      |
| Git identity        | `git config --global user.{name,email}` appended to `/etc/sandbox-persistent.sh` |
| Claude bypass mode  | `claude()` function adding `--dangerously-skip-permissions`                      |
| Shell prompt        | powerline `PS1` with: `SBX`, sandbox name, cwd                                    |

`/etc/sandbox-persistent.sh` is sourced before every bash invocation in the
sandbox — that's what makes the last three persist.

The statusline is the kit's job rather than the script's, so it travels with the
kit and applies to any sandbox that loads it.

## Gotchas

Verified against `sbx v0.37.0`, not inferred from the docs.

- **`~/.claude/settings.json` must be _merged_, never overwritten** — the kit does a `jq` merge.
- **A mixin's install commands run after the agent's own**, which is where that
  seeding happens — so an install-time merge survives. Static `files/` and
  `initFiles` at that path do *not*: they're applied earlier and get overwritten.
- **Install commands run before `files/` is copied in**, so they can't `chmod` or
  read a kit-shipped file. Ship the executable bit in the file's own mode instead.
