# Roadmap — session-roam

## Milestone 1: v0.1.0 — Core Functionality

### Phase 1: Setup Script
**Goal:** One-command Syncthing configuration for Claude Code session sync
**Requirements:** R1
**Deliverables:** `setup.sh` — install, configure, and verify Syncthing
**Plans:** 1 plan

Plans:
- [x] 01-01-PLAN.md — Create setup.sh: install Syncthing, configure claude-sessions folder, device pairing, service management

### Phase 2: Ignore Patterns + Resume Wrapper
**Goal:** Optimized sync with smart exclusions and quick resume alias
**Requirements:** R2, R3
**Deliverables:** `.stignore` template, `cr` alias installer

### Phase 3: Verification + Safety
**Goal:** Confirm sync is working and detect problems before they cause data loss
**Requirements:** R4, R6
**Deliverables:** `verify.sh`, conflict detection, pre-flight checks

### Phase 4: Documentation + README
**Goal:** Ship-ready docs with the discovery story, setup guide, and limitations
**Requirements:** R5
**Deliverables:** `README.md`, `LIMITATIONS.md`, `TROUBLESHOOTING.md`

### Phase 5: GitHub Release
**Goal:** Private repo on GitHub, tagged v0.1.0
**Deliverables:** Push to VirelNode/session-roam, create release

## Success Criteria
- [ ] Run `setup.sh` on a fresh node, session files sync within 5 seconds
- [ ] `cr` on any node resumes the most recent session from any other node
- [ ] `verify.sh` catches misconfiguration and conflict files
- [ ] README tells the full story and is genuinely useful
