#!/usr/bin/env bash
# End-to-end test for agent-stats-kit: drives the hook with synthetic payloads in a
# throwaway git repo, and replays the spec's install step against a throwaway
# ~/.claude to check the settings.json merge is additive and idempotent.
#
#   bash agent-stats-kit/tests/test-agent-stats.sh
set -uo pipefail

KIT=$(cd -- "$(dirname -- "$0")/.." && pwd)
SPEC="$KIT/spec.yaml"
HOOK="$KIT/files/home/.claude/hooks/agent-stats.py"
STATS=".agent-tool-stats.md"
failures=0

ok() { printf '  ✓ %s\n' "$1"; }
ko() { printf '  ✗ %s\n' "$1"; failures=$((failures + 1)); }
check() { if [ "$1" = 0 ]; then ok "$2"; else ko "$2"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- install step ----------------------------------------------------------

echo "install step"
CLAUDE_DIR="$TMP/claude"
mkdir -p "$CLAUDE_DIR/hooks"
# Pull the inline install command out of the single spec step, dedent it, and point
# it at the throwaway config dir. Run from a file, never from an -c string.
sed -n '/^      command: |$/,/^      user:/p' "$SPEC" \
    | sed '1d;$d' \
    | sed -e 's/^        //' -e "s#/home/agent/.claude#$CLAUDE_DIR#g" > "$TMP/install.sh"

printf '{"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/bin/bash /x/git-guardrails.sh"}]}]}}\n' \
    > "$CLAUDE_DIR/settings.json"

if command -v jq >/dev/null 2>&1; then
    sh "$TMP/install.sh" >/dev/null 2>&1
    check $? "install step succeeds"
    settings="$CLAUDE_DIR/settings.json"
    jq -e '.model == "opus"' "$settings" >/dev/null 2>&1
    check $? "unrelated settings preserved"
    jq -e '.hooks.PreToolUse | length == 1' "$settings" >/dev/null 2>&1
    check $? "foreign hook preserved"
    for event in UserPromptSubmit PostToolUse Stop SessionEnd; do
        jq -e --arg e "$event" '
            [.hooks[$e][].hooks[] | select(.command | contains("agent-stats.py"))] | length == 1
        ' "$settings" >/dev/null 2>&1
        check $? "$event registered once"
    done
    jq -e '.hooks.PostToolUse[-1].matcher == "*"' "$settings" >/dev/null 2>&1
    check $? "PostToolUse matcher is *"
    jq -e '.hooks.UserPromptSubmit[-1] | has("matcher") | not' "$settings" >/dev/null 2>&1
    check $? "UserPromptSubmit entry has no matcher"

    cp "$settings" "$TMP/settings.before"
    sh "$TMP/install.sh" >/dev/null 2>&1
    cmp -s "$TMP/settings.before" "$settings"
    check $? "second install leaves settings.json unchanged"
else
    echo "  - jq missing, install step skipped"
fi

# --- hook ------------------------------------------------------------------

echo "hook"
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test

hook() { # hook <json>
    printf '%s' "$1" | (cd "$REPO" && python3 "$HOOK")
}
payload() { # payload <event> <session> [extra-json]
    printf '{"session_id":"%s","cwd":"%s","hook_event_name":"%s"%s}' \
        "$2" "$REPO" "$1" "${3:-}"
}

hook "$(payload UserPromptSubmit s1 ',"prompt":"Add an SBX kit that records agent tool usage. Then test it."')"
check $? "UserPromptSubmit exits 0"
[ -f "$REPO/$STATS" ]
check $? "$STATS created"
grep -q '^# Agent tool stats$' "$REPO/$STATS"
check $? "document header written"
grep -Eq '^## [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} - Add an SBX kit that records agent tool usage\.$' "$REPO/$STATS"
check $? "heading is '<date> - <sentence>' from the first prompt"
grep -q '^\.claude/\.agent-stats/$' "$REPO/.gitignore"
check $? "state dir gitignored"

for _ in 1 2 3; do hook "$(payload PostToolUse s1 ',"tool_name":"Bash"')"; done
hook "$(payload PostToolUse s1 ',"tool_name":"Edit"')"
grep -q '^| Bash | 3 |$' "$REPO/$STATS"
check $? "Bash counted 3 times"
grep -q '^| Edit | 1 |$' "$REPO/$STATS"
check $? "Edit counted once"
grep -q '^\*\*Total:\*\* 4$' "$REPO/$STATS"
check $? "total is 4"

hook "$(payload UserPromptSubmit s1 ',"prompt":"And now something else entirely."')"
grep -q 'Add an SBX kit that records agent tool usage\.' "$REPO/$STATS"
check $? "later prompt does not overwrite the session title"

sed -n '/agent-stats:session:s1 /,/\/agent-stats:session:s1 /p' "$REPO/$STATS" > "$TMP/block1"
printf '\nHand written note, outside any marker.\n' >> "$REPO/$STATS"
hook "$(payload PostToolUse s2 ',"tool_name":"Read"')"
check $? "second session, hook installed mid-session, exits 0"
[ "$(grep -c '^## ' "$REPO/$STATS")" = 2 ]
check $? "two session blocks"
sed -n '/agent-stats:session:s1 /,/\/agent-stats:session:s1 /p' "$REPO/$STATS" | cmp -s - "$TMP/block1"
check $? "first block untouched"
grep -q '^Hand written note, outside any marker\.$' "$REPO/$STATS"
check $? "hand edit outside the markers preserved"
grep -q '(task description unavailable)' "$REPO/$STATS"
check $? "lazy block gets the placeholder title"

hook "$(payload Stop s1)"
git -C "$REPO" diff --cached --name-only | grep -qx "$STATS"
check $? "Stop stages the file"
[ -z "$(git -C "$REPO" log --oneline 2>/dev/null)" ]
check $? "nothing committed"

# --- robustness ------------------------------------------------------------

echo "robustness"
printf '' | (cd "$REPO" && python3 "$HOOK"); check $? "empty stdin exits 0"
printf 'not json' | (cd "$REPO" && python3 "$HOOK"); check $? "non-JSON stdin exits 0"
printf '[]' | (cd "$REPO" && python3 "$HOOK"); check $? "non-object payload exits 0"
hook '{"hook_event_name":"PostToolUse","tool_name":"Bash"}'; check $? "missing session_id exits 0"
hook "$(payload PostToolUse s1 ',"tool_name":"Bash"')" >/dev/null # restore a sane state

NOGIT="$TMP/nogit"
mkdir -p "$NOGIT"
printf '{"session_id":"s9","cwd":"%s","hook_event_name":"Stop"}' "$NOGIT" | python3 "$HOOK"
check $? "Stop outside a work tree exits 0"

chmod a-w "$REPO/$STATS"
hook "$(payload PostToolUse s1 ',"tool_name":"Bash"')"
check $? "unwritable stats file exits 0"
chmod u+w "$REPO/$STATS"

# --- concurrency -----------------------------------------------------------

echo "concurrency"
CONC="$TMP/conc"
mkdir -p "$CONC"
for i in $(seq 1 20); do
    printf '{"session_id":"c1","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash"}' "$CONC" \
        | python3 "$HOOK" &
done
wait
grep -q '^\*\*Total:\*\* 20$' "$CONC/$STATS"
check $? "20 parallel PostToolUse hooks all counted"

echo
if [ "$failures" = 0 ]; then
    echo "all checks passed"
else
    echo "$failures check(s) failed"
fi
exit $((failures > 0))
