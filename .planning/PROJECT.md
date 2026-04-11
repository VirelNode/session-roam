# session-roam

## Vision
Cross-node Claude Code session continuity using Syncthing. Resume any session from any machine in your cluster.

## Problem
Claude Code sessions are tied to a single machine. `claude -c` only finds sessions stored locally in `~/.claude/projects/`. Developers working across multiple machines (homelab nodes, desktop + laptop, workstations) lose session context when switching machines.

## Solution
Use Syncthing to peer-to-peer sync `~/.claude/projects/` across all machines. Combined with identical filesystem paths (same username, same project directories), `claude -c` seamlessly resumes sessions from any node.

## Key Requirements
- Same username and project paths across all machines (e.g., `/home/joe/Desktop`)
- Syncthing installed on all nodes with P2P connectivity
- 2-second file watcher delay for near-instant propagation
- Only one active session at a time (exit before resuming elsewhere)

## What This Repo Provides
- Setup script: install Syncthing, configure shared folder, set watcher delay
- `.stignore` template optimized for ~/.claude/ (skip node_modules, caches, etc.)
- `cr` alias wrapper script
- Verification/test scripts
- Documentation with setup guide and discovery story

## Tech Stack
- Bash (setup scripts)
- Syncthing (peer-to-peer file sync)
- No external dependencies beyond Syncthing

## Discovery
Accidentally discovered during a cluster maintenance session on April 10, 2026. Joe Daily and Claude were updating BIOS, drivers, and firmware across a 4-node homelab cluster. After rebooting, `claude -c` on a different node picked up the session — Syncthing had been silently syncing the home directory. Five beers and a "what if?" later, this repo was born.

## Constraints
- Sessions must NOT be open on multiple nodes simultaneously (causes JSONL conflicts)
- Long sessions (100+ turns) will lose older context on resume due to context window limits
- Syncthing conflict files indicate concurrent writes — investigate, don't ignore
- This syncs session transcripts only — memory databases (sqlite-vec) are separate infrastructure

## Team
- Joe Daily — architecture, testing, infrastructure
- Claude — implementation, documentation, research
