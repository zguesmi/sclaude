# Hooks

- `git-guardrails.sh` (`PreToolUse`, Bash) `exit 2`s to block. Every other path exits 0 — a broken hook
  must not cut off shell access. `~/.claude/.git-guardrails-off` disables it. Patterns use `[^;&|]*` so
  no match spans chained commands.
