# session-roam

Cross-node session continuity for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Sync conversations across machines using Syncthing and resume from any node in your cluster.

## Overview

Claude Code stores conversations as `.jsonl` files in `~/.claude/projects/`. session-roam syncs that directory peer-to-peer across your machines, enabling seamless session handoff between nodes.

**Core workflow:** exit a session on one machine, walk to another, type `cr`, and continue where you left off.

## Requirements

- Two or more machines running Claude Code
- Matching usernames and project paths across machines
- Ubuntu/Debian or macOS
- Network connectivity (LAN, Tailscale, or internet)

## Quick Start

```bash
# First machine
git clone https://github.com/VirelNode/session-roam.git
cd session-roam
./setup.sh

# Second machine — use the device ID printed by the first
./setup.sh --device-id <FIRST_MACHINE_DEVICE_ID>

# Back on the first machine — add the second
./setup.sh --device-id <SECOND_MACHINE_DEVICE_ID>

# Both machines — install shortcuts and verify
./install-aliases.sh
source ~/.bashrc
./verify.sh
```

Repeat for additional nodes. Each machine needs the device IDs of its peers.

## Commands

| Command | Description |
|---------|-------------|
| `cr` | Resume most recent session (with namespace and staleness checks) |
| `cr --force` | Resume immediately, skip all checks |
| `cs` | Browse past sessions interactively |
| `cf "keyword"` | Search sessions by keyword |
| `cn "name"` | Start a new named session |
| `cfork ID` | Fork a past session (original stays unmodified) |
| `crf` | Fork the most recent session |

## How It Works

1. **Syncthing** syncs `~/.claude/projects/` peer-to-peer with a 2-second file watcher delay
2. **`claude -c`** reopens the most recent `.jsonl` session file for the current directory
3. **`claude -r`** provides an interactive session browser across all namespaces
4. **`cr`** wraps `claude -c` with a 2-second delay (for sync propagation), namespace validation, and stale session warnings

No central server. No cloud dependency. Peer-to-peer only.

## Files

| File | Purpose |
|------|---------|
| `setup.sh` | Install Syncthing, configure the shared folder, pair devices |
| `install-aliases.sh` | Install shell aliases and `.stignore` patterns |
| `verify.sh` | Health check across 9 dimensions (service, API, folder, peers, sessions, ignore, conflicts, shortcuts, agent isolation) |
| `cr.sh` | Smart resume wrapper with namespace and staleness checks |
| `stignore.template` | Syncthing ignore patterns (skip worktrees and caches, keep sessions and memory) |
| `CONVENTIONS.md` | Session namespacing conventions for multi-agent setups |

## Important Constraints

- **One writer at a time.** Always exit a session before resuming on another machine. Two nodes writing the same `.jsonl` concurrently will produce Syncthing conflict files.
- **Context window limits still apply.** Long sessions compact older context when resumed.
- **Resolve conflicts promptly.** If `verify.sh` reports `.sync-conflict-*` files, compare versions and keep the one with the data you need.

## Troubleshooting

**"No conversation to continue"**
- Session file may not have synced yet. Wait a few seconds and retry.
- Run `verify.sh` to check peer connectivity.

**Sync conflicts detected**
- Conflict files are named `.sync-conflict-YYYYMMDD-HHMMSS`.
- Compare the conflict file with the original. Keep the better version, delete the other.

**No peers connected**
- Confirm Syncthing is running on both machines (`verify.sh` checks this).
- Ensure device IDs have been exchanged: run `setup.sh` on both nodes.
- Behind NAT, Syncthing uses relay servers automatically.

**Sessions not appearing on other nodes**
- Verify both machines use the same working directory (e.g., both use `~/Desktop`).
- Run `verify.sh` on both nodes and compare session counts.
- Check connectivity with `syncthing cli show connections`.

## Limitations

- Does not sync memory databases (sqlite-vec, Qdrant, etc.) — those require separate infrastructure.
- Does not manage context window compaction.
- Requires the same OS username on all machines.
- LAN/Tailscale only by default. Internet sync is possible but you are responsible for securing it.

## License

MIT
