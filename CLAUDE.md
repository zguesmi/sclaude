# CLAUDE.md

Host wrapper around `sbx`: one bash script, four kit specs. No build, no tests.
Validate by creating a sandbox.
The notes in `.ai/` are verified against **sbx v0.38.0** — if `sbx` contradicts one,
flag it, don't silently fix it.

Read the file that covers what you are about to touch _before_ editing:

- [.ai/wrapper.md](.ai/wrapper.md) — the `sclaude` script: what it owns, what it must leave to `sbx`,
  how `--name` and `--kit` behave. Read before changing argument handling or the kit list.
- [.ai/accounts.md](.ai/accounts.md) — the account prompt, the name suffix, the token, and the
  keyring. Read before touching `select_account`, `sbx secret`, or anything that handles the token.
- [.ai/kits.md](.ai/kits.md) — spec format, step ordering, file modes, and the files several kits
  write to at once. Read before editing any `spec.yaml`.
- [.ai/claude-config.md](.ai/claude-config.md) — plugins, marketplaces, and settings in a fresh
  sandbox. Read before editing `claude-config-kit`.
- [.ai/hooks.md](.ai/hooks.md) — how `git-guardrails.sh` blocks and how it must fail. Read before
  editing that script or adding a second hook.
- [.ai/statusline.md](.ai/statusline.md) — the segments the statusline renders and how they are
  capped. Read before editing `statusline.sh`.
- [.ai/conventions.md](.ai/conventions.md) — shell style, and how wrapper output is coloured and
  indented. Read before adding output of any kind.
