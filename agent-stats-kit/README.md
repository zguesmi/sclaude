# agent-stats-kit

Registers a Claude Code hook that creates or updates `.agent-tool-stats.md` at the root of the
project mounted in the sandbox: every tool the agent used and how many times, one markdown block per
session, each titled `<date> - <a sentence explaining the task>`. The file is staged with `git add`
when the session ends, so it is tracked in git — committing it stays your decision.

The script is registered for four events in `~/.claude/settings.json`:

| Event              | Does                                                                     |
| ------------------ | ------------------------------------------------------------------------ |
| `UserPromptSubmit` | creates the session block, title derived from the first prompt           |
| `PostToolUse`      | increments the counter for `tool_name` and re-renders the block          |
| `Stop`/`SessionEnd`| final render, then `git add -- .agent-tool-stats.md`                     |

Counters live as JSON in `<project>/.claude/.agent-stats/<session-id>.json`; the markdown file is a
rendering of that state. The hook appends `.claude/.agent-stats/` to the project's `.gitignore` on
first use. Each block is fenced by `<!-- agent-stats:session:<id> -->` markers, so a re-render
rewrites only the current session's span — earlier blocks and hand edits outside the markers survive.
Writes go through a temp file in the same directory plus an `flock` on `<state-dir>/lock`, so
concurrent `PostToolUse` hooks cannot interleave.

Sample output:

```markdown
# Agent tool stats

<!-- agent-stats:session:6f2c1a -->
## 2026-09-23 10:22 - Add an SBX kit that records agent tool usage.

| Tool | Invocations |
| --- | --- |
| Bash | 12 |
| Edit | 4 |

**Total:** 16
<!-- /agent-stats:session:6f2c1a -->
```

Every code path exits 0: a stats failure never blocks or slows a tool call, and a broken payload is
dropped silently (with a line in `<state-dir>/agent-stats.log`).

Notes:

- The title comes from your first prompt of the session, collapsed to one sentence and truncated to
  100 characters. It lands in a file you may commit — do not open a session with a secret.
- A tracked file that grows on every session conflicts easily in a shared repo; a
  `.gitattributes` line such as `.agent-tool-stats.md merge=union` takes the sting out of it.
- Needs `python3` in the sandbox. `files/` lands mode 644, so the hook is registered as
  `python3 /home/agent/.claude/hooks/agent-stats.py`, never as a bare path.

Check the spec and exercise the hook with synthetic payloads:

```shell
sbx kit validate agent-stats-kit
bash agent-stats-kit/tests/test-agent-stats.sh
```

Remove it by dropping the four `agent-stats.py` entries from `~/.claude/settings.json`.
