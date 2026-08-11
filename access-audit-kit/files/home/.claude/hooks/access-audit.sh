#!/bin/bash
# Claude Code hook that records denied accesses. Registered for two events, and it
# branches on .hook_event_name from the payload rather than on a CLI flag:
#
#   PostToolUse  — the tool ran but something in the sandbox refused it. This is where
#                  sbx proxy denials land: the proxy answers 403 with the exact text
#                  "Blocked by network policy: domain <host>:<port>", which shows up in
#                  the tool result (curl body, npm/pip error, WebFetch failure, ...).
#   Notification — Claude Code asking for permission. A permission prompt is the closest
#                  observable signal for "this call was refused", because a call blocked
#                  by PreToolUse never reaches PostToolUse at all.
#
# Always exits 0 and prints nothing: this hook observes, it never changes a verdict.

set -uo pipefail

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

recorder="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/record-denial.sh"
[ -x "$recorder" ] || exit 0

event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.url // .tool_input.file_path // empty' 2>/dev/null)

record() {
    "$recorder" --kind "$1" --target "$2" --detail "$3" \
        --cwd "$cwd" --command "$cmd" --tool "$tool" --session "$session" >/dev/null 2>&1 || true
}

if [ "$event" = "Notification" ]; then
    message=$(printf '%s' "$input" | jq -r '.message // empty' 2>/dev/null)
    case "$message" in
        *permission*|*Permission*)
            record permission "${tool:-unknown-tool}" "$message"
            ;;
    esac
    exit 0
fi

# PostToolUse: flatten the whole result (string or object) to text and scan it.
text=$(printf '%s' "$input" | jq -r '.tool_response | if type == "string" then . else tojson end' 2>/dev/null)
[ -n "$text" ] || exit 0

# sbx proxy denial, e.g. "Blocked by network policy: domain example.com:443".
# The policy word is captured too, so a filesystem denial is filed as its own kind.
printf '%s' "$text" | grep -oE 'Blocked by [a-z]+ policy: [a-z]+ [^[:space:]"\\]+' 2>/dev/null | sort -u | while IFS= read -r hit; do
    policy=$(printf '%s' "$hit" | awk '{print $3}')       # network | filesystem | ...
    resource=$(printf '%s' "$hit" | awk '{print $NF}')    # host:port | path
    record "$policy" "$resource" "blocked by sbx $policy policy (default deny)"
done

# Claude Code's own refusals. These normally arrive as a tool error rather than a
# PostToolUse event, so treat this as a best-effort catch, not the primary path.
if printf '%s' "$text" | grep -qE "Permission for this action was denied|Blocked by classifier|requested permissions to use|user doesn't want to (proceed|take this action)"; then
    record permission "${tool:-unknown-tool}" "Claude Code denied the call"
fi

exit 0
