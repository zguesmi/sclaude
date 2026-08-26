---
paths:
  - "claude-config-kit/**/*"
---

# Claude config

What `claude-config-kit` writes into a fresh sandbox: plugins, marketplaces, settings.

- Install plugins with the CLI. `enabledPlugins` alone leaves them uninstalled.
- Add every marketplace explicitly, `claude-plugins-official` included: Claude registers it on first
  *interactive* start, which a new sandbox never had. A live sandbox lists it only because a session ran.
- `claude` is on PATH in an install step.
- Loops guard on `--json` (`.[].repo`, `.[].id`) and are best-effort: an outage costs a plugin, not the
  sandbox. The settings merge is strict and runs first, since `plugin install` rewrites its own keys.
