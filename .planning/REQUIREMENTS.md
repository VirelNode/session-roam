# Requirements — session-roam

## R1: Setup Script
- Install Syncthing if not present (apt/brew)
- Configure `claude-sessions` shared folder pointing to `~/.claude/projects/`
- Set `fsWatcherDelayS` to 2 seconds
- Enable and start Syncthing as user systemd service
- Accept device IDs from other nodes (interactive or via args)
- Idempotent — safe to run multiple times

## R2: .stignore Template
- Skip `node_modules`, `__pycache__`, `.venv`, build artifacts
- Skip browser data, large caches, Docker buildx
- Skip Syncthing internals (`.stversions`, `.stfolder`)
- Preserve all `.jsonl` session files, `sessions-index.json`, `memory/` directories
- Template placed in the synced directory root

## R3: Resume Wrapper
- `cr` alias: `sleep 2 && claude -c` (Syncthing propagation beat)
- Optional: `cr <session-name>` for named session resume
- Installs to `~/.bashrc` and/or `~/.zshrc`
- Non-destructive (checks before appending)

## R4: Verification Script
- Confirm Syncthing is running on current node
- Confirm `claude-sessions` folder exists and is synced
- Check connected devices and sync status
- Verify file watcher delay is 2s
- Report any `.sync-conflict` files (indicates concurrent write problems)
- Check that session files exist and are recent

## R5: Documentation
- README with setup guide, requirements, and usage
- The discovery story (how we found this)
- Limitations section (context window, single-active-session rule)
- Troubleshooting guide
- Contributing guide

## R6: Safety Guardrails
- Pre-flight check: warn if same session is already active on another node
- `.sync-conflict` file detection and alerting
- LF line ending enforcement for any generated scripts
- Git autocrlf=input recommendation in setup

## Non-Requirements (Explicitly Out of Scope for v1)
- Memory database (sqlite-vec) sync — separate infrastructure
- MemOS integration
- Context window management / anti-compaction
- NFS or cloud-based alternatives to Syncthing
- Multi-user support
