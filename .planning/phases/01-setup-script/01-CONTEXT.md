# Phase 1: Setup Script - Context

**Gathered:** 2026-04-11
**Status:** Ready for planning

<domain>
## Phase Boundary

One-command Syncthing configuration for Claude Code session sync. The script installs Syncthing (if needed), configures a shared folder pointing to `~/.claude/projects/`, sets optimal sync parameters, enables the systemd user service, and accepts device IDs for peering. Must be idempotent — safe to run on a node that's already configured.

</domain>

<decisions>
## Implementation Decisions

### Installation Strategy
- **D-01:** Detect package manager (apt on Ubuntu/Debian, brew on macOS). Install Syncthing if not present, skip if already installed. No snap — apt or brew only.
- **D-02:** Script must work on Ubuntu 22.04+ and macOS 14+ (the actual cluster runs Ubuntu 24.04, but keep it portable for open-source release).

### Device Pairing UX
- **D-03:** Accept device IDs via `--device-id <ID>` flags (repeatable for multiple peers). If no flags provided, prompt interactively: display this node's device ID and ask user to paste peer IDs one per line, empty line to finish.
- **D-04:** Display this node's device ID prominently at the end of setup so the user can share it with other nodes.

### Output Verbosity
- **D-05:** Step-by-step progress messages with color (green checkmarks for success, red X for failures). No --verbose or --quiet flags for v1 — single output mode.
- **D-06:** Final summary block showing: node device ID, shared folder path, connected peers, sync status.

### Error Recovery
- **D-07:** Fail fast (`set -euo pipefail`) with a trap for cleanup messages. Each step prints what it's doing before doing it, so the user knows where it failed.
- **D-08:** Pre-flight checks at script start: confirm not running as root (Syncthing uses user services), confirm systemd is available (or launchd on macOS).

### Syncthing Configuration
- **D-09:** Shared folder ID: `claude-sessions`. Path: `~/.claude/projects/`. fsWatcherDelayS: 2. These are the values proven on the 4-node cluster.
- **D-10:** Folder type: Send & Receive (bidirectional sync). No ignore-delete, no versioning for v1.
- **D-11:** Syncthing API accessed via localhost REST API (default port 8384). Script reads/writes config via `syncthing cli` or direct REST calls.

### Service Management
- **D-12:** Enable and start Syncthing as a systemd user service (`systemctl --user enable syncthing` / `systemctl --user start syncthing`). On macOS, use `brew services start syncthing`.
- **D-13:** Verify service is running after start (health check with retry — wait up to 10s for API to respond).

### Claude's Discretion
- Exact color codes and formatting of output messages
- Whether to use `syncthing cli` commands vs direct REST API calls (whichever is more reliable)
- Temporary file handling during configuration
- Order of configuration steps (as long as the end state is correct)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

No external specs — requirements fully captured in decisions above. The Syncthing REST API documentation (https://docs.syncthing.net/dev/rest.html) is the authoritative reference for configuration operations.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — this is a greenfield repo with no existing code.

### Established Patterns
- None yet — this script establishes the project's first patterns.

### Integration Points
- The script creates the foundation that Phase 2 (.stignore + alias) and Phase 3 (verify.sh) build upon.
- Output format (colors, status symbols) should be consistent across all scripts.

</code_context>

<specifics>
## Specific Ideas

- The script was born from a real discovery on a 4-node cluster (node01 Threadripper, node02 7950X3D, node03 5900X, node05 laptop) with 100GbE between desktops and Tailscale for laptop.
- `fsWatcherDelayS=2` was empirically chosen — near-instant on 100GbE, fast enough on WiFi.
- The `cr` alias (`sleep 2 && claude -c`) gives Syncthing a beat to propagate — this is Phase 2 but informs the setup script's timing expectations.
- Session files are JSONL in `~/.claude/projects/` — the critical sync target.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-setup-script*
*Context gathered: 2026-04-11 via --auto mode*
