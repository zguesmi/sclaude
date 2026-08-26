# Wrapper

The `sclaude` script itself: what it owns, and how it hands off to `sbx`.

- Job is the kit list and the account. Delete features rather than reimplement `sbx`. `"$@"` reaches
  `sbx run` unparsed; don't route flags host-side — that is why the account is an env var, not a flag.
- `sbx run` resolves by *name*, defaulting to `<agent>-<workdir>` — **not** by which sandbox already
  holds the workspace. Omit `--name` and it builds a second, unsuffixed sandbox next to ours (seen:
  `claude-tmp.X` and `claude-tmp.X-personal` sharing one workspace). So `--name` goes on both paths,
  and existence is tested on the name, not the workspace.
- `--kit` is rejected on an existing sandbox, so only kits are conditional. Hence `set --` prepends
  them, then one `exec`. Don't use an array emptied on one path: empty `"${arr[@]}"` under `set -u`
  breaks bash 3.2 (macOS).
- Kits must be `git+<repo>#ref=master&dir=<kit>`. Other git syntaxes hit the OCI puller and fail. A kit
  edit only reaches new sandboxes once pushed.
- Kit prefixes need `kit.allowedSources`. It is shared — never drop entries.
- `sbx` seeds `/home/agent/.gitconfig`; add no git-identity step. It skips credential helpers — that's
  the global `github` secret.
