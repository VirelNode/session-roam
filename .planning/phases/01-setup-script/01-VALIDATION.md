---
phase: 1
slug: setup-script
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-11
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + shellcheck (shell script linting) |
| **Config file** | none — Wave 0 installs shellcheck |
| **Quick run command** | `bash -n setup.sh && shellcheck --severity=error setup.sh` |
| **Full suite command** | `bash -n setup.sh && shellcheck setup.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash -n setup.sh` (syntax check)
- **After every plan wave:** Run `shellcheck --severity=error setup.sh` (lint check)
- **Before `/gsd-verify-work`:** Full setup.sh execution on a configured node + idempotency re-run
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 1-01-01 | 01 | 1 | R1 | syntax | `bash -n setup.sh` | pending |
| 1-01-02 | 01 | 1 | R1 | syntax+lint | `bash -n setup.sh && shellcheck --severity=error setup.sh` | pending |
| 1-01-03 | 01 | 2 | R1 | manual | Verify Syncthing running after setup, shellcheck clean | pending |

---

## Wave 0 Requirements

- [ ] `setup.sh` — script exists and passes `bash -n` syntax check
- [ ] Script has `set -euo pipefail` and proper error handling
- [ ] `shellcheck` installed: `sudo apt install shellcheck` (if not present)
