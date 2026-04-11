#!/usr/bin/env bash
set -euo pipefail

# session-roam: Smart resume wrapper
# Replaces the old `alias cr='sleep 2 && claude -c'` with context-aware checks.
# https://github.com/VirelNode/session-roam

YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

warn() { printf '%s[!]%s %s\n' "$YELLOW" "$NC" "$1"; }

# ─── --force flag ─────────────────────────────────────────────
force=false
if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
    force=true
    shift
fi

if [[ "$force" == true ]]; then
    sleep 2
    exec claude -c "$@"
fi

# ─── Directory namespace check ────────────────────────────────
# Personal sessions live in ~/Desktop. Warn if we're elsewhere
# (likely an agent/project namespace).
if [[ "$PWD" != "$HOME/Desktop"* ]]; then
    warn "You're not in ~/Desktop -- this is an agent/project namespace."
    printf "  Current directory: %s\n" "$PWD"
    printf "  Continue here anyway? [y/N] "
    read -r answer
    if [[ "${answer,,}" != "y" ]]; then
        printf "Aborted. Use 'cs' to pick a specific session, or cd ~/Desktop first.\n"
        exit 0
    fi
fi

# ─── Stale session warning ────────────────────────────────────
# Find the most recent .jsonl in the Claude session namespace for this CWD.
namespace_dir="$HOME/.claude/projects/-$(echo "$PWD" | sed 's|^/||; s|/|-|g')"

if [[ -d "$namespace_dir" ]]; then
    newest=$(find "$namespace_dir" -maxdepth 2 -name "*.jsonl" -printf "%T@ %p\n" 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
    if [[ -n "${newest:-}" ]]; then
        age_seconds=$(( $(date +%s) - $(stat -c %Y "$newest") ))
        if [[ $age_seconds -gt 86400 ]]; then
            days=$((age_seconds / 86400))
            hours=$(( (age_seconds % 86400) / 3600 ))
            warn "Last session is ${days}d ${hours}h old."
            printf "  Continue? [Y/n] "
            read -r answer
            if [[ "${answer,,}" == "n" ]]; then
                printf "Aborted. Use 'cs' to browse sessions or 'cn \"name\"' to start fresh.\n"
                exit 0
            fi
        fi
    fi
fi

# ─── Syncthing propagation delay ─────────────────────────────
sleep 2

# ─── Resume ──────────────────────────────────────────────────
exec claude -c "$@"
