---
paths:
  - "statusline-kit/**/*"
---

# Statusline

What `statusline-kit/files/home/.claude/statusline.sh` renders, and why each segment is shaped that
way.

The statusline reads only the account out of `claude-<dir>-<account>` and renders it as
`[SBX] <Account>`, the account bare behind the badge; an unknown suffix leaves `[SBX]` standing alone.
Badge and account share one hue, held in `$sbx_hue` so the two cannot drift apart, and no weight or
per-account colour separates them — the segment reads as one word. The name itself is never shown —
`<dir>` is the workspace directory, which the line already carries.

It never measures the terminal, so the two unbounded segments are capped instead: dir 32 (`.../`
prefix, whole components only), branch 20 (`...` suffix), both overridable with
`SBX_STATUSLINE_MAX_DIR` and `SBX_STATUSLINE_MAX_BRANCH`. Ellipses are ASCII, not `…`, so a cropped
name never reads as one character.

The caps are a guess about terminal width, so budget against the rest of the line before moving one:
the other segments and separators cost 70 columns together, which puts the worst case at 126 —
everything present, dir and branch both cropped at their cap.
