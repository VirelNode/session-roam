#!/usr/bin/env bash
set -euo pipefail

# session-roam: Verify sync health and detect problems
# https://github.com/VirelNode/session-roam

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
fail() { printf '  %s✗%s %s\n' "$RED" "$NC" "$1"; ERRORS=$((ERRORS + 1)); }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$1"; WARNINGS=$((WARNINGS + 1)); }
info() { printf '  %s·%s %s\n' "$BLUE" "$NC" "$1"; }

ERRORS=0
WARNINGS=0

echo ""
printf '%s%s%s\n' "$BOLD" "session-roam health check" "$NC"
echo "────────────────────────────────────"
echo ""

# ─── 1. Syncthing running ─────────────────────────────────────
printf '%s%s%s\n' "$BOLD" "Syncthing Service" "$NC"

if pgrep -x syncthing >/dev/null 2>&1; then
    ok "Syncthing process is running"
else
    fail "Syncthing is not running"
    echo ""
    echo "  Fix: systemctl --user start syncthing"
    echo ""
fi

# Check systemd status
if systemctl --user is-enabled syncthing.service >/dev/null 2>&1; then
    ok "Syncthing enabled at boot"
else
    warn "Syncthing not enabled at boot (won't survive reboot)"
    echo "  Fix: systemctl --user enable syncthing"
fi

echo ""

# ─── 2. API responding ────────────────────────────────────────
printf '%s%s%s\n' "$BOLD" "Syncthing API" "$NC"

# Find API key
api_key=""
for config_path in \
    "$HOME/.local/state/syncthing/config.xml" \
    "$HOME/.config/syncthing/config.xml"; do
    if [[ -f "$config_path" ]]; then
        api_key=$(python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('${config_path}')
print(tree.getroot().find('gui/apikey').text)
" 2>/dev/null || true)
        break
    fi
done

if [[ -n "$api_key" ]]; then
    if curl -sf -H "X-API-Key: ${api_key}" \
        "http://127.0.0.1:8384/rest/system/status" >/dev/null 2>&1; then
        ok "API responding on port 8384"
    else
        fail "API not responding"
    fi
else
    fail "Cannot find Syncthing API key"
fi

echo ""

# ─── 3. claude-sessions folder ─────────────────────────────────
printf '%s%s%s\n' "$BOLD" "claude-sessions Folder" "$NC"

if syncthing cli config folders list 2>/dev/null | grep -q "^claude-sessions$"; then
    ok "claude-sessions folder configured"

    # Check path
    folder_path=$(syncthing cli config folders claude-sessions path get 2>/dev/null || echo "unknown")
    if [[ "$folder_path" == *".claude/projects"* ]]; then
        ok "Path: $folder_path"
    else
        fail "Unexpected path: $folder_path (expected ~/.claude/projects)"
    fi

    # Check watcher delay
    delay=$(syncthing cli config folders claude-sessions fswatcher-delays get 2>/dev/null || echo "unknown")
    if [[ "$delay" == "2" ]]; then
        ok "File watcher delay: ${delay}s"
    else
        warn "File watcher delay is ${delay}s (expected 2s)"
    fi

    # Check folder type
    folder_type=$(syncthing cli config folders claude-sessions type get 2>/dev/null || echo "unknown")
    if [[ "$folder_type" == "sendreceive" ]]; then
        ok "Folder type: sendreceive"
    else
        warn "Folder type is '$folder_type' (expected sendreceive)"
    fi
else
    fail "claude-sessions folder not configured"
    echo "  Fix: run setup.sh"
fi

echo ""

# ─── 4. Connected devices ─────────────────────────────────────
printf '%s%s%s\n' "$BOLD" "Connected Devices" "$NC"

if [[ -n "$api_key" ]]; then
    connected_count=$(curl -sf -H "X-API-Key: ${api_key}" \
        "http://127.0.0.1:8384/rest/system/connections" 2>/dev/null \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for v in data.get('connections', {}).values() if v.get('connected'))
print(count)
" 2>/dev/null || echo "0")

    if [[ "$connected_count" -gt 0 ]]; then
        ok "${connected_count} peer(s) connected"
    else
        warn "No peers connected (sessions won't sync until a peer is online)"
    fi

    # List devices
    total_devices=$(syncthing cli config devices list 2>/dev/null | wc -l)
    my_id=$(syncthing cli show system 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['myID'])" 2>/dev/null || echo "unknown")
    peer_count=$((total_devices - 1))  # subtract self
    if [[ $peer_count -gt 0 ]]; then
        info "${peer_count} peer(s) configured total"
    fi
else
    warn "Skipping device check (no API key)"
fi

echo ""

# ─── 5. Session files ─────────────────────────────────────────
printf '%s%s%s\n' "$BOLD" "Session Files" "$NC"

session_dir="$HOME/.claude/projects"
session_count=$(find "$session_dir" -maxdepth 2 -name "*.jsonl" 2>/dev/null | wc -l || true)

if [[ $session_count -gt 0 ]]; then
    ok "${session_count} session file(s) found"

    # Most recent — disable pipefail locally to avoid SIGPIPE from head
    newest=$(set +o pipefail; find "$session_dir" -maxdepth 2 -name "*.jsonl" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    if [[ -n "$newest" ]]; then
        age_seconds=$(( $(date +%s) - $(stat -c %Y "$newest" 2>/dev/null || echo 0) ))
        if [[ $age_seconds -lt 3600 ]]; then
            ok "Most recent session: $((age_seconds / 60))m ago"
        elif [[ $age_seconds -lt 86400 ]]; then
            ok "Most recent session: $((age_seconds / 3600))h ago"
        else
            info "Most recent session: $((age_seconds / 86400))d ago"
        fi
    fi
else
    warn "No session files found"
fi

echo ""

# ─── 6. .stignore ─────────────────────────────────────────────
printf '%s%s%s\n' "$BOLD" ".stignore" "$NC"

if [[ -f "$session_dir/.stignore" ]]; then
    line_count=$(wc -l < "$session_dir/.stignore")
    ok ".stignore present (${line_count} lines)"
else
    warn "No .stignore — worktrees and caches are being synced unnecessarily"
    echo "  Fix: run install-aliases.sh or copy stignore.template"
fi

echo ""

# ─── 7. Conflict detection ────────────────────────────────────
printf '%s%s%s\n' "$BOLD" "Conflict Detection" "$NC"

conflict_count=$(find "$session_dir" -name "*.sync-conflict-*" 2>/dev/null | wc -l)

if [[ $conflict_count -eq 0 ]]; then
    ok "No sync conflicts found"
else
    fail "${conflict_count} sync conflict(s) detected!"
    echo ""
    echo "  Conflict files (investigate these — means concurrent writes happened):"
    find "$session_dir" -name "*.sync-conflict-*" 2>/dev/null | while read -r f; do
        echo "    $f"
    done
fi

echo ""

# ─── 8. Aliases installed ─────────────────────────────────────
printf '%s%s%s\n' "$BOLD" "Session Shortcuts" "$NC"

# Aliases and functions don't propagate into script subshells.
# Check the config files directly.
check_shortcut() {
    local name="$1"
    local pattern="$2"  # grep pattern to find it
    if grep -q "$pattern" "$HOME/.bash_aliases" 2>/dev/null || \
       grep -q "$pattern" "$HOME/.bashrc" 2>/dev/null || \
       grep -q "$pattern" "$HOME/.zshrc" 2>/dev/null; then
        ok "$name"
    else
        warn "$name not found (run install-aliases.sh, then source ~/.bashrc)"
    fi
}

check_shortcut "cr"    "alias cr="
check_shortcut "cs"    "alias cs="
check_shortcut "cf"    "^cf()"
check_shortcut "cn"    "^cn()"
check_shortcut "cfork" "^cfork()"
check_shortcut "crf"   "alias crf="

echo ""

# ─── Summary ──────────────────────────────────────────────────
echo "────────────────────────────────────"
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    printf '%s%s All checks passed.%s\n' "$GREEN" "$BOLD" "$NC"
elif [[ $ERRORS -eq 0 ]]; then
    printf '%s%s Passed with %d warning(s).%s\n' "$YELLOW" "$BOLD" "$WARNINGS" "$NC"
else
    printf '%s%s %d error(s), %d warning(s).%s\n' "$RED" "$BOLD" "$ERRORS" "$WARNINGS" "$NC"
fi
echo ""

exit $ERRORS
