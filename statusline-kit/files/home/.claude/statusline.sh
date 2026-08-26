#!/bin/bash
# Claude Code status line — combines context info with the caveman plugin badge.

input=$(cat)

# --- sbx account (IS_SANDBOX/SANDBOX_VM_ID set by sbx itself) ---
# The sandbox is named claude-<dir>-<account>. Only the account is read out of it:
# <dir> is the workspace directory, which the line already carries further along.
in_sbx=""
sbx_account=""
sbx_account_sgr=""
if [ "${IS_SANDBOX:-}" = "1" ]; then
    in_sbx=1
    # Bold, and a hue per account, so which subscription is paying reads at a glance.
    case "${SANDBOX_VM_ID:-$(hostname)}" in
        *-personal) sbx_account="Personal" sbx_account_sgr='1;38;5;215' ;;
        *-work) sbx_account="Work" sbx_account_sgr='1;38;5;117' ;;
    esac
fi

# --- directory (path, shortened when long) ---
# /home/x/some/dir -> ~/some/dir -> …/some/dir
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
dir="$cwd"
case "$dir" in
    "$HOME") dir="~" ;;
    "$HOME"/*) dir="~${dir#"$HOME"}" ;;
esac
max=${SBX_STATUSLINE_MAX_DIR:-24}
if [ "${#dir}" -gt "$max" ]; then
    IFS='/' read -ra __comps <<< "$dir"
    kept=""
    for ((i = ${#__comps[@]} - 1; i >= 0; i--)); do
        [ -z "${__comps[i]}" ] && continue
        cand="/${__comps[i]}$kept"
        # -1 leaves room for the "…" prefix
        [ "${#cand}" -gt "$((max - 1))" ] && break
        kept="$cand"
    done
    # A single component longer than $max still has to be shown in full.
    [ -n "$kept" ] || kept="/${__comps[${#__comps[@]} - 1]}"
    dir="…$kept"
fi

# --- git branch (skip optional locks) ---
branch=""
if git -C "$cwd" rev-parse --is-inside-work-tree --no-optional-locks >/dev/null 2>&1; then
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    branch_max=${SBX_STATUSLINE_MAX_BRANCH:-20}
    if [ "${#branch}" -gt "$branch_max" ]; then
        branch="${branch:0:$((branch_max - 1))}…"
    fi
fi

# --- model ---
model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // "auto"')

# --- context usage ---
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')

# --- rate limits ---
five_hours_rate_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

# --- cost ---
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

# --- caveman badge ---
caveman() {
    local FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"
    [ -L "$FLAG" ] && return
    [ ! -f "$FLAG" ] && return
    local MODE
    MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
    MODE=$(printf '%s' "$MODE" | tr -cd 'a-z0-9-')
    case "$MODE" in
        off|lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress) ;;
        *) return ;;
    esac
    if [ -z "$MODE" ] || [ "$MODE" = "full" ]; then
        printf '\033[38;5;172m[CAVEMAN]\033[0m'
    else
        local SUFFIX
        SUFFIX=$(printf '%s' "$MODE" | tr '[:lower:]' '[:upper:]')
        printf '\033[38;5;172m[CAVEMAN:%s]\033[0m' "$SUFFIX"
    fi
    if [ "${CAVEMAN_STATUSLINE_SAVINGS:-1}" != "0" ]; then
        local SAVINGS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-statusline-suffix"
        if [ -f "$SAVINGS_FILE" ] && [ ! -L "$SAVINGS_FILE" ]; then
        local SAVINGS
        SAVINGS=$(head -c 64 "$SAVINGS_FILE" 2>/dev/null | tr -d '\000-\037')
        [ -n "$SAVINGS" ] && printf ' \033[38;5;172m%s\033[0m' "$SAVINGS"
        fi
    fi
}
caveman_badge=$(caveman)

# --- assemble ---
parts=()

# [SBX] Personal/Work
if [ -n "$in_sbx" ]; then
    sbx_badge=$(printf '\033[38;5;173m[SBX]\033[0m')
    [ -n "$sbx_account" ] &&
        sbx_badge+=$(printf ' \033[%sm%s\033[0m' "$sbx_account_sgr" "$sbx_account")
    parts+=("$sbx_badge")
fi

# model: Opus 5 (high)
[ -n "$model" ] && parts+=("$(printf '\033[90m%s\033[0m' "$model ($effort)")")

# context used % (+ token count): 104.3k (10%)
if [ -n "$used" ]; then
    used_int=$(printf '%.0f' "$used")
    tok_str=""
    if [ -n "$tokens" ]; then
        if [ "$tokens" -ge 1000 ]; then
        tok_str="$(awk -v t="$tokens" 'BEGIN{printf "%.1fk", t/1000}') "
        else
        tok_str="${tokens} "
        fi
    fi
    if [ "$used_int" -ge 80 ]; then
        parts+=("$(printf '\033[31m%s(%d%%)\033[0m' "$tok_str" "$used_int")")
    elif [ "$used_int" -ge 50 ]; then
        parts+=("$(printf '\033[33m%s(%d%%)\033[0m' "$tok_str" "$used_int")")
    else
        parts+=("$(printf '\033[32m%s(%d%%)\033[0m' "$tok_str" "$used_int")")
    fi
fi

# 5-hour rate limit: 5h:12%
if [ -n "$five_hours_rate_pct" ]; then
    rate_int=$(printf '%.0f' "$five_hours_rate_pct")
    [ "$rate_int" -gt 0 ] && parts+=("$(printf '\033[90m5h:%d%%\033[0m' "$rate_int")")
fi

# directory + branch: /some/dir (chore/branch)
if [ -n "$branch" ]; then
    parts+=("$(printf '\033[34m%s\033[0m \033[36m(%s)\033[0m' "$dir" "$branch")")
else
    parts+=("$(printf '\033[34m%s\033[0m' "$dir")")
fi

# # cost so far, USD
# if [ -n "$cost" ]; then
#     parts+=("$(awk -v c="$cost" 'BEGIN{printf "\033[32m$%.2f\033[0m", c}')")
# fi

# caveman badge (already colored, append as-is)
[ -n "$caveman_badge" ] && parts+=("$caveman_badge")

# join with separator
result=""
for part in "${parts[@]}"; do
    if [ -z "$result" ]; then
        result="$part"
    else
        result="$result $(printf '\033[90m|\033[0m') $part"
    fi
done

printf '%s' "$result"
