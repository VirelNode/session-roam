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
**Plans:** 1 plan (freeform)

Plans:
- [x] stignore.template — Exclude worktrees, subagents, caches, webfetch; keep .jsonl + memory
- [x] install-aliases.sh — Install cr/cs/cf/cn/cfork/crf to bash/zsh, deploy .stignore

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

## Success Criteria (v0.1.0)
- [x] Run `setup.sh` on a fresh node, session files sync within 5 seconds
- [x] `cr` on any node resumes the most recent session from any other node
- [x] `verify.sh` catches misconfiguration and conflict files
- [x] README tells the full story and is genuinely useful

---

## Milestone 2: v0.2.0 — Multi-Agent Awareness

### Phase 6: Session Namespacing
**Goal:** Federation agents and IOSTUI panes don't collide with personal sessions
**Deliverables:** CONVENTIONS.md, verify.sh section 9, federation CWD pin recommendation
**Plans:** 1 plan

Plans:
- [x] 06-01-PLAN.md — Document namespacing conventions, add agent isolation check to verify.sh, create federation CWD pin recommendation

### Phase 7: Smart Resume Wrapper
**Goal:** `cr` is context-aware — warns on wrong namespace, warns on stale sessions, Syncthing delay built-in
**Deliverables:** `cr.sh` smart wrapper, updated `install-aliases.sh`, updated `verify.sh`
**Plans:** 1 plan

Plans:
- [x] 07-01-PLAN.md — Create cr.sh smart wrapper, update install-aliases.sh to deploy it, update verify.sh shortcut detection

## Success Criteria (v0.2.0)
- [ ] `cr` on any node ONLY grabs personal sessions, never agent sessions
- [ ] Session namespacing convention documented and enforced
- [ ] Smart `cr` wrapper filters by session origin
