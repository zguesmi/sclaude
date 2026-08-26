---
paths:
  - "statusline-kit/**/*"
---

# Statusline

What `statusline-kit/files/home/.claude/statusline.sh` renders, and why each segment is shaped that
way.

The statusline reads only the account out of `claude-<dir>-<account>` and renders it as
`[SBX] <Account>`, the account bare and bold in its own hue behind the badge; an unknown suffix leaves
`[SBX]` standing alone. The name itself is never shown — `<dir>` is the workspace directory, which the
line already carries.

It never measures the terminal, so the two unbounded segments are capped instead: dir 24 (`.../`
prefix, whole components only), branch 20 (`...` suffix), both overridable with
`SBX_STATUSLINE_MAX_DIR` and `SBX_STATUSLINE_MAX_BRANCH`. Ellipses are ASCII, not `…`, so a cropped
name never reads as one character.
