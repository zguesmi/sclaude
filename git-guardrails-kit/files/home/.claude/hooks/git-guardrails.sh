#!/bin/bash
# Claude Code PreToolUse hook (Bash): deny destructive git commands.
#
# Reads the hook payload on stdin, pulls .tool_input.command, and exits 2 with a
# reason on stderr when the command matches a destructive pattern — exit 2 is what
# tells Claude Code to block the call and hand the message back to the model.
# Anything else (including a parse failure) exits 0, so a broken hook never wedges
# the sandbox's shell access.
#
# Escape hatch: create ~/.claude/.git-guardrails-off inside the sandbox to disable, e.g.
# from the host:  sbx exec <sandbox> -- touch /home/agent/.claude/.git-guardrails-off
# This is an accident guard, not a security boundary — the agent can create that
# file itself if it decides to.
#
# Every deny is also handed to access-audit-kit's recorder when that kit is
# installed, so the block shows up in the repo-local audit log. Optional by design:
# the two kits stay independent and this one works alone.

set -uo pipefail

input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

[ -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.git-guardrails-off" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
recorder="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/record-denial.sh"

# Collapse newlines/runs of spaces so the patterns below also match commands that
# were written across line continuations or with odd spacing.
norm=$(printf '%s' "$cmd" | tr '\n\t' '  ' | tr -s ' ')

has() { printf '%s' "$norm" | grep -Eq -- "$1"; }

deny() {
    # Best-effort audit trail; never let a missing/failing recorder change the verdict.
    if [ -x "$recorder" ]; then
        "$recorder" --kind git --target "$1" --detail "$2" --cwd "$cwd" --command "$cmd" >/dev/null 2>&1 || true
    fi
    printf 'git-guardrails: blocked "%s".\n%s\n' "$1" "$2" >&2
    printf 'Ask the user to run it themselves if it is really needed.\n' >&2
    exit 2
}

# Cheap bail-out: only inspect commands that actually invoke git (start of string,
# or after a shell separator, optionally via sudo/env prefixes we care about).
has '(^|[;&|(]|&&|\|\|) *(sudo +)?git( |$)' || exit 0

# Everything up to the next shell separator is checked as one unit per pattern;
# [^;&|]* keeps a match from spanning two chained commands.

# --- history rewriting on a remote -------------------------------------------
if has 'git( -[^ ]+)* push( |$)'; then
    # --force-with-lease and --force-if-includes are blocked too: they only guard the
    # remote-side race, and still rewrite history other clones already have.
    if has '(--force(-with-lease|-if-includes)?([ =]|$)|(^| )-f( |$))'; then
        deny 'git push --force' 'Force-pushing rewrites published history, --force-with-lease included.'
    fi
    has 'push[^;&|]* --mirror' && deny 'git push --mirror' 'A mirror push can delete every remote ref that is missing locally.'
    has 'push[^;&|]* --delete' && deny 'git push --delete' 'Deleting a remote branch is not reversible from here.'
    has 'push[^;&|]* :[^ /]+( |$)' && deny 'git push <remote> :<branch>' 'That refspec deletes the remote branch.'
fi

# --- discarding committed work ----------------------------------------------
has 'git[^;&|]* reset[^;&|]* --hard' && deny 'git reset --hard' 'This throws away uncommitted work. Use git stash, or reset --keep / --mixed.'
has 'git[^;&|]* (filter-branch|filter-repo)' && deny 'git filter-branch / filter-repo' 'Whole-history rewrite.'
has 'git[^;&|]* reflog[^;&|]* expire' && deny 'git reflog expire' 'The reflog is the last way back from a bad reset or rebase.'
has 'git[^;&|]* gc[^;&|]* --prune' && deny 'git gc --prune' 'Pruning drops unreachable objects, including anything only the reflog still points at.'
has 'git[^;&|]* update-ref[^;&|]* -d' && deny 'git update-ref -d' 'Deletes a ref outright, with no reflog entry to recover from.'
has 'git[^;&|]* branch[^;&|]* (-D|--delete[^;&|]* --force|-d[^;&|]* --force|--force[^;&|]* -d)' \
    && deny 'git branch -D' 'Force-deletes a branch even when it is not merged. Use -d and let git refuse if unmerged.'

# --- discarding uncommitted work --------------------------------------------
has 'git[^;&|]* clean[^;&|]* (-[a-zA-Z]*f|--force)' && deny 'git clean -f' 'Deletes untracked files, including ones git never had a copy of.'
has 'git[^;&|]* checkout[^;&|]* (--|\.)( |$)' && deny 'git checkout -- <path>' 'Overwrites uncommitted changes in the working tree.'
if has 'git[^;&|]* restore( |$)'; then
    # --staged on its own only unstages, which is recoverable; anything else
    # (including --staged --worktree) writes over the working tree.
    if ! has 'restore[^;&|]* --staged( |$)' || has 'restore[^;&|]* (--worktree|-W)( |$)'; then
        deny 'git restore <path>' 'Overwrites uncommitted changes in the working tree. --staged alone (unstage only) is allowed.'
    fi
fi
has 'git[^;&|]* switch[^;&|]* --discard-changes' && deny 'git switch --discard-changes' 'Throws away uncommitted changes.'
has 'git[^;&|]* stash[^;&|]* (drop|clear)' && deny 'git stash drop / clear' 'Stash entries are not in any branch; dropping them is final.'
has 'git[^;&|]* worktree[^;&|]* remove[^;&|]* (--force|-f)( |$)' && deny 'git worktree remove --force' 'Force-removes a worktree with uncommitted changes in it.'

exit 0
