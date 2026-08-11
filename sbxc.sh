#!/bin/bash

# Launch Claude Code in the sandbox for the current directory, creating it with this repo's kits on
# first use. Arguments go to `sbx run`; Claude's own go after `--`. See README.md.

set -euo pipefail

REPO=https://github.com/zguesmi/sbx-test.git
KIT_SOURCE=github.com/zguesmi/
KITS=(
    --kit "git+$REPO#ref=master&dir=shell-prompt-kit"
    --kit "git+$REPO#ref=master&dir=statusline-kit"
    --kit "git+$REPO#ref=master&dir=git-guardrails-kit"
    --kit "git+$REPO#ref=master&dir=access-audit-kit"
)

# Host-wide, hence a one-off rather than part of every launch.
setup() {
    if setting_is clipboard.imagePaste true; then
        echo "clipboard.imagePaste: already set"
    else
        sbx settings set clipboard.imagePaste true >/dev/null
        echo "clipboard.imagePaste: set"
    fi

    # Merged, not assigned: the default list holds docker.io/ and may hold other sources.
    local sources
    sources=$(sbx settings get kit.allowedSources 2>/dev/null) || sources='[]'
    if jq -e --arg s "$KIT_SOURCE" 'index($s)' <<<"$sources" >/dev/null; then
        echo "kit.allowedSources: already allows $KIT_SOURCE"
    else
        sbx settings set kit.allowedSources \
            "$(jq -c --arg s "$KIT_SOURCE" '. + [$s]' <<<"$sources")" >/dev/null
        echo "kit.allowedSources: added $KIT_SOURCE"
    fi

    if sbx secret ls 2>/dev/null | awk '$3 == "github" {f=1} END {exit !f}'; then
        echo "github secret: already stored"
    elif gh auth token 2>/dev/null | sbx secret set -g github >/dev/null; then
        echo "github secret: stored"
    else
        echo "github secret: unavailable, run 'gh auth login'" >&2
    fi
}

setting_is() { [ "$(sbx settings get "$1" 2>/dev/null)" = "$2" ]; }

# sbx resolves a sandbox by workspace, so ask it rather than re-deriving the name it would pick.
sandbox_exists() {
    sbx ls --json 2>/dev/null |
        jq -e --arg w "$PWD" \
            'any(.sandboxes[]; .agent == "claude" and (.workspaces | index($w)))' \
            >/dev/null
}

if [ "${1-}" = setup ]; then
    setup
elif sandbox_exists; then
    # sbx rejects --kit on an existing sandbox; use `sbx kit add` for that.
    exec sbx run claude . "$@"
else
    exec sbx run claude . "${KITS[@]}" "$@"
fi
