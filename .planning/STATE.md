# State — session-roam

## Current Phase
Phase 1: Setup Script

## Status
Initialized — ready for `/gsd-plan-phase 1`

## Decisions
- Syncthing over NFS (P2P, no single point of failure, works over Tailscale)
- fsWatcherDelayS=2 (near-instant on 100GbE, fast enough on WiFi)
- Scope limited to session transcript sync for v1 (no memory DB sync)
- Private repo initially, public when polished

## Context
- Proven working on 4-node cluster: node01 (Threadripper), node02 (7950X3D), node03 (5900X), node05 (laptop)
- All nodes run Ubuntu 24.04, same username (joe), identical paths
- 100GbE between desktop nodes, Tailscale for laptop
- Discovered accidentally 2026-04-10 during cluster maintenance
