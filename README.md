# sbx-postinstall kit

Automates the "Post-install configuration" section of the
[Docker Sandboxes (sbx) for AI agents](REDACTED
page, so a new sandbox needs no manual setup.

Verified on `sbx v0.37.0` / `claude-code-docker`.

## Usage

```shell
cd ~/my-project
/path/to/sclaude.sh
```

Names the sandbox after the current directory, configures it, and attaches.

```shell
./sclaude.sh -n my-name        # explicit name
./sclaude.sh --no-run          # create without attaching
./sclaude.sh -- . ../docs:ro   # extra args for `sbx create`
```

Re-running on an existing sandbox re-applies the kit with `sbx kit add`, which
restarts the VM but keeps its state. Kit alone, without the host-side steps:

```shell
sbx create --name my-project --kit ./sbx-postinstall-kit claude .
```

## What's automated

| Step | Where | How |
| --- | --- | --- |
| Claude Code statusline | kit | `statusline.sh` merged into `settings.json` at startup |
| Git identity | kit + host | host `~/.gitconfig` staged into the kit, wired in with `[include]` |
| Image pasting | host | `sbx settings set clipboard.imagePaste true` |
| GitHub over HTTPS | host | `gh auth token \| sbx secret set -g github` |
| Host agent skills | host | `sbx skills import --force` |

## GitHub: HTTPS, not SSH

The kit ships no `github.com:22` rule, so SSH is unreachable. GitHub goes over
HTTPS, authenticated by the proxy from the stored `github` secret. The token
never enters the VM — the sandbox sees a sentinel (`gho_sbxproxymanaged…`), and
injection is triggered by the request's destination domain.

Repos with a `git@github.com:` remote won't push. Switch them:

```shell
git remote set-url origin https://github.com/<org>/<repo>.git
```

## Two Anthropic tokens for two sandboxes

```shell
sbx secret set sandbox-a anthropic
```

A sandbox-scoped secret beats the global (`-g`) one and applies immediately, with
no recreate; changing a *global* secret does need one. Caveat: this scopes the
API key. If the agent is signed in with a Claude subscription (OAuth, stored at
`~/.claude/.credentials.json`), usage follows that login instead.

## Gotchas, if you edit this

All verified against `sbx v0.37.0`, not inferred from the docs.

- **The sandbox seeds `~/.claude/settings.json` after kit `files/` and
  `initFiles`**, so only `commands.startup` runs late enough to touch it — and it
  must be *merged*, since the seeded file carries `defaultMode: bypassPermissions`.
  Docker's own [example](https://docs.docker.com/ai/sandboxes/customize/kit-examples/#override-agent-settings)
  overwrites the file, which would leave the agent prompting on every tool call.
- **Install commands run before `files/` is copied in**, so they can't `chmod` a
  kit-shipped script. The startup command uses `bash <path>` instead.
- **`git config --global` doesn't follow `[include]`** — read the identity back
  with `git config user.name`.
- **Kit spec v2**: `caps.network.allow` replaces `network.allowedDomains`, and
  `credentials` is a list of `- service:` entries with `apiKey.inject`. The
  published docs still show v1.
- **Kits can't read arbitrary host files at create time** (`initFiles` only
  expands `${WORKDIR}`; `credentials` file sources are proxy-only). Hence
  `sclaude.sh` stages the gitconfig host-side.

## Next

- Publish to Docker Hub (`sbx kit push`) so teammates use a ref instead of a
  local path — the Confluence page's open "Shared team setup" item. Only
  `docker.io/` is allowed by default (`kit.allowedSources`).
- MCP servers via `files/workspace/.mcp.json`, which the sandbox won't overwrite.

## Layout

```text
├── spec.yaml                  kit spec (v2)
├── sclaude.sh                  host-side wrapper: settings, secret, skills, create
└── files/home/.sbx-kit/       → /home/agent/.sbx-kit/
    ├── setup.sh                    idempotent setup, runs at every sandbox start
    └── statusline.sh          the statusline
```
