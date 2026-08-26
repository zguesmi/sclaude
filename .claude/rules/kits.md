---
paths:
  - "**/spec.yaml"
  - "claude-config-kit/**/*"
  - "git-guardrails-kit/**/*"
  - "shell-prompt-kit/**/*"
  - "statusline-kit/**/*"
---

# Kits

Spec format, step ordering, and the files several kits write to at once.

- `sbx kit validate <kit-dir>` checks a spec.
- Top-level key is `setup:`. Unknown keys fail `sbx create`.
- `install` runs after the agent seeds its files, so a `jq` merge survives and static `files/` does not.
  It also runs before `files/` is copied, so it cannot `chmod` a shipped file.
- `files/` lands mode 644 whatever the mode in git. A shipped script is therefore never executable, and
  nothing in the kit can make it so. Register it as `/bin/bash <path>`, never as the bare path — run
  directly it is `Permission denied`, which Claude Code reports as no statusline and as a hook that
  silently guards nothing. Dedup a re-registered hook on the script path, not the command string, or
  the bare-path entry from an older revision survives beside the new one.
- Steps run under `sh`. `<<<` is a parse error and its exit 2 aborts `sbx create`. Step stdout is
  hidden; write a file and `sbx exec … cat` it.
- `~/.claude/settings.json` is shared by three kits: `jq` to a temp file in the same dir, then `mv`.
  Never overwrite. Hook kits append to `.hooks.<Event>` after dropping their own script's entry.
- `/etc/sandbox-persistent.sh` is shared and sourced before every bash: append only. Never completion
  scripts — `COMP_WORDS`/`COMPREPLY` break every shell.
