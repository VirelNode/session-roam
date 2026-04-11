---
phase: 1
slug: setup-script
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-11
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + bats-core (shell script testing) |
| **Config file** | none — Wave 0 installs |
| **Quick run command** | `bash setup.sh --dry-run` |
| **Full suite command** | `bats tests/` (if bats available) or manual verification |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash -n setup.sh` (syntax check)
- **After every plan wave:** Run dry-run or manual test on node
- **Before `/gsd-verify-work`:** Full setup.sh execution on a configured node
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 1-01-01 | 01 | 1 | R1 | syntax | `bash -n setup.sh` | ⬜ pending |
| 1-01-02 | 01 | 1 | R1 | integration | `bash setup.sh --dry-run` | ⬜ pending |
| 1-01-03 | 01 | 2 | R1 | manual | Verify Syncthing running after setup | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `setup.sh` — script exists and passes `bash -n` syntax check
- [ ] Script has `set -euo pipefail` and proper error handling
