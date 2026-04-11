# Session Namespacing Conventions

session-roam syncs `~/.claude/projects/` across all nodes in the cluster. Because Claude Code creates session directories based on the terminal's working directory, different session origins **must** use different CWDs to avoid namespace collisions. This document defines the convention for every session type.

## How Claude Code Maps CWD to Session Directory

Claude Code mangles the absolute path of your working directory into a directory name under `~/.claude/projects/`. Slashes become dashes, and a leading dash is added.

| Working Directory | Session Namespace |
|-------------------|-------------------|
| `~/Desktop` | `-home-joe-Desktop/` |
| `~/Projects` | `-home-joe-Projects/` |
| `~/Projects/claude-memory-system` | `-home-joe-Projects-claude-memory-system/` |

All session `.jsonl` files, CLAUDE.md, and memory directories for that CWD live inside the corresponding namespace directory.

## Session Types

| Origin | CWD | Session Namespace | Status |
|--------|-----|-------------------|--------|
| Personal (Joe) | `~/Desktop` | `-home-joe-Desktop/` | Isolated (convention) |
| IOSTUI panes | `~/Projects` (via `IOSTUI_CWD` in `.env`) | `-home-joe-Projects/` | Isolated (config enforced) |
| Federation subprocess | Inherits federation server CWD (`~/Projects/claude-memory-system`) | `-home-joe-Projects-claude-memory-system/` | Isolated (server CWD) |
| Federation Zellij pane | Inherits terminal CWD (UNPINNED) | Varies -- **COLLISION RISK** | **GAP -- needs CWD pin** |

### Personal Sessions

Joe's interactive Claude Code sessions always run from `~/Desktop`. The `cr` alias resumes the most recent session in `-home-joe-Desktop/`. This namespace is sacred -- no automated agent should write here.

### IOSTUI Pane Sessions

IOSTUI's `.env` file sets `IOSTUI_CWD=/home/joe/Projects`. The PTY manager (`pty-manager.js`) and agent daemon (`agentd`) both honor this, spawning Claude Code processes with that CWD. Sessions land in `-home-joe-Projects/`, fully isolated from personal sessions.

### Federation Subprocess Sessions

When the federation server runs agents via `subprocess.run()`, the child process inherits the server's own CWD (`~/Projects/claude-memory-system`). Sessions land in `-home-joe-Projects-claude-memory-system/`. No collision.

### Federation Zellij Pane Sessions (THE GAP)

`send_to_zellij_pane()` in `zellij_helpers.py` injects text into existing terminal panes via Zellij's `write-chars` action. Those panes inherit whatever CWD the Zellij session was created with. If someone opens the federation Zellij session from `~/Desktop`, all 4 pane agents (Claude, Gemini, Codex, Qwen) will create sessions in the personal namespace.

See [FEDERATION-CWD-PIN.md](FEDERATION-CWD-PIN.md) for the fix specification.

## Rules for New Agents

1. **Never run agents from `~/Desktop`** -- that namespace is reserved for Joe's personal sessions.
2. **Set an explicit CWD for any new agent type.** Follow IOSTUI's pattern: config-driven CWD via environment variable or config file.
3. **If using Zellij panes**, ensure the session is created from the project directory, not `~/Desktop`.
4. **Subprocess-mode agents** should set `cwd=` explicitly in their `subprocess.run()` calls.
5. **When adding a new agent origin**, add a row to the Session Types table above and verify isolation with `./verify.sh`.

## Verification

`verify.sh` section 9 ("Agent Session Isolation") scans the personal namespace for signs of agent contamination. Run it after any agent configuration change:

```bash
./verify.sh
```

If section 9 reports warnings, an automated agent is (or was) writing sessions into `-home-joe-Desktop/`. Identify the agent, pin its CWD to a non-Desktop path, and re-verify.
