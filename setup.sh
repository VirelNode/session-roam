#!/usr/bin/env bash
set -euo pipefail

# session-roam: One-command Syncthing setup for Claude Code session sync
# https://github.com/VirelNode/session-roam

# ---------------------------------------------------------------------------
# Color output helpers (D-05)
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1" >&2; }
info() { printf "${BLUE}[..]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[!!]${NC} %s\n" "$1"; }
die()  { fail "$1"; exit 1; }

trap 'fail "Setup failed at line $LINENO"' ERR

# ---------------------------------------------------------------------------
# Config path helpers
# ---------------------------------------------------------------------------
get_config_path() {
    # Try syncthing --paths first (most reliable)
    local paths_output
    if paths_output=$(syncthing --paths 2>/dev/null); then
        local config_file
        config_file=$(echo "$paths_output" | grep -A1 "Configuration file:" | tail -1 | tr -d '[:space:]')
        if [[ -n "$config_file" && -f "$config_file" ]]; then
            echo "$config_file"
            return 0
        fi
    fi

    # Fallback: check common locations
    local path
    for path in \
        "$HOME/.local/state/syncthing/config.xml" \
        "$HOME/.config/syncthing/config.xml" \
        "$HOME/Library/Application Support/Syncthing/config.xml"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    die "Cannot find Syncthing config.xml"
}

get_api_key() {
    local config_file
    config_file=$(get_config_path)
    python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('${config_file}')
print(tree.getroot().find('gui/apikey').text)
"
}

# ---------------------------------------------------------------------------
# Health check with retry (D-13)
# ---------------------------------------------------------------------------
wait_for_syncthing() {
    local api_key="$1"
    local max_attempts=20
    local attempt=0
    info "Waiting for Syncthing API..."
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -sf -H "X-API-Key: ${api_key}" \
            "http://127.0.0.1:8384/rest/system/status" >/dev/null 2>&1; then
            ok "Syncthing API is responding"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 0.5
    done
    die "Syncthing API did not respond within 10 seconds"
}

# ---------------------------------------------------------------------------
# Argument parsing (D-03)
# ---------------------------------------------------------------------------
DEVICE_IDS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device-id)
            DEVICE_IDS+=("$2")
            shift 2
            ;;
        -h|--help)
            echo "Usage: setup.sh [--device-id ID]..."
            echo ""
            echo "Options:"
            echo "  --device-id ID   Peer device ID to add (repeatable)"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            die "Unknown option: $1. Use --help for usage."
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Pre-flight checks (D-08)
# ---------------------------------------------------------------------------
info "Running pre-flight checks..."

[[ $EUID -eq 0 ]] && die "Do not run as root. Syncthing uses user services."

OS=""
case "$(uname -s)" in
    Linux)
        command -v apt-get >/dev/null 2>&1 || die "Unsupported Linux distribution (apt-get not found)"
        command -v systemctl >/dev/null 2>&1 || die "systemd not found (systemctl missing)"
        OS="debian"
        ;;
    Darwin)
        command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install from https://brew.sh"
        OS="macos"
        ;;
    *)
        die "Unsupported OS: $(uname -s)"
        ;;
esac
ok "OS detected: ${OS}"

mkdir -p "$HOME/.claude/projects"
ok "Target directory ready: ~/.claude/projects/"

# ---------------------------------------------------------------------------
# Syncthing installation (D-01, D-02)
# ---------------------------------------------------------------------------
if command -v syncthing >/dev/null 2>&1; then
    ok "Syncthing already installed ($(syncthing --version | head -1))"
else
    info "Installing Syncthing..."
    case "$OS" in
        debian)
            sudo apt-get update && sudo apt-get install -y syncthing
            ;;
        macos)
            brew install syncthing
            ;;
    esac
    ok "Syncthing installed ($(syncthing --version | head -1))"
fi

# ---------------------------------------------------------------------------
# Config generation (first-run bootstrap)
# ---------------------------------------------------------------------------
config_exists=false
for check_path in \
    "$HOME/.local/state/syncthing/config.xml" \
    "$HOME/.config/syncthing/config.xml" \
    "$HOME/Library/Application Support/Syncthing/config.xml"; do
    if [[ -f "$check_path" ]]; then
        config_exists=true
        break
    fi
done

# Also try syncthing --paths
if [[ "$config_exists" == "false" ]]; then
    local_paths_config=""
    if local_paths_config=$(syncthing --paths 2>/dev/null | grep -A1 "Configuration file:" | tail -1 | tr -d '[:space:]'); then
        if [[ -n "$local_paths_config" && -f "$local_paths_config" ]]; then
            config_exists=true
        fi
    fi
fi

if [[ "$config_exists" == "false" ]]; then
    info "Generating initial Syncthing configuration..."
    syncthing generate --skip-port-probing --no-default-folder
    ok "Initial configuration generated"
else
    ok "Syncthing configuration already exists"
fi

# ---------------------------------------------------------------------------
# Service enable and start (D-12)
# ---------------------------------------------------------------------------
info "Ensuring Syncthing service is running..."
case "$OS" in
    debian)
        systemctl --user enable syncthing.service 2>/dev/null || true
        systemctl --user start syncthing.service 2>/dev/null || true
        ok "Syncthing service enabled and started (systemd)"

        # Check linger status
        linger_status=$(loginctl show-user "$USER" -p Linger --value 2>/dev/null || echo "unknown")
        if [[ "$linger_status" != "yes" ]]; then
            warn "User linger not enabled. Run: sudo loginctl enable-linger $USER"
        fi
        ;;
    macos)
        brew services start syncthing 2>/dev/null || true
        ok "Syncthing service started (brew services)"
        ;;
esac

# ---------------------------------------------------------------------------
# Wait for API readiness
# ---------------------------------------------------------------------------
api_key=$(get_api_key)
wait_for_syncthing "$api_key"

# --- Folder configuration and device pairing (Task 2) ---
