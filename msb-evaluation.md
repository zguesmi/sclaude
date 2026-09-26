# Evaluation: replacing sbx with msb (microsandbox)

Date: 2026-09-26. Based on msb docs and source only (`main` at 708a8ee, release v0.7.3 of
2026-09-24). Nothing was run: msb on Linux needs `/dev/kvm`, and the evaluation sandbox has none.

## Verdict

msb can carry the same setup, and it fixes the current blocker: sbx ≥ 0.43 strips the OAuth header
on `api.anthropic.com` (see `known-issues.md`), while msb documents placeholder substitution for any
host you allow. The cost is real: no kits, no clipboard image paste, no ready-made `claude` image,
and a beta tool.

## Mapping

| sclaude today (sbx) | msb equivalent | Gap |
|---|---|---|
| `sbx secret set-custom --host api.anthropic.com --env CLAUDE_CODE_OAUTH_TOKEN` | `--secret 'CLAUDE_CODE_OAUTH_TOKEN@api.anthropic.com'`. The guest sees a `$MSB_…` placeholder; the host-side proxy substitutes the real token. | msb reads the token from the host env at every sandbox **start**, not only at creation. The keyring read moves to every cold start. |
| Proxy injects the GitHub token for git | `--secret 'GH_TOKEN@github.com,api.github.com'` plus a git credential helper that sends the placeholder. Basic-auth substitution is on by default. | You write the credential helper. |
| 4 kits (`spec.yaml` + `files/`) | No kit concept. Use a custom OCI image (Dockerfile), or `--copy`/`--copy-dir` patches plus `msb exec` setup steps after create. | Largest rewrite. The `jq` merges carry over; the kit rules in `.claude/rules/kits.md` become obsolete. |
| `claude` agent image: user `agent`, uid 1000, `/etc/sandbox-persistent.sh` | msb's example uses `node:24-bookworm-slim` + `npm i -g @anthropic-ai/claude-code`. | You build and maintain the image: git, gh, jq, the user, the prompt file. |
| `sbx run claude .` does create-or-attach in one call | `msb run -t --name … --mount-dir $PWD:/workspace:rw`, then `msb exec -t <name> -- claude` for later sessions; `msb start` first if stopped. | The wrapper needs a three-way branch: missing, stopped, running. `msb ls --format json` gives the state. |
| Account as sandbox name suffix | Same scheme works. `--label account=personal` is an alternative. | None. |
| Default-deny network with host-side approval prompts | `--net-rule` allow/deny lists, `--net public` profile. | No interactive approval flow. |
| `clipboard.imagePaste` | No match in msb docs or source. | Image paste is lost. |
| Shared skills store mount | `--mount-dir ~/.claude/skills:/home/agent/.claude/skills` | None. |

msb runs one unprivileged host process per sandbox and no daemon, so the env passed to the `msb`
invocation reaches the sandbox's proxy.

## Risks to verify first

1. **Hosts other than `api.anthropic.com`.** A placeholder sent to a host outside the secret's allow
   list is blocked (default action `block-and-log`). If Claude Code sends the token elsewhere (for
   example for the claude.ai MCP connectors), those calls fail. The exact host list is unknown. Test
   with `*.anthropic.com`; msb wildcards match the root domain and its subdomains.
2. **CA trust.** msb's guest agent sets `NODE_EXTRA_CA_CERTS` and `SSL_CERT_FILE` for its TLS
   interception (`crates/agentd/lib/tls.rs`). Claude Code's native binary should honour
   `NODE_EXTRA_CA_CERTS`; not confirmed.
3. **Placeholder format.** Claude Code accepted `sbx-cs-…` before sbx 0.43, so `$MSB_…` will
   probably work. Not tested.
4. **Churn.** msb releases about weekly and its README says "expect breaking changes". sbx already
   broke once.
5. **Image source.** Not checked whether msb runs a locally built image or needs a registry push. If
   it needs a push, add a GHCR image to the pipeline.

## Cost

- **Wrapper:** about the same ~180 lines, restructured. Every sbx call changes, create/attach logic
  grows, and the `set-custom` placeholder upsert goes away.
- **Kits:** replaced by a Dockerfile plus the same install steps. Rough guess, not measured: 1–2 days
  to parity, including a CI image build.
- **Lost for good:** clipboard image paste, the network approval UX, Docker's maintained agent image.

## Recommendation

Run a one-hour spike on the host (KVM required) before migrating:

```shell
# msb reads the secret from the host env; the keyring keeps it off argv and history.
export CLAUDE_CODE_OAUTH_TOKEN=$(secret-tool lookup service sclaude account personal)
msb run -t --name msb-spike --secret 'CLAUDE_CODE_OAUTH_TOKEN@api.anthropic.com' \
  node:24-bookworm-slim -- sh -lc \
  'apt-get update && apt-get install -y ca-certificates git &&
   npm i -g @anthropic-ai/claude-code && exec claude'
```

Check `claude -p hi` and one claude.ai MCP connector. If both work, msb fixes the blocker and the
migration is worth it. If the connectors fail on hosts that cannot be allow-listed, stay pinned to
sbx 0.42.1 and wait for docker/sbx-releases#601.

## Sources

- [microsandbox repo](https://github.com/superradcompany/microsandbox): `docs/sandboxes/secrets.mdx`,
  `docs/networking/tls.mdx`, `docs/cli/sandbox-commands.mdx`,
  `docs/examples/agents/claude-code.mdx`, `docs/security/isolation.mdx`
- [Secrets docs](https://docs.microsandbox.dev/sdk/go/secrets)
