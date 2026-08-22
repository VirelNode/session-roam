# Architecture — session-roam

## Overview

session-roam enables cross-node Claude Code session continuity using Syncthing for peer-to-peer file synchronization. No servers, no cloud, no custom daemons — just P2P sync of session transcript files.

## How Claude Code Stores Sessions

Claude Code persists conversations as JSONL files:

```
~/.claude/projects/-home-joe-Desktop/
  sessions-index.json          # Index of all sessions for this project path
  <session-id>.jsonl           # Full conversation transcript (append-only)
  <session-id>/subagents/      # Sub-agent transcripts
  <session-id>/tool-results/   # Cached tool outputs
  memory/                      # Auto-memory files (cross-session knowledge)
    MEMORY.md                  # Index of memory files
    *.md                       # Individual memory entries
```

Sessions are indexed by **working directory path**. `claude -c` finds the most recent session for the current directory. This means cross-node resume requires identical filesystem paths (same username, same project directories).

## Architecture Diagram

```
┌─────────────┐     Syncthing P2P      ┌─────────────┐
│   node01    │◄──────────────────────► │   node02    │
│ ~/.claude/  │   fsWatcher: 2s         │ ~/.claude/  │
│  projects/  │   100GbE / Tailscale    │  projects/  │
└──────┬──────┘                         └──────┬──────┘
       │                                       │
       │         ┌─────────────┐               │
       └────────►│   node03    │◄──────────────┘
                 │ ~/.claude/  │
                 │  projects/  │
                 └──────┬──────┘
                        │
                        │     Tailscale
                 ┌──────▼──────┐
                 │   node05    │
                 │  (laptop)   │
                 │ ~/.claude/  │
                 │  projects/  │
                 └─────────────┘
```

## Components

### setup.sh
- Installs Syncthing if not present (apt)
- Configures `claude-sessions` shared folder pointing to `~/.claude/projects/`
- Sets `fsWatcherDelayS=2` for near-instant file change detection
- Enables Syncthing as user systemd service
- Exchanges device IDs with peer nodes
- Idempotent — safe to run multiple times

### install-aliases.sh
- Installs 6 shell aliases to `~/.bashrc`:
  - `cr` — smart resume (runs cr.sh wrapper)
  - `cs` — browse all sessions interactively
  - `cf keyword` — search sessions by keyword
  - `cn name` — start a named session
  - `cfork ID` — fork a past session
  - `crf` — fork the most recent session
- Copies `cr.sh` to `~/.local/bin/`
- Copies `lib/session-lock.sh` to `~/.local/lib/session-roam/`

### cr.sh (Smart Resume Wrapper)
- Checks CWD namespace (warns if not `~/Desktop` — the personal session space)
- Detects stale sessions
- Enforces the one-writer rule via a cross-node session lock (see below)
- Supports `--force` to bypass warnings and lock blocks
- Sleeps 2 seconds before `claude -c` to allow Syncthing propagation
- Releases the lock on EXIT/INT/TERM/HUP — SIGHUP covers terminal close, SSH disconnect, and tmux kill, which terminate bash without running EXIT traps

### lib/session-lock.sh (Cross-node Session Lock)
Advisory lease file inside the synced tree: `~/.claude/projects/<namespace>/.roam-lock.json`, written atomically (`*.roam-lock.tmp` then rename; temp pattern is `.stignore`d so the flicker never propagates or conflicts). Content identifies holder node, pid, tty, start time. Classification ladder on resume:

| State | Meaning | cr.sh behavior |
|---|---|---|
| none | no lock | acquire |
| self-stale | our node, pid dead (crash/reboot leftover) | clear silently, acquire fresh |
| self-active | our node, pid alive | hard block (another terminal here) |
| remote-fresh (< `ROAM_FRESH_SECS`, default 900) | other node recently | hard block |
| remote-stale (>= threshold) | probably crashed holder | warn with evidence, `[y/N]` |
| unknown | unreadable/corrupt lock file | fail closed |

Any successful proceed takes ownership of the lock. Release uses an ownership guard so a late exit can never delete a newer holder's lock.

**Failure modes:** A node that crashes mid-session leaves its lock behind; nothing on disk distinguishes "crashed yesterday" from "idle open for 3 days", so remote locks are never auto-deleted — they age out of the hard-block tier into a warned override, and `verify.sh` dimension 10 surfaces every lock with holder and age. If Syncthing is down the guard is blind cross-node (degrades to pre-lock behavior). Two resumes inside the ~2s propagation window remain a theoretical race, vastly narrower than before. PID reuse can make a dead wrapper look alive until that pid cycles.

### verify.sh
10-dimension health check:
1. Syncthing service running
2. Syncthing API accessible
3. `claude-sessions` folder configured
4. Peer devices connected
5. Session file counts across nodes
6. `.stignore` deployed
7. Conflict file detection (`.sync-conflict` files)
8. Shell shortcuts installed
9. Agent isolation (federation sessions not polluting personal namespace)
10. Session locks (holder, age, class; abandoned `.roam-lock.tmp` residue >1h)

### stignore.template
Selective sync rules — only session-critical files cross the wire:
- **Synced**: `.jsonl` session files, `sessions-index.json`, `memory/` directories
- **Excluded**: worktrees, subagent transcripts, node_modules, caches, build artifacts, `.stversions`

### CONVENTIONS.md
Session namespacing rules:
- `~/Desktop` → personal sessions (Joe + Lead Claude)
- `~/Projects/<name>` → project-scoped sessions
- Federation agents should use project-specific CWDs, not `~/Desktop`
- Collision risk: Zellij panes starting from `~/Desktop` can pollute the personal namespace

## Key Design Decisions

### Why Syncthing (not NFS, not cloud sync)
- **No single point of failure** — if any node goes down, others retain full copies
- **Works over Tailscale** — laptop syncs over VPN when off-LAN
- **Peer-to-peer** — no central server to maintain
- **Conflict detection** — creates `.sync-conflict` files instead of silently corrupting
- **Battle-tested** — mature, stable, low-overhead

### Why 2-Second File Watcher
- Near-instant on 100GbE LAN (sub-second actual propagation)
- Fast enough on Tailscale/WiFi (~3-5 seconds end-to-end)
- Default 10s was too slow for the "walk to another node" workflow

### One-Writer Rule
Sessions must only be active on ONE node at a time. The JSONL format is append-only, so concurrent writers from multiple nodes would interleave messages and corrupt the conversation. Syncthing detects this and creates conflict files, but prevention is better than cure: `cr` now enforces the rule with a cross-node session lock (`lib/session-lock.sh`) instead of relying on discipline alone.

### CWD-Based Namespacing
Claude Code maps working directory → session directory name. This is a Claude Code convention, not ours. We leverage it for isolation: personal sessions live under `~/Desktop`, project work under `~/Projects/<name>`. Federation agents should never start sessions from `~/Desktop`.

## Limitations

- **Context window**: Long sessions (100+ turns) lose older context on resume regardless of sync — this is a Claude Code context window limit, not a session-roam issue
- **Memory DBs**: session-roam syncs transcripts only. sqlite-vec memory databases are separate infrastructure
- **Path dependency**: All nodes must have identical project paths (`/home/joe/Desktop`, same username)
- **No Windows support**: Syncthing works on Windows but Claude Code session paths differ

## Discovery Story

Accidentally discovered during a cluster maintenance session on April 10, 2026. Joe and Claude were updating BIOS, drivers, and firmware across a 4-node homelab. After rebooting node03 and walking to node01, `claude -c` picked up the session — Syncthing had been silently syncing the home directory. Five beers and a "what if?" later, this repo was born.

## Related Projects

- **session-roam-cluster** (private) — Federation/IOSTUI integration, conflict resolution, multi-agent session protocol
- **agent-reliability** (private) — Stuck detection, tool dedup, verification gates for Claude Code agents
- **memory-operating-system** (private) — Unified memory read/write plane across all agents and nodes
