# sbx claude setup

Automates the "Post-install configuration" section of the
[Docker Sandboxes (sbx) for AI agents](REDACTED
page, so a new sandbox needs no manual setup.

Two pieces:

- **`sbxc.sh`** — host wrapper. Creates the sandbox if missing, configures it, opens a shell.
- **`statusline-kit/`** — kit that registers the Claude Code statusline on every sandbox start.

## Layout

```text
├── sbxc.sh                          host wrapper
└── statusline-kit/
    ├── spec.yaml                    kit spec (v2)
    └── files/home/.statusline-kit/  → /home/agent/.statusline-kit/
        ├── setup.sh                 registers the statusline, every start
        └── statusline.sh            the statusline itself
```

## Usage

```shell
cd ~/my-project
/path/to/sbxc.sh --kit /path/to/statusline-kit
```

The sandbox is named `claude-<directory>`. Every argument is forwarded straight
to `sbx create`, so extra mounts work too:

```shell
./sbxc.sh --kit ./statusline-kit ../docs:ro
```

If the sandbox already exists, setup is skipped and you just get a shell in it.

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

The statusline is the kit's job rather than the script's, because it has to run
as a `commands.startup` step.

## Gotchas

Verified against `sbx v0.37.0`, not inferred from the docs.

- **The sandbox seeds `~/.claude/settings.json` after kit `files/` and
  `initFiles`**, so only `commands.startup` runs late enough to touch it — and it
  must be _merged_, since the seeded file carries `defaultMode: bypassPermissions`.
  Docker's own [example](https://docs.docker.com/ai/sandboxes/customize/kit-examples/#override-agent-settings)
  overwrites the file, which would leave the agent prompting on every tool call.
- **Install commands run before `files/` is copied in**, so they can't `chmod` a
  kit-shipped script. The startup command uses `bash <path>` instead.
