# Known issues

## OAuth token rejected on sbx ≥ 0.43.0

Status: open upstream, [docker/sbx-releases#601](https://github.com/docker/sbx-releases/issues/601).
Last working release: **0.42.1**.

### Symptom

Claude in a freshly created sandbox reports:

```
Remote managed settings failed to load (authentication rejected (401))
Not logged in · Please run /login
```

The configuration looks correct on both sides: `sbx secret ls --sandbox <name>` shows the
`api.anthropic.com` / `CLAUDE_CODE_OAUTH_TOKEN` mapping, the sandbox env holds the `sbx-cs-…`
placeholder, and the token authenticates from the host. Nothing warns at `set-custom` or at creation.

### Cause

sbx 0.43.0 changed the egress proxy:

> Hardened credential handling in the sandbox egress proxy so a client-supplied credential the proxy
> did not issue is not forwarded to managed provider hosts.

`api.anthropic.com` is a managed provider host, and the proxy treats the custom-secret placeholder as
a client-supplied credential. It strips the `Authorization` header instead of substituting it, so
Anthropic sees no credentials at all:

```shell
sbx exec <sandbox> sh -c 'curl -s https://api.anthropic.com/v1/messages \
  -H "Authorization: Bearer $CLAUDE_CODE_OAUTH_TOKEN" -H "anthropic-beta: oauth-2025-04-20" \
  -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
  -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"'
# ≥ 0.43.0: {"type":"error","error":{"type":"authentication_error","message":"x-api-key header is required"}}
```

The header is dropped whatever it holds, even an `sk-ant-oat01-` shaped placeholder or a bogus token.

### What does not work

- A custom placeholder shaped like an OAuth token (`--placeholder 'sk-ant-oat01-{rand}'`): still stripped.
- The built-in service, `sbx secret set anthropic --sandbox <name>`: forces api-key mode (seeds an
  `apiKeyHelper`), and the OAuth token is rejected as `API key is invalid.`
- `/login` inside the sandbox: sbx intercepts it and stores the token as a **global**
  `anthropic (oauth configured)` secret — one account for every sandbox, and `sclaude` refuses to run
  while it exists. Remove it with `sbx secret rm anthropic -f`.
- `-e CLAUDE_CODE_OAUTH_TOKEN=…` at creation works, but puts the real token inside the sandbox, which
  `sclaude` exists to avoid.

### Verified

Side by side on 2026-09-26, same keyring token, same Claude Code 2.1.280, fresh sandboxes:

| sbx     | direct API call               | `claude -p`     |
|---------|-------------------------------|-----------------|
| v0.45.0 | `x-api-key header is required` | `Not logged in` |
| v0.39.0 | reply                         | `ok`            |

### Workaround

Pin sbx to 0.42.1 until #601 is resolved:

```shell
sbx daemon stop
sudo apt install --allow-downgrades docker-sbx=0.42.1-1~ubuntu.24.04~noble
sudo apt-mark hold docker-sbx
```

Sandboxes created or modified under a newer release may not load after downgrading; rebuild with
`sbx rm claude-<dir>-<account> && sclaude`.

Related: [docker/sbx-releases#11](https://github.com/docker/sbx-releases/issues/11) (the original
`set-custom` workaround, reported broken since 0.43.0),
[v0.43.0 release notes](https://github.com/docker/sbx-releases/releases/tag/v0.43.0).
