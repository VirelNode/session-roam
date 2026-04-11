---
phase: 01-setup-script
verified: 2026-04-11T06:00:00Z
status: human_needed
score: 8/8 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Run setup.sh on a node with Syncthing already installed"
    expected: "Prints 'already installed', configures (or confirms) claude-sessions folder, prompts for device IDs (enter empty line to skip), prints summary block with this node's device ID, exits 0"
    why_human: "Requires a live Syncthing daemon and real API responses. Cannot simulate REST API calls or syncthing CLI calls programmatically without running the service."
  - test: "Run setup.sh a second time immediately after (idempotency)"
    expected: "All 'already known'/'already configured' messages appear, no duplicate entries in syncthing config, exits 0"
    why_human: "Requires live Syncthing config state to verify no duplicate folders or devices are created."
  - test: "Confirm Syncthing folder config after first run"
    expected: "'syncthing cli config folders list' includes 'claude-sessions'; 'syncthing cli config folders claude-sessions type get' returns 'sendreceive'; REST API query returns fsWatcherDelayS=2"
    why_human: "Requires live Syncthing CLI and running service to query config state."
---

# Phase 1: Setup Script Verification Report

**Phase Goal:** One-command Syncthing configuration for Claude Code session sync
**Verified:** 2026-04-11T06:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Running setup.sh on a fresh node installs Syncthing if not present | VERIFIED | `apt-get install -y syncthing` (line 145) and `brew install syncthing` (line 148) inside `command -v syncthing` guard (line 139) |
| 2 | Running setup.sh configures a claude-sessions shared folder at ~/.claude/projects/ | VERIFIED | `syncthing cli config folders add --id "claude-sessions" --path "$HOME/.claude/projects"` (lines 255-261) |
| 3 | fsWatcherDelayS is set to 2 on the claude-sessions folder | VERIFIED | `--fswatcher-delays 2` in add branch (line 260); `fswatcher-delays set 2` in idempotent branch (line 252). Both paths covered. |
| 4 | claude-sessions folder type is sendreceive | VERIFIED | `--type sendreceive` in add branch (line 259); `type set sendreceive` in idempotent branch (line 253). Both paths covered. |
| 5 | Syncthing runs as a systemd user service (Linux) or brew service (macOS) | VERIFIED | `systemctl --user enable syncthing.service` + `start` (lines 192-193); `brew services start syncthing` (line 203) |
| 6 | Peer device IDs can be added via --device-id flags or interactive prompt | VERIFIED | Argument parsing at lines 91-107; interactive `read -r line` loop at lines 282-287; `add_peer_device` adds both globally and to folder |
| 7 | Running setup.sh a second time produces no errors and no duplicate config | VERIFIED (static) | Folder guard: `folders list | grep -q "^claude-sessions$"` (line 249); device guard: `devices list | grep -q "^${device_id}$"` (line 230); install guard: `command -v syncthing` (line 139) |
| 8 | The script refuses to run as root | VERIFIED | `[[ $EUID -eq 0 ]] && die "Do not run as root."` (line 114) |

**Score:** 8/8 truths verified (static code analysis)

Note: Truths 1, 2, 3, 4, 5, 6 require a live Syncthing service to confirm runtime behavior. Static analysis confirms all code paths are implemented and wired correctly. Live execution is routed to human verification.

### Deferred Items

None. Phase 1 claims only R1, which is fully addressed by setup.sh.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `setup.sh` | One-command Syncthing setup for Claude Code session sync | VERIFIED | 348 lines (min 250), executable (-rwxrwxr-x), contains `set -euo pipefail` at line 2, LF line endings confirmed (0 CRLF chars) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `setup.sh` | `syncthing cli config folders` | CLI commands after service is running | WIRED | `syncthing cli config folders add` (line 255), `syncthing cli config folders list` (line 249), `syncthing cli config folders claude-sessions fswatcher-delays set 2` (line 252), `syncthing cli config folders claude-sessions type set sendreceive` (line 253) — 11 total occurrences |
| `setup.sh` | `~/.claude/projects/` | shared folder path configuration | WIRED | `mkdir -p "$HOME/.claude/projects"` (line 133), `--path "$HOME/.claude/projects"` (line 258), `.stfolder` marker at line 266 — 5 path references |
| `setup.sh` | `systemctl --user` | service management | WIRED | `systemctl --user enable syncthing.service` (line 192) + `systemctl --user start syncthing.service` (line 193) inside Linux OS branch |

### Data-Flow Trace (Level 4)

Not applicable — setup.sh is a bash infrastructure script, not a component that renders dynamic data from a state variable or API response.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Script passes bash syntax check | `bash -n setup.sh` | exit 0 | PASS |
| Script is shellcheck-clean (all severities) | `shellcheck setup.sh` | exit 0, zero findings | PASS |
| set -euo pipefail present | `grep -c 'set -euo pipefail' setup.sh` | 1 | PASS |
| LF line endings only | `grep -cP '\r' setup.sh` | 0 | PASS |
| Minimum 250 lines | `wc -l setup.sh` | 348 | PASS |
| claude-sessions used in 5+ places (per plan verification criterion) | `grep -c 'claude-sessions' setup.sh` | 11 | PASS |
| device-id used in 3+ places | `grep -c 'device-id\|device_id' setup.sh` | 12 | PASS |
| type sendreceive explicit | `grep -c 'type sendreceive\|--type sendreceive' setup.sh` | 1 (`--type sendreceive` in add; `type set sendreceive` via CLI in idempotent branch) | PASS |
| Live execution (Syncthing service required) | `bash setup.sh` | NOT RUN | SKIP — routed to human verification |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| R1 | 01-01-PLAN.md | Install Syncthing if not present (apt/brew), configure claude-sessions folder at ~/.claude/projects/, fsWatcherDelayS=2, enable+start systemd user service, accept device IDs (interactive or via args), idempotent | SATISFIED | All 6 sub-requirements implemented and verified above. SUMMARY confirms requirements-completed: [R1]. |

No orphaned requirements: ROADMAP.md maps only R1 to Phase 1. R2-R6 are scoped to Phases 2-4.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | — |

No TODOs, FIXMEs, placeholders, empty returns, or hardcoded empty data found. Script is clean.

### Human Verification Required

#### 1. Live Execution on Configured Node

**Test:** Run `bash setup.sh` on any node where Syncthing is already running.
**Expected:**
- "Syncthing already installed (syncthing vX.Y.Z)" printed
- "claude-sessions folder already configured" OR "claude-sessions folder created" printed
- Interactive prompt shows this node's device ID, accepts empty line to skip
- Summary block prints: device ID, path `~/.claude/projects`, ID `claude-sessions`, type `sendreceive`, fsWatcherDelayS `2`
- Exit code 0

**Why human:** Requires live Syncthing daemon. Script calls `syncthing cli config`, `syncthing cli show system`, and REST API endpoints that cannot be tested without the service running.

#### 2. Idempotency Run

**Test:** Run `bash setup.sh` a second time immediately after the first.
**Expected:**
- "Syncthing already installed" — not re-installed
- "claude-sessions folder already configured" — not re-added
- No errors about duplicate folder or device IDs
- Exit code 0

**Why human:** Requires live Syncthing config state. The idempotency guards (`folders list | grep`, `devices list | grep`) only work against real config.

#### 3. Confirm Syncthing Config After Setup

**Test:** After running setup.sh, query the live config:
```
syncthing cli config folders list
syncthing cli config folders claude-sessions type get
curl -sf -H "X-API-Key:$(python3 -c "import xml.etree.ElementTree as ET; print(ET.parse('$(syncthing --paths | grep -A1 Configuration | tail -1 | tr -d ' ')').getroot().find('gui/apikey').text)")" http://127.0.0.1:8384/rest/config/folders/claude-sessions | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'fsWatcherDelayS={d[\"fsWatcherDelayS\"]} type={d[\"type\"]}')"
```
**Expected:** `claude-sessions` in folder list; `type get` returns `sendreceive`; REST returns `fsWatcherDelayS=2 type=sendreceive`
**Why human:** Requires live Syncthing running and config populated by the setup run.

### Gaps Summary

No gaps. All 8 must-have truths are verified at the code level. All artifacts exist, are substantive (348 lines, shellcheck-clean), and all key links are wired. The 3 human verification items are runtime/behavioral checks that cannot be completed without a live Syncthing service — they do not indicate code defects.

The phase goal — "One-command Syncthing configuration for Claude Code session sync" — is achieved by setup.sh as written. Pending human confirmation of runtime behavior.

---

_Verified: 2026-04-11T06:00:00Z_
_Verifier: Claude (gsd-verifier)_
