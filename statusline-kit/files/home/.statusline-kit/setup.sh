#!/bin/bash

# Idempotent sandbox setup, run at every start via commands.startup.
# Must be a startup command: the sandbox seeds ~/.claude/settings.json after files/ and initFiles.

set -uo pipefail

KIT_DIR="$HOME/.statusline-kit"
log() { printf '[statusline-kit] %s\n' "$*"; }

# Merge, never overwrite: settings.json holds the seeded bypassPermissions keys.
setup_statusline() {
    local settings="$HOME/.claude/settings.json" script="$KIT_DIR/statusline.sh" tmp
    [ -f "$script" ] || { log "statusline.sh missing"; return; }
    chmod +x "$script" 2>/dev/null
    mkdir -p "$HOME/.claude"
    [ -s "$settings" ] || echo '{}' > "$settings"

    # Bail on invalid JSON instead of letting jq empty the file.
    jq -e . "$settings" >/dev/null 2>&1 || { log "settings.json invalid, skipping"; return; }

    tmp=$(mktemp)
    if jq --arg cmd "$script" '.statusLine = {"type":"command","command":$cmd}' "$settings" >"$tmp" && [ -s "$tmp" ]; then
        mv "$tmp" "$settings"; log "statusline registered"
    else
        rm -f "$tmp"; log "statusline merge failed"
    fi
}

main() {
    setup_statusline
    exit 0
}

main
