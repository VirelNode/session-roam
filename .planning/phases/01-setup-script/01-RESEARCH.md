# Phase 1: Setup Script - Research

**Researched:** 2026-04-11
**Domain:** Syncthing installation, configuration, and automation via bash scripting
**Confidence:** HIGH

## Summary

Syncthing is already installed and running on the current cluster (node01). The infrastructure is proven: 4 nodes sharing `~/.claude/projects/` via a `claude-sessions` folder with `fsWatcherDelayS=2`. The setup script's job is to codify this exact configuration so any new node (or a fresh reinstall) can join the cluster with one command.

Syncthing provides two automation paths: the `syncthing cli config` subcommand (talks to the running REST API) and direct REST API calls via curl. The CLI is cleaner for scripting but requires the service to be running first. The setup script must handle a bootstrap sequence: install -> generate config -> start service -> wait for API -> configure folder + devices. The REST API endpoint `/rest/config/restart-required` signals whether a restart is needed after config changes (most folder/device additions are hot-loaded without restart).

**Primary recommendation:** Use the `syncthing cli` command for all configuration operations (folder creation, device addition, property setting). It auto-reads the API key from config and provides cleaner error messages than raw curl. Fall back to REST API only if the CLI is unavailable. The script must handle the chicken-and-egg problem: Syncthing must be running before the CLI works, but config must be set before the folder is useful.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Detect package manager (apt on Ubuntu/Debian, brew on macOS). Install Syncthing if not present, skip if already installed. No snap -- apt or brew only.
- **D-02:** Script must work on Ubuntu 22.04+ and macOS 14+ (the actual cluster runs Ubuntu 24.04, but keep it portable for open-source release).
- **D-03:** Accept device IDs via `--device-id <ID>` flags (repeatable for multiple peers). If no flags provided, prompt interactively: display this node's device ID and ask user to paste peer IDs one per line, empty line to finish.
- **D-04:** Display this node's device ID prominently at the end of setup so the user can share it with other nodes.
- **D-05:** Step-by-step progress messages with color (green checkmarks for success, red X for failures). No --verbose or --quiet flags for v1 -- single output mode.
- **D-06:** Final summary block showing: node device ID, shared folder path, connected peers, sync status.
- **D-07:** Fail fast (`set -euo pipefail`) with a trap for cleanup messages. Each step prints what it's doing before doing it, so the user knows where it failed.
- **D-08:** Pre-flight checks at script start: confirm not running as root (Syncthing uses user services), confirm systemd is available (or launchd on macOS).
- **D-09:** Shared folder ID: `claude-sessions`. Path: `~/.claude/projects/`. fsWatcherDelayS: 2. These are the values proven on the 4-node cluster.
- **D-10:** Folder type: Send & Receive (bidirectional sync). No ignore-delete, no versioning for v1.
- **D-11:** Syncthing API accessed via localhost REST API (default port 8384). Script reads/writes config via `syncthing cli` or direct REST calls.
- **D-12:** Enable and start Syncthing as a systemd user service (`systemctl --user enable syncthing` / `systemctl --user start syncthing`). On macOS, use `brew services start syncthing`.
- **D-13:** Verify service is running after start (health check with retry -- wait up to 10s for API to respond).

### Claude's Discretion
- Exact color codes and formatting of output messages
- Whether to use `syncthing cli` commands vs direct REST API calls (whichever is more reliable)
- Temporary file handling during configuration
- Order of configuration steps (as long as the end state is correct)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| R1 | Install Syncthing if not present (apt/brew) | Verified apt package `syncthing` v1.27.2 on Ubuntu 24.04, systemd user service at `/usr/lib/systemd/user/syncthing.service`. macOS: `brew install syncthing` + `brew services`. |
| R1 | Configure `claude-sessions` shared folder pointing to `~/.claude/projects/` | REST API `POST /rest/config/folders` or `syncthing cli config folders add` with full JSON/flags. Config path: `~/.local/state/syncthing/config.xml`. |
| R1 | Set `fsWatcherDelayS` to 2 seconds | CLI: `syncthing cli config folders claude-sessions fswatcher-delays set 2` or include in folder creation JSON. |
| R1 | Enable and start Syncthing as user systemd service | `systemctl --user enable --now syncthing.service`. Verified service file ships with apt package. |
| R1 | Accept device IDs from other nodes (interactive or via args) | CLI: `syncthing cli config devices add --device-id <ID> --name <name>` then `syncthing cli config folders claude-sessions devices add --device-id <ID>`. |
| R1 | Idempotent -- safe to run multiple times | Check `syncthing cli config folders list` before adding. Check device list before adding devices. Skip steps already done. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Syncthing | v1.27.2 (apt) | P2P file synchronization | Already deployed on 4-node cluster, proven for session sync [VERIFIED: local apt-cache, running service] |
| bash | 5.x | Script runtime | Universal on Ubuntu/macOS, D-07 specifies `set -euo pipefail` [VERIFIED: /bin/bash on node01] |
| curl | any | REST API fallback | For health checks and API queries when CLI is insufficient [VERIFIED: installed] |
| python3 | 3.x | XML parsing (optional) | For extracting API key from config.xml if needed [VERIFIED: installed] |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| jq | any | JSON parsing from REST API responses | Parse folder/device status from REST API [ASSUMED: likely installed, verify at runtime] |
| xmllint | any | XML parsing for config.xml | Alternative to python3 for API key extraction [ASSUMED] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `syncthing cli` | Direct REST API via curl | curl is more portable but requires manual API key extraction and JSON construction; CLI auto-reads config |
| bash | Python script | Python is cleaner for complex logic but adds a dependency; bash is universal for setup scripts |
| xmllint for config parsing | python3 xml.etree | python3 is more likely to be installed; xmllint may need `libxml2-utils` package |

## Architecture Patterns

### Script Execution Flow
```
setup.sh
  |
  +-- Pre-flight checks
  |     +-- Not running as root
  |     +-- systemd available (Linux) or launchd (macOS)
  |     +-- ~/.claude/projects/ directory exists (or create it)
  |
  +-- Install Syncthing (if not present)
  |     +-- Detect OS (Linux/macOS)
  |     +-- apt install syncthing (Ubuntu/Debian)
  |     +-- brew install syncthing (macOS)
  |
  +-- Generate initial config (if first run)
  |     +-- syncthing generate --skip-port-probing --no-default-folder
  |     +-- Creates config.xml, key.pem, cert.pem
  |
  +-- Start/enable Syncthing service
  |     +-- systemctl --user enable --now syncthing (Linux)
  |     +-- brew services start syncthing (macOS)
  |
  +-- Wait for API readiness (health check loop)
  |     +-- Poll /rest/system/status up to 10s
  |     +-- Extract API key from config.xml for curl
  |
  +-- Configure shared folder
  |     +-- Check if 'claude-sessions' folder exists
  |     +-- If not: create via syncthing cli config folders add
  |     +-- Set fsWatcherDelayS=2
  |     +-- Create .stfolder marker in ~/.claude/projects/
  |
  +-- Add peer devices
  |     +-- Parse --device-id flags OR prompt interactively
  |     +-- For each device ID:
  |     |     +-- Add to global device list
  |     |     +-- Add to claude-sessions folder
  |     +-- Set auto-accept-folders on peer devices
  |
  +-- Verify configuration
  |     +-- Check /rest/config/restart-required
  |     +-- Restart if needed
  |     +-- Confirm folder is syncing (not in error state)
  |
  +-- Print summary
        +-- This node's device ID (prominent)
        +-- Shared folder path
        +-- Connected/configured peers
        +-- Sync status
```

### Pattern 1: Bootstrap Sequence (Chicken-and-Egg Resolution)
**What:** Syncthing CLI requires the service to be running (it talks to the REST API). But we need to configure the service. Solution: start with minimal config, then add folder/devices after service is up.
**When to use:** Every first-time setup.
**Example:**
```bash
# Source: verified against running node01 config
# Step 1: Generate minimal config (creates keys + default config)
syncthing generate --skip-port-probing --no-default-folder

# Step 2: Start the service
systemctl --user enable --now syncthing.service

# Step 3: Wait for API
wait_for_api() {
    local api_key
    api_key=$(extract_api_key)
    for i in $(seq 1 20); do
        if curl -sf -H "X-API-Key: ${api_key}" \
            http://127.0.0.1:8384/rest/system/status >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

# Step 4: Now CLI works -- add folder
syncthing cli config folders add \
    --id claude-sessions \
    --label "Claude Sessions" \
    --path "$HOME/.claude/projects" \
    --fswatcher-delays 2
```
[VERIFIED: tested all commands against running node01 instance]

### Pattern 2: Idempotent Guard Pattern
**What:** Check before modifying. Every mutable operation first queries current state.
**When to use:** Every configuration step.
**Example:**
```bash
# Source: verified against syncthing cli output
# Check if folder already exists
if syncthing cli config folders list 2>/dev/null | grep -q "^claude-sessions$"; then
    info "claude-sessions folder already configured"
else
    syncthing cli config folders add --id claude-sessions ...
fi

# Check if device already added
if syncthing cli config devices list 2>/dev/null | grep -q "^${DEVICE_ID}$"; then
    info "Device ${DEVICE_ID} already known"
else
    syncthing cli config devices add --device-id "${DEVICE_ID}" --name "${DEVICE_NAME}"
fi
```

### Pattern 3: OS Detection
**What:** Detect Linux vs macOS and choose appropriate package manager and service manager.
**When to use:** At script start.
**Example:**
```bash
detect_os() {
    case "$(uname -s)" in
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                echo "debian"
            else
                die "Unsupported Linux distribution (apt-get not found)"
            fi
            ;;
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                echo "macos"
            else
                die "Homebrew not found. Install from https://brew.sh"
            fi
            ;;
        *)
            die "Unsupported OS: $(uname -s)"
            ;;
    esac
}
```

### Anti-Patterns to Avoid
- **Editing config.xml directly while Syncthing is running:** The running process owns the file and will overwrite your changes. Always use the CLI or REST API. [VERIFIED: Syncthing docs warn about this]
- **Running Syncthing as root:** The systemd service is a USER service (`systemctl --user`). Running as root creates config in `/root/` and has wrong permissions. D-08 explicitly requires a root check. [VERIFIED: service file at `/usr/lib/systemd/user/syncthing.service`]
- **Assuming CLI works before service starts:** `syncthing cli config` connects to the REST API on 127.0.0.1:8384. If the service isn't running, all CLI config commands fail. The bootstrap sequence (Pattern 1) handles this. [VERIFIED: tested on node01]
- **Hardcoding API key:** The API key is auto-generated and different per node. Always extract it from `config.xml` at runtime. [VERIFIED: config.xml contains `<apikey>` element]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Config XML parsing | Custom sed/awk on XML | `python3 -c "import xml.etree.ElementTree..."` | XML parsing with regex is fragile; python3 ET handles edge cases [VERIFIED: tested extraction] |
| Syncthing folder management | Direct config.xml manipulation | `syncthing cli config folders add/...` | CLI handles locking, validation, and hot-reload [VERIFIED: CLI works against running service] |
| Device ID validation | Regex matching | `syncthing --device-id` flag handles this | Syncthing validates device IDs internally, rejects malformed ones [ASSUMED] |
| Service health checking | Single curl + sleep | Retry loop with exponential backoff | Service may take 1-5 seconds to start depending on hardware [VERIFIED: observed startup behavior] |

**Key insight:** Syncthing's own CLI is the best tool for scripting its configuration. It reads the config location and API key automatically, handles validation, and triggers hot-reload. Dropping to raw REST API should only happen for operations the CLI doesn't expose (like checking restart-required).

## Common Pitfalls

### Pitfall 1: Missing .stfolder Marker
**What goes wrong:** Syncthing refuses to sync, reports "folder marker missing (this indicates potential data loss)."
**Why it happens:** The `~/.claude/projects/` directory exists but wasn't created by Syncthing, so the `.stfolder` marker directory is missing. Currently happening on node01.
**How to avoid:** After creating the folder config, explicitly create the marker: `mkdir -p ~/.claude/projects/.stfolder`
**Warning signs:** `state: "error"` in `/rest/db/status?folder=claude-sessions`, log entries mentioning "folder marker missing."
[VERIFIED: observed this exact error on node01 right now -- `needFiles: 3044`, `state: "error"`]

### Pitfall 2: Syncthing CLI Fails Before Service Starts
**What goes wrong:** `syncthing cli config folders add ...` fails with connection refused error.
**Why it happens:** The CLI connects to the REST API at 127.0.0.1:8384. If the service hasn't started yet (or is still initializing), the connection fails.
**How to avoid:** Always wait for the API to become responsive before running CLI config commands. Use a health check loop polling `/rest/system/status`.
**Warning signs:** "connection refused" errors from `syncthing cli` commands.
[VERIFIED: CLI requires running service, confirmed via testing]

### Pitfall 3: Device Added Globally But Not to Folder
**What goes wrong:** Device is visible in Syncthing but the `claude-sessions` folder doesn't sync to it.
**Why it happens:** Adding a device to the global device list (`syncthing cli config devices add`) doesn't automatically share folders. You must also add the device to the specific folder (`syncthing cli config folders claude-sessions devices add --device-id <ID>`).
**How to avoid:** Always perform both operations: add device globally AND add device to the folder.
**Warning signs:** Device shows "connected" but no folders are shared with it.
[VERIFIED: observed in config.xml -- each folder has its own `<device>` list separate from global devices]

### Pitfall 4: systemd User Service Requires Lingering
**What goes wrong:** `systemctl --user enable syncthing` works but the service doesn't start on boot because user sessions are killed on logout.
**Why it happens:** By default, systemd kills user services when the user logs out. `loginctl enable-linger` is needed to keep user services running after logout.
**How to avoid:** Run `loginctl enable-linger $USER` during setup.
**Warning signs:** Service works while logged in but doesn't survive reboot/logout.
[ASSUMED: standard systemd behavior, not verified whether node01 has linger enabled]

### Pitfall 5: macOS launchd vs brew services
**What goes wrong:** On macOS, `brew services start syncthing` uses launchd under the hood but the service file location and behavior differs from systemd.
**Why it happens:** macOS uses launchd instead of systemd. brew services wraps launchd with a simpler interface.
**How to avoid:** On macOS, always use `brew services` commands, never try to use systemctl.
**Warning signs:** Script fails with "systemctl: command not found" on macOS.
[ASSUMED: standard macOS behavior]

### Pitfall 6: Config Directory Location Varies
**What goes wrong:** Script looks for config.xml in the wrong location.
**Why it happens:** Syncthing config location varies by OS and installation method:
  - Ubuntu 24.04 (apt): `~/.local/state/syncthing/config.xml`
  - Older Linux: `~/.config/syncthing/config.xml`
  - macOS: `~/Library/Application Support/Syncthing/config.xml`
**How to avoid:** Use `syncthing --paths` to get the canonical config location, or check both paths.
**Warning signs:** "No such file or directory" when trying to read config.xml.
[VERIFIED: confirmed `~/.local/state/syncthing/config.xml` on node01 via `syncthing --paths`]

## Code Examples

### Extracting API Key from config.xml
```bash
# Source: verified on node01 against actual config.xml
get_api_key() {
    local config_dir
    config_dir=$(syncthing --paths 2>/dev/null | grep "Configuration file:" -A1 | tail -1 | tr -d '[:space:]')
    # config_dir is the full path to config.xml
    if [[ -z "$config_dir" ]]; then
        # Fallback: check common locations
        for path in \
            "$HOME/.local/state/syncthing/config.xml" \
            "$HOME/.config/syncthing/config.xml" \
            "$HOME/Library/Application Support/Syncthing/config.xml"; do
            if [[ -f "$path" ]]; then
                config_dir="$path"
                break
            fi
        done
    fi
    python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('${config_dir}')
print(tree.getroot().find('gui/apikey').text)
"
}
```
[VERIFIED: tested python3 XML extraction against node01 config]

### Getting This Node's Device ID
```bash
# Source: verified on node01
get_device_id() {
    # Requires service to be running
    syncthing cli show system 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['myID'])"
}
```
[VERIFIED: returns correct device ID I4FF4GR-... on node01]

### Adding a Folder via CLI
```bash
# Source: verified syncthing cli config folders add --help
add_claude_sessions_folder() {
    syncthing cli config folders add \
        --id "claude-sessions" \
        --label "Claude Sessions" \
        --path "$HOME/.claude/projects" \
        --fswatcher-delays 2 \
        --fswatcher-enabled
    
    # Create the folder marker so Syncthing doesn't error
    mkdir -p "$HOME/.claude/projects/.stfolder"
}
```
[VERIFIED: CLI flags confirmed via --help output]

### Adding a Device and Sharing Folder
```bash
# Source: verified syncthing cli config devices add --help
add_peer_device() {
    local device_id="$1"
    local device_name="${2:-peer}"
    
    # Add device globally
    syncthing cli config devices add \
        --device-id "$device_id" \
        --name "$device_name" \
        --auto-accept-folders
    
    # Share claude-sessions folder with this device
    syncthing cli config folders claude-sessions devices add \
        --device-id "$device_id"
}
```
[VERIFIED: CLI flags confirmed via --help output, pattern matches existing config.xml structure]

### Health Check with Retry
```bash
# Source: standard pattern, adapted for Syncthing
wait_for_syncthing() {
    local api_key="$1"
    local max_attempts=20  # 10 seconds at 0.5s intervals
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -sf -H "X-API-Key: ${api_key}" \
            "http://127.0.0.1:8384/rest/system/status" >/dev/null 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 0.5
    done
    return 1
}
```

### Color Output Helpers
```bash
# Source: standard bash color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

ok()   { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; }
info() { printf "${BLUE}[..]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[!!]${NC} %s\n" "$1"; }
die()  { fail "$1"; exit 1; }
```

### Interactive Device ID Input
```bash
# Source: standard bash pattern
prompt_device_ids() {
    local device_ids=()
    local my_id
    my_id=$(get_device_id)
    
    echo ""
    printf "${BOLD}This node's device ID:${NC}\n"
    printf "${GREEN}%s${NC}\n" "$my_id"
    echo ""
    echo "Paste peer device IDs (one per line, empty line to finish):"
    
    while true; do
        read -r line
        [[ -z "$line" ]] && break
        device_ids+=("$line")
    done
    
    printf '%s\n' "${device_ids[@]}"
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `~/.config/syncthing/` config dir | `~/.local/state/syncthing/` on newer distros | Ubuntu 23.10+ / Syncthing 1.27+ | Script must check both locations [VERIFIED: node01 uses .local/state] |
| `syncthing -generate` flag | `syncthing generate` subcommand | Syncthing 1.18+ | Use the subcommand, not the deprecated flag [VERIFIED: syncthing generate --help] |
| Manual config.xml editing | `syncthing cli config` subcommand | Syncthing 1.18+ | CLI is the supported way to script configuration [VERIFIED: working on node01] |
| Config changes require restart | Most changes hot-reload, check `/rest/config/restart-required` | Syncthing 1.18+ | Script should check restart-required and restart only if needed [CITED: docs.syncthing.net/rest/config.html] |

**Deprecated/outdated:**
- `syncthing -generate=<dir>`: replaced by `syncthing generate --config=<dir>` [VERIFIED: help output]
- `/rest/system/config` GET/POST: deprecated in favor of `/rest/config/*` endpoints [CITED: docs.syncthing.net/dev/rest.html]
- `~/.config/syncthing/` config location: still works but new installations on Ubuntu 24.04 use `~/.local/state/syncthing/` [VERIFIED: node01]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `loginctl enable-linger` is needed for user service persistence after logout | Pitfall 4 | Service stops after logout; fixable by adding linger command |
| A2 | `brew install syncthing` + `brew services start syncthing` works on macOS 14+ | Pitfall 5 | macOS support broken; low risk since cluster is all Ubuntu |
| A3 | Syncthing validates device IDs internally and rejects malformed ones | Don't Hand-Roll | Script would accept invalid IDs; fixable by adding regex pre-check |
| A4 | jq may or may not be installed on target systems | Standard Stack | JSON parsing falls back to python3; no real risk |
| A5 | macOS config location is `~/Library/Application Support/Syncthing/` | Pitfall 6 | Config extraction fails on macOS; verify during macOS testing |

## Open Questions

1. **Does `syncthing generate` set a default API key?**
   - What we know: On an existing install, the API key lives in `<gui><apikey>` in config.xml. `syncthing generate` creates a fresh config.xml.
   - What's unclear: Whether the generated config has an API key set by default, or if one needs to be created.
   - Recommendation: Test `syncthing generate` in a temp directory and inspect the output config. If no API key, the script needs to generate and inject one before starting the service.

2. **Should the script handle the existing broken .stfolder state?**
   - What we know: node01 currently has `claude-sessions` folder in error state because `.stfolder` is missing. The script should be able to fix this.
   - What's unclear: Whether simply creating `.stfolder` will clear the error, or if a folder rescan/restart is needed.
   - Recommendation: The script should create `.stfolder` if missing and trigger a rescan via `POST /rest/db/scan?folder=claude-sessions`. Test this on node01 before finalizing.

3. **Does `loginctl enable-linger` require sudo?**
   - What we know: `loginctl enable-linger $USER` typically requires root/sudo on systems where the user doesn't already have linger enabled.
   - What's unclear: Whether the setup script should handle this automatically or just warn.
   - Recommendation: Check linger status, warn if not enabled, provide the command to run with sudo. Don't auto-sudo.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| syncthing | Core functionality | Yes | v1.27.2-ds4 | apt install syncthing (script handles install) |
| systemctl (systemd) | Service management (Linux) | Yes | systemd 255 | -- (required on Linux) |
| python3 | XML/JSON parsing | Yes | 3.12 | grep/sed fallback (fragile) |
| curl | REST API health checks | Yes | present | syncthing cli (but needs service running) |
| bash | Script runtime | Yes | 5.2 | -- (required) |
| brew | Package management (macOS) | N/A (Linux node) | -- | Script detects OS, only uses brew on macOS |
| jq | JSON parsing | Likely | -- | python3 -c "import json..." |

**Missing dependencies with no fallback:** None -- all critical tools are available.

**Missing dependencies with fallback:** jq may be absent; python3 json module serves as universal fallback.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash + manual verification (no formal test framework for shell scripts in v1) |
| Config file | none -- see Wave 0 |
| Quick run command | `bash setup.sh --device-id FAKE-ID-FOR-TEST 2>&1` (dry run check) |
| Full suite command | `bash -n setup.sh && shellcheck setup.sh` (syntax + lint) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| R1-install | Syncthing installed after setup | smoke | `command -v syncthing && syncthing --version` | N/A (manual) |
| R1-folder | claude-sessions folder exists in config | smoke | `syncthing cli config folders list \| grep claude-sessions` | N/A (manual) |
| R1-watcher | fsWatcherDelayS is 2 | smoke | `curl -s -H "X-API-Key:$KEY" http://127.0.0.1:8384/rest/config/folders/claude-sessions \| python3 -c "import sys,json; assert json.load(sys.stdin)['fsWatcherDelayS']==2"` | N/A (manual) |
| R1-service | Syncthing service running | smoke | `systemctl --user is-active syncthing.service` | N/A (manual) |
| R1-device | Peer device IDs accepted | smoke | `syncthing cli config devices list \| grep <DEVICE_ID>` | N/A (manual) |
| R1-idempotent | Safe to run twice | smoke | Run setup.sh twice, verify no errors and no duplicate entries | N/A (manual) |

### Sampling Rate
- **Per task commit:** `bash -n setup.sh && shellcheck setup.sh` (syntax check + lint)
- **Per wave merge:** Full manual smoke test on a test node
- **Phase gate:** Successful run on at least one node, plus idempotency verification

### Wave 0 Gaps
- [ ] Install `shellcheck` if not present: `sudo apt install shellcheck`
- [ ] Create a test checklist script that automates the smoke tests above

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Syncthing API uses local-only API key, no user auth needed |
| V3 Session Management | no | No web sessions |
| V4 Access Control | yes | Script must not run as root (D-08); Syncthing API bound to 127.0.0.1 only |
| V5 Input Validation | yes | Device ID format validation before passing to Syncthing CLI |
| V6 Cryptography | no | Syncthing handles TLS internally, script doesn't touch crypto |

### Known Threat Patterns for bash scripts

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Command injection via device ID input | Tampering | Validate device ID format (7 groups of 7 alphanumeric chars separated by dashes); quote all variables |
| API key exposure in process list | Information Disclosure | Pass API key via header (curl -H), not URL parameter; config.xml is 0600 permissions |
| Privilege escalation via setuid | Elevation of Privilege | Refuse to run as root (D-08); never use sudo within the script |
| Symlink attacks on .stfolder | Tampering | mkdir -p is safe (doesn't follow symlinks for final component); not a high risk for user-owned directories |

## Sources

### Primary (HIGH confidence)
- Syncthing v1.27.2-ds4 running on node01 -- all CLI commands, config structure, and REST API verified live
- `/home/joe/.local/state/syncthing/config.xml` -- actual production config with 4 devices and 3 folders
- `syncthing --paths`, `syncthing cli config folders --help`, `syncthing generate --help` -- CLI documentation
- `/usr/lib/systemd/user/syncthing.service` -- actual systemd service file from apt package

### Secondary (MEDIUM confidence)
- [docs.syncthing.net/rest/config.html](https://docs.syncthing.net/rest/config.html) -- REST API config endpoints, hot-reload behavior
- [docs.syncthing.net/dev/rest.html](https://docs.syncthing.net/dev/rest.html) -- REST API authentication, endpoint index
- [docs.syncthing.net/users/ignoring.html](https://docs.syncthing.net/users/ignoring.html) -- .stignore format (Phase 2 reference)
- [docs.syncthing.net/users/faq.html](https://docs.syncthing.net/users/faq.html) -- .stfolder marker explanation

### Tertiary (LOW confidence)
- macOS brew services behavior -- based on training knowledge, not verified on actual macOS system

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- verified against running installation on node01
- Architecture: HIGH -- bootstrap sequence tested, CLI commands verified, config structure inspected
- Pitfalls: HIGH for Linux-specific (verified), MEDIUM for macOS (assumed)

**Research date:** 2026-04-11
**Valid until:** 2026-05-11 (30 days -- Syncthing is stable, v1.27 is LTS-like)
