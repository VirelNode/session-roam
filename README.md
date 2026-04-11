# session-roam

Cross-node Claude Code session continuity using Syncthing. Resume any conversation from any machine in your cluster.

## What This Does

Claude Code stores conversations as `.jsonl` files in `~/.claude/projects/`. This tool syncs that directory across all your machines using Syncthing. Combined with `claude -c` (continue) and `claude -r` (resume), you can:

- Finish a conversation on your desktop, walk to your laptop, type `cr`, and pick up exactly where you left off
- Browse ALL past sessions from ANY node with `cs`
- Search for specific conversations with `cf "keyword"`
- Name sessions for easy recall with `cn "project name"`
- Fork old conversations without modifying the original with `cfork`

## Quick Start

```bash
# On your first machine:
git clone https://github.com/VirelNode/session-roam.git
cd session-roam
./setup.sh

# Note the device ID it prints. Then on your second machine:
./setup.sh --device-id <FIRST_MACHINE_DEVICE_ID>

# Go back to the first machine and add the second:
./setup.sh --device-id <SECOND_MACHINE_DEVICE_ID>

# Install session shortcuts on each machine:
./install-aliases.sh
source ~/.bashrc

# Verify everything works:
./verify.sh
```

## Requirements

- Two or more machines with Claude Code installed
- Same username and project paths across machines (e.g., both have `/home/joe/Desktop`)
- Ubuntu/Debian or macOS (for the setup script)
- Network connectivity between machines (LAN, Tailscale, or internet)

## Session Shortcuts

| Command | What It Does |
|---------|-------------|
| `cr` | Continue your most recent conversation (2s sync delay) |
| `cs` | Browse all past sessions interactively |
| `cf "keyword"` | Search sessions by keyword |
| `cn "name"` | Start a new named session |
| `cfork ID` | Resume a past session without modifying the original |
| `crf` | Branch off your most recent conversation |

## How It Works

1. **Syncthing** syncs `~/.claude/projects/` peer-to-peer across your machines
2. **fsWatcherDelayS=2** means changes propagate in ~2 seconds
3. **`claude -c`** finds the most recent `.jsonl` session file and reopens it
4. **`claude -r`** lets you browse and search all sessions interactively
5. The **2-second sleep** in `cr` gives Syncthing time to finish propagating

No server. No cloud. No single point of failure. Just P2P file sync.

## Files

| File | Purpose |
|------|---------|
| `setup.sh` | Install Syncthing, configure shared folder, pair devices |
| `install-aliases.sh` | Install session shortcuts + `.stignore` |
| `verify.sh` | Health check (8 dimensions: service, API, folder, peers, sessions, ignore, conflicts, shortcuts) |
| `stignore.template` | Syncthing ignore patterns — skip worktrees, caches, keep sessions + memory |

## The Rules

1. **One active session at a time.** Exit your conversation before resuming on another machine. Two nodes writing the same `.jsonl` simultaneously will create sync conflicts.
2. **Context window limits apply.** A long session (100+ turns) will only load the most recent portion when resumed — older context gets compacted.
3. **Investigate conflict files.** If `verify.sh` reports `.sync-conflict-*` files, it means concurrent writes happened. Check which version has the data you want.

## The Discovery Story

This wasn't planned. On the night of April 10, 2026, Joe Daily and Claude were doing cluster maintenance — BIOS flashes, driver upgrades, firmware updates across a 4-node homelab. After rebooting node01, `claude -c` on a different node picked up the conversation like nothing happened.

Syncthing had been silently syncing the home directory. The session files came along for the ride.

Five beers and a "what if?" later, this repo was born.

Phase 1 (setup.sh) was built by CC on node01 during that same marathon session. Phase 2 (aliases + .stignore) and Phase 3 (verify.sh) were built by CC on node05 the following night — after a rescue operation to bring node01's instance up to speed. The repo itself is a cross-instance collaboration.

## Troubleshooting

**`cr` says "no conversation to continue"**
- The session file hasn't synced yet. Wait a few seconds and try again.
- Check `verify.sh` to see if Syncthing has connected peers.

**`verify.sh` shows sync conflicts**
- Look at the conflict file names — they'll have `.sync-conflict-YYYYMMDD-HHMMSS` in them.
- Compare with the original file. Keep whichever has more/better data.
- Delete the conflict file once resolved.

**No peers connected**
- Make sure Syncthing is running on the other machine (`verify.sh` checks this).
- Exchange device IDs: run `setup.sh` on both machines.
- If behind NAT, Syncthing uses relay servers automatically.

**Sessions not appearing on other nodes**
- Check that both machines have the same project path (e.g., both use `~/Desktop` as working directory).
- Run `verify.sh` on both nodes — compare session counts.
- Check `syncthing cli show connections` for sync status.

## What This Doesn't Do

- **Memory database sync** — sqlite-vec databases are separate infrastructure.
- **Context window management** — long sessions will still compact.
- **Multi-user support** — requires same username across machines.
- **Cloud sync** — this is LAN/Tailscale only (Syncthing can work over internet, but that's on you to secure).

## License

MIT
