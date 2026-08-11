#!/bin/bash

# Create the sandbox for the current directory if needed, then launch Claude in it.
# Args are forwarded straight through to `claude` (via `sbx run -- ...`). A `--`
# in the script's own args splits that from a second group forwarded to `sbx create`
# (only meaningful the first time, when the sandbox doesn't exist yet).
#
# Usage:
#   sbxc                              # launch claude
#   sbxc -r                           # -> claude -r
#   sbxc agents                       # -> claude agents
#   sbxc -r -- --kit /path/to/other-kit   # claude -r, plus an extra kit at create time
#
# Install globally: ln -s "$PWD/sbxc.sh" ~/.local/bin/sbxc

set -euo pipefail

# sbx names sandboxes "<agent>-<workdir>".
AGENT=claude
BASENAME=${PWD##*/}
SANDBOX_NAME="$AGENT-${BASENAME//[^a-zA-Z0-9.+-]/-}"

# readlink -f resolves the ~/.local/bin symlink, so the kits are found next to the
# real script rather than next to the link.
KITS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Split "$@" on the first literal "--": before it goes to claude, after it goes
# to `sbx create` (e.g. extra --kit/mounts).
CLAUDE_ARGS=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    CLAUDE_ARGS+=("$1")
    shift
done
SBX_CREATE_ARGS=("${@:2}")  # skips the "--" itself; empty when there was none

# $'...' so these hold real escape characters, usable directly in a format string.
RESET=$'\033[0m'
BOLD=$'\033[1m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
GREY=$'\033[90m'

title() { printf "\n${BOLD}%s${RESET} ${GREY}%s${RESET}\n" "$1" "${2-}"; }
ok()    { printf "  ${GREEN}✔${RESET} %s\n" "$*"; }
run()   { printf "  ${CYAN}→${RESET} %s\n" "$*"; }
warn()  { printf "  ${YELLOW}!${RESET} %s\n" "$*"; }
error() { printf "  ${RED}✘${RESET} %s\n" "$*"; }

sandbox_exists() {
    sbx ls 2>/dev/null | awk -v n="$SANDBOX_NAME" '$1 == n {found=1} END {exit !found}'
}

setting_is() { [ "$(sbx settings get "$1" 2>/dev/null)" = "$2" ]; }

# Appends to /etc/sandbox-persistent.sh, sourced before every bash in the sandbox.
append_to_persistent_sh_file() {
    sbx exec -i "$SANDBOX_NAME" bash -c 'cat >> /etc/sandbox-persistent.sh'
}

# Optional: silent when the host is already configured.
set_host_config() {
    setting_is clipboard.imagePaste true || {
        sbx settings set clipboard.imagePaste true >/dev/null && ok "clipboard.imagePaste"
    }
    setting_is kit.allowLocalKits true || {
        sbx settings set kit.allowLocalKits true >/dev/null && ok "kit.allowLocalKits"
    }
}

# Optional: silent when a github secret is already stored.
set_github_token() {
    sbx secret ls 2>/dev/null | awk '$3 == "github" {f=1} END {exit !f}' && return
    gh auth token | sbx secret set -g github >/dev/null && ok "github token stored"
}

create_sandbox() {
    # --kit only applies at create; `sbx kit add` restarts but preserves VM state.
    # sbx kit add "$SANDBOX_NAME" <kit>
    sbx create --name "$SANDBOX_NAME" \
        --kit "$KITS_DIR/shell-prompt-kit" \
        --kit "$KITS_DIR/statusline-kit" \
        --kit "$KITS_DIR/git-guardrails-kit" \
        --kit "$KITS_DIR/access-audit-kit" \
        "${SBX_CREATE_ARGS[@]}" \
        "$AGENT" . >/dev/null && ok "sandbox created"
}

set_git_identity() {
    GIT_USER_NAME=$(git config --global user.name)
    GIT_USER_EMAIL=$(git config --global user.email)
    GIT_COMMANDS="git config --global user.name \"$GIT_USER_NAME\""$'\n'
    GIT_COMMANDS+="git config --global user.email \"$GIT_USER_EMAIL\""
    printf '%s\n' "$GIT_COMMANDS" | append_to_persistent_sh_file
    ok "git identity  ${GREY}$GIT_USER_NAME <$GIT_USER_EMAIL>${RESET}"
}

run_sandbox() {
    run "Claude Code"
    exec sbx run --name "$SANDBOX_NAME" -- "${CLAUDE_ARGS[@]}"
}

main() {
    if sandbox_exists; then
        title "$SANDBOX_NAME" "(existing)"
        [ "${#SBX_CREATE_ARGS[@]}" -eq 0 ] || warn "ignoring args after --  (sandbox already exists): ${SBX_CREATE_ARGS[*]}"
    else
        title "$SANDBOX_NAME" "(new)"
        set_host_config
        set_github_token
        create_sandbox
        set_git_identity
    fi
    run_sandbox
}

main
