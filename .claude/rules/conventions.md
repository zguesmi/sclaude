# Conventions

Bash, `set -euo pipefail`. The kit list is explicit, not globbed.

Wrapper output borrows `sbx`'s glyphs (`→` step, `✓` result, `✗` failure) but prefixes a coral
`[sclaude]` tag flush left, so the two logs stay tellable apart in one scrollback. `log()` wraps the
message in grey; values inside it are `$WHITE` and return to `$GREY` after, so a line reads as a
shape before it reads as words. Everything goes to stderr and drops colour off a tty; every line
after the first — menu entries, wrapped errors — indents by `$INDENT`, four spaces. `sbx secret
set-custom` narrates in three lines — capture it and show it only when it fails.
