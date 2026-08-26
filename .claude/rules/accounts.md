---
paths:
  - "sclaude"
---

# Accounts

Which Claude subscription pays for a sandbox: the prompt, the sandbox name suffix, the token, and the
keyring it comes from.

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
