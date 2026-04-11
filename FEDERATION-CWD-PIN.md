# Federation Zellij Pane CWD Pinning

Actionable specification for closing the one remaining session namespace gap: federation Zellij panes that inherit an unpinned terminal CWD.

## Problem

Federation Zellij panes inherit the CWD of whatever terminal the Zellij session was created from. If the federation session is started from `~/Desktop`, all 4 pane agents (Claude, Gemini, Codex, Qwen) will create Claude Code sessions in `-home-joe-Desktop/`, colliding with Joe's personal sessions.

This is the only session isolation gap identified in the [CONVENTIONS.md](CONVENTIONS.md) audit. The other two agent types (IOSTUI panes, federation subprocess mode) are already isolated by design.

## Current State

**`session_registry.py`** (at `~/Projects/claude-memory-system/extensions/notes-federation/session_registry.py`) defines the pane layout and `SESSION_CONFIGS` for federation sessions. It specifies agent names and pane indices but does NOT set a CWD.

**`zellij_helpers.py`** provides `send_to_zellij_pane()`, which injects text into Zellij panes using `write-chars`. It has no CWD control -- it writes into whatever shell is running in the target pane, and that shell's CWD is whatever the Zellij session was created with.

**Result:** If the Zellij session was started from `~/Desktop`, every `claude` command injected into panes will create sessions in `-home-joe-Desktop/`.

## Recommended Fix

Two complementary changes, both in the `claude-memory-system` repo.

### 1. Add `cwd` field to `SESSION_CONFIGS` in `session_registry.py`

```python
SESSION_CONFIGS = {
    "federation": {
        "cwd": "/home/joe/Projects/claude-memory-system",
        "agents": ["claude", "gemini", "codex", "qwen"],
        # ... rest unchanged
    },
    "qwen-federation": {
        "cwd": "/home/joe/Projects/claude-memory-system",
        "agents": ["qwen", "qwen-2", "qwen-3", "qwen-4", "qwen-5"],
        # ... rest unchanged
    },
}
```

### 2. Inject `cd` preamble when initializing panes

When the federation bootstrap sends the first command to a Zellij pane, prepend a `cd` to the configured CWD. This can be done in `send_to_zellij_pane()` or in the session initialization code that first populates each pane.

```python
def send_to_zellij_pane(session_name, pane_index, text, config_key="federation"):
    config = SESSION_CONFIGS[config_key]
    cwd = config.get("cwd")

    # On first use of a pane, pin its CWD
    if cwd and not _pane_initialized.get((session_name, pane_index)):
        _send_raw(session_name, pane_index, f"cd {cwd}\n")
        _pane_initialized[(session_name, pane_index)] = True

    _send_raw(session_name, pane_index, text)
```

### Alternative: Zellij Layout File

If the federation uses a Zellij layout file (`.kdl`), CWD can be set per-pane declaratively:

```kdl
layout {
    pane cwd="/home/joe/Projects/claude-memory-system" {
        // Claude agent pane
    }
    pane cwd="/home/joe/Projects/claude-memory-system" {
        // Gemini agent pane
    }
    // ... etc
}
```

This is cleaner than the `cd` injection approach but requires the federation to use a layout file for session creation.

## Why `~/Projects/claude-memory-system`

This is where the federation code lives. Using it as the CWD means:

- Sessions land in `-home-joe-Projects-claude-memory-system/`, which is already the subprocess-mode namespace
- Subprocess agents and pane agents share the same namespace (consistent)
- The path is stable and meaningful (it IS the federation project)

## Scope Note

This fix lives in the **`claude-memory-system` repo**, NOT in `session-roam`. This document serves as the specification for that change. The `session-roam` side (`verify.sh` section 9) will detect if the fix is not applied -- agent sessions leaking into the personal namespace will trigger warnings.

## Testing After Fix

1. **Automated:** Run `./verify.sh` from the session-roam repo. Section 9 should report "No agent sessions detected in personal namespace."

2. **Manual:** Start a federation Zellij session and confirm pane agents create sessions in `-home-joe-Projects-claude-memory-system/`, not `-home-joe-Desktop/`:
   ```bash
   ls ~/.claude/projects/-home-joe-Projects-claude-memory-system/
   # Should show recent federation agent sessions
   ```

3. **Negative check:** Verify no new sessions appeared in the personal namespace:
   ```bash
   # After running federation panes, check that personal namespace
   # session count didn't increase unexpectedly
   find ~/.claude/projects/-home-joe-Desktop -maxdepth 2 -name "*.jsonl" -mmin -60 | wc -l
   ```
