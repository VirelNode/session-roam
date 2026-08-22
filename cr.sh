#!/usr/bin/env bash
set -euo pipefail

# session-roam: Smart resume wrapper
# Replaces the old `alias cr='sleep 2 && claude -c'` with context-aware checks,
# plus a cross-node session lock so the same namespace cannot be resumed from
# two nodes at once (the root cause of .sync-conflict files).
# https://github.com/VirelNode/session-roam

YELLOW='\033[0;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

warn() { printf '%s[!]%s %s\n' "$YELLOW" "$NC" "$1"; }
deny() { printf '%s[x]%s %s\n' "$RED" "$NC" "$1"; }

# ─── Lock library ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_LIB_OK=true
if [[ -f "$SCRIPT_DIR/lib/session-lock.sh" ]]; then
    # shellcheck source=lib/session-lock.sh
    source "$SCRIPT_DIR/lib/session-lock.sh"
elif [[ -f "$HOME/.local/lib/session-roam/session-lock.sh" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.local/lib/session-roam/session-lock.sh"
else
    LOCK_LIB_OK=false
fi

# ─── --force flag ─────────────────────────────────────────────
force=false
if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
    force=true
    shift
fi

# ─── Directory namespace check ────────────────────────────────
# Personal sessions live in ~/Desktop. Warn if we're elsewhere
# (likely an agent/project namespace).
if [[ "$force" == false && "$PWD" != "$HOME/Desktop"* ]]; then
    warn "You're not in ~/Desktop -- this is an agent/project namespace."
    printf "  Current directory: %s\n" "$PWD"
    printf "  Continue here anyway? [y/N] "
    read -r answer
    if [[ "${answer,,}" != "y" ]]; then
        printf "Aborted. Use 'cs' to pick a specific session, or cd ~/Desktop first.\n"
        exit 0
    fi
fi

# ─── Namespace directory (session store + lock home) ──────────
namespace_dir="$HOME/.claude/projects/-$(echo "$PWD" | sed 's|^/||; s|/|-|g')"

# ─── Stale session warning ────────────────────────────────────
newest=""
if [[ "$force" == false && -d "$namespace_dir" ]]; then
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

fmt_age() { # fmt_age <seconds> -> "4 min" | "3h 20m" | "2d 3h"
    local s=$1
    if (( s < 3600 )); then
        printf '%d min' $(( s / 60 ))
    elif (( s < 86400 )); then
        printf '%dh %dm' $(( s / 3600 )) $(( (s % 3600) / 60 ))
    else
        printf '%dd %dh' $(( s / 86400 )) $(( (s % 86400) / 3600 ))
    fi
}

# ─── Cross-node session lock ──────────────────────────────────
# Advisory lease synced via Syncthing. Classification ladder:
#   none        -> acquire
#   self-stale  -> our own crashed leftover (pid gone): clear, acquire fresh
#   self-active -> another terminal ON THIS NODE holds it: hard block
#   remote-fresh(< ROAM_FRESH_SECS, default 900) -> treat as live: hard block
#   remote-stale(>= threshold) -> probably a crashed holder: warn, [y/N]
#   unknown     -> unreadable/corrupt lock file: fail closed
if [[ "$LOCK_LIB_OK" == true ]]; then
    lock_classify "$namespace_dir"
    case "$LOCK_CLASS" in
        none)
            ;;
        self-stale)
            rm -f "$LOCK_FILE_PATH"
            warn "Cleared a stale lock left by an earlier session on this node."
            ;;
        self-active)
            if [[ "$force" == false ]]; then
                holder="pid ${LOCK_PID:-?}"
                if [[ -n "${LOCK_TTY:-}" && "$LOCK_TTY" != "none" ]]; then holder+=", tty $LOCK_TTY"; fi
                if [[ -n "${LOCK_STARTED:-}" ]]; then holder+=", since $LOCK_STARTED"; fi
                deny "A session in this namespace appears open on THIS node ($holder)."
                printf "  Two writers on the same transcript will corrupt it.\n"
                printf "  If you are sure it is closed, rerun with --force.\n"
                exit 1
            fi
            ;;
        remote-fresh|unknown)
            if [[ "$force" == false ]]; then
                if [[ "$LOCK_CLASS" == "unknown" ]]; then
                    deny "Found an UNREADABLE session lock in this namespace (${LOCK_FILE_PATH})."
                    printf "  Treating it as active rather than risk a concurrent writer.\n"
                else
                    deny "This namespace looks ACTIVE on '${LOCK_NODE}' (lock held $(fmt_age "$LOCK_AGE"), since ${LOCK_STARTED})."
                fi
                printf "  Resume here only after closing it over there, or rerun with --force to override.\n"
                exit 1
            fi
            ;;
        remote-stale)
            if [[ "$force" == false ]]; then
                warn "Session lock from ANOTHER NODE found in this namespace:"
                printf "    Holder: %s (held %s, since %s)\n" "${LOCK_NODE:-?}" "$(fmt_age "$LOCK_AGE")" "${LOCK_STARTED:-?}"
                printf "    If that node crashed mid-session this is leftover; if it is merely idle, resuming twice WILL fork conflicts.\n"
                printf "  Continue anyway? [y/N] "
                read -r answer
                if [[ "${answer,,}" != "y" ]]; then
                    printf "Aborted. Clear the other side first, or use --force.\n"
                    exit 0
                fi
            fi
            ;;
    esac

    if [[ "${LOCK_CLASS:-none}" != "none" && "$LOCK_CLASS" != "self-stale" ]]; then
        printf '%s[lock]%s Taking ownership of the session lock (was %s).\n' "$GREEN" "$NC" "${LOCK_NODE:-$(hostname)}"
    fi

    if [[ -z "$newest" && -d "$namespace_dir" ]]; then
        newest=$(set +o pipefail; find "$namespace_dir" -maxdepth 2 -name "*.jsonl" -printf "%T@ %p\n" 2>/dev/null \
            | sort -rn | head -1 | cut -d' ' -f2-)
    fi
    if ! lock_acquire "$namespace_dir" "${newest##*/}"; then
        warn "Could not write the session lock; continuing WITHOUT cross-node protection."
        LOCK_LIB_OK=false
    fi
else
    warn "session-lock library not found (~/.local/lib/session-roam/) -- running without concurrent-session protection."
fi

release_lock() {
    [[ "$LOCK_LIB_OK" == true ]] && lock_release "$namespace_dir"
    return 0
}
trap release_lock EXIT
trap 'release_lock; trap - EXIT; exit 129' HUP
trap 'release_lock; trap - EXIT; exit 130' INT
trap 'release_lock; trap - EXIT; exit 143' TERM

# ─── Syncthing propagation delay ─────────────────────────────
sleep 2

# ─── Resume ──────────────────────────────────────────────────
RC=0
claude -c "$@" || RC=$?
exit "$RC"
