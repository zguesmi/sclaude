#!/bin/bash

# Create the sandbox for the current directory if needed, then launch Claude in it.
# All arguments are forwarded straight through to `claude` (via `sbx run -- ...`).
#
# Usage:
#   sbxc                              # launch claude
#   sbxc -r                           # -> claude -r
#   sbxc agents                       # -> claude agents
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
    sbx create --name "$SANDBOX_NAME" "$AGENT" . \
        --kit "$KITS_DIR/shell-prompt-kit" --kit "$KITS_DIR/statusline-kit" \
        >/dev/null && ok "sandbox created"
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
    exec sbx run --name "$SANDBOX_NAME" -- "$@"
}

validate() {
    step "Ready"
    # No --global on the git reads: that scope skips the [include] holding the identity.
    sbx exec "$SANDBOX_NAME" -- bash -lc '
printf "    git identity : %s\n" `git config list | grep name`
printf "    statusline   : %s\n" "$(jq -r ".statusLine.command // \"NOT SET\"" ~/.claude/settings.json 2>/dev/null)"
printf "    agent mode   : %s\n" "$(jq -r ".defaultMode // \"default\"" ~/.claude/settings.json 2>/dev/null)"
printf "    github https : %s\n" "$(gh auth status 2>&1 | grep -qi "logged in\|Active account" && echo "authenticated via proxy" || echo "unauthenticated (public repos only)")"
' 2>/dev/null || warn "could not verify sandbox state"
}

main() {
    if sandbox_exists; then
        title "$SANDBOX_NAME" "(existing)"
    else
        title "$SANDBOX_NAME" "(new)"
        set_host_config
        set_github_token
        create_sandbox
        set_git_identity
    fi
    # validate
    run_sandbox "$@"
}

main "$@"
