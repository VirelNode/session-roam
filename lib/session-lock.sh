#!/usr/bin/env bash
# session-roam: cross-node session lock (advisory lease propagated by Syncthing)
# Sourced by cr.sh (full lifecycle) and verify.sh (read-only reporting).
#
# The lock lives INSIDE the synced namespace directory, so Syncthing itself is
# the transport: no server, no daemon. A lock means "a session in this namespace
# was started on <node> at <time> and has not exited cleanly yet."
# It does NOT prove the session is still alive — see ARCHITECTURE.md for the
# failure-mode analysis (crashed holder -> stale lock -> age-based handling).

ROAM_LOCK_NAME=".roam-lock.json"
ROAM_LOCK_TMP_SUFFIX=".roam-lock.tmp"
ROAM_FRESH_SECS="${ROAM_FRESH_SECS:-900}"

lock_file() { printf '%s/%s' "$1" "$ROAM_LOCK_NAME"; }

lock_read_field() { # lock_read_field <file> <key>
    python3 - "$1" "$2" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
except Exception:
    sys.exit(3)
v = d.get(sys.argv[2], "")
print(v if v is not None else "")
PY
}

lock_classify() { # lock_classify <ns_dir> -> LOCK_CLASS LOCK_NODE LOCK_PID LOCK_AGE LOCK_STARTED LOCK_TTY
    local f now epoch node pid rc
    LOCK_FILE_PATH="$(lock_file "$1")"
    LOCK_CLASS="none" LOCK_NODE="" LOCK_PID="" LOCK_AGE=0 LOCK_STARTED="" LOCK_TTY=""
    [[ -f "$LOCK_FILE_PATH" ]] || return 0

    now=$(date +%s)
    node="$(lock_read_field "$LOCK_FILE_PATH" node)" || { LOCK_CLASS="unknown"; return 0; }
    pid="$(lock_read_field "$LOCK_FILE_PATH" pid)" || { LOCK_CLASS="unknown"; return 0; }
    epoch="$(lock_read_field "$LOCK_FILE_PATH" started_epoch)" || { LOCK_CLASS="unknown"; return 0; }
    LOCK_STARTED="$(lock_read_field "$LOCK_FILE_PATH" started_iso)" || { LOCK_CLASS="unknown"; return 0; }
    LOCK_TTY="$(lock_read_field "$LOCK_FILE_PATH" tty 2>/dev/null)" || LOCK_TTY=""

    if ! [[ "$epoch" =~ ^[0-9]+$ ]] || [[ "$epoch" -eq 0 ]]; then
        epoch=$(stat -c %Y "$LOCK_FILE_PATH" 2>/dev/null || echo "$now")
    fi
    LOCK_AGE=$((now - epoch))
    (( LOCK_AGE < 0 )) && LOCK_AGE=0
    LOCK_NODE="$node"
    LOCK_PID="$pid"

    if [[ -z "$node" ]]; then
        LOCK_CLASS="unknown"
    elif [[ "$node" == "$(hostname)" && -n "$pid" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        LOCK_CLASS="self-active"
    elif [[ "$node" == "$(hostname)" ]]; then
        LOCK_CLASS="self-stale"
    elif [[ "$LOCK_AGE" -lt "$ROAM_FRESH_SECS" ]]; then
        LOCK_CLASS="remote-fresh"
    else
        LOCK_CLASS="remote-stale"
    fi
    return 0
}

lock_acquire() { # lock_acquire <ns_dir> [session_hint]
    local dir="$1" hint="${2:-}" f tmp epoch iso tty_name
    mkdir -p "$dir" || return 1
    f="$(lock_file "$dir")"
    tmp="${f}${ROAM_LOCK_TMP_SUFFIX}"
    epoch=$(date +%s)
    iso=$(date -d "@$epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
    if [[ -t 0 ]]; then
        tty_name=$(tty 2>/dev/null || true)
    fi
    tty_name=${tty_name:-none}
    hint=${hint//\"/}
    cat > "$tmp" <<EOF
{
  "node": "$(hostname)",
  "pid": $$,
  "tty": "${tty_name//\"/}",
  "started_epoch": $epoch,
  "started_iso": "$iso",
  "session_file": "$hint"
}
EOF
    mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
}

lock_release() { # lock_release <ns_dir> — only removes a lock we still own
    local dir="$1" f node pid
    f="$(lock_file "$dir")"
    [[ -f "$f" ]] || return 0
    node="$(lock_read_field "$f" node 2>/dev/null)" || { rm -f "${f}${ROAM_LOCK_TMP_SUFFIX}"; return 0; }
    pid="$(lock_read_field "$f" pid 2>/dev/null)" || true
    if [[ "$node" == "$(hostname)" && "$pid" == "$$" ]]; then
        rm -f "$f" "${f}${ROAM_LOCK_TMP_SUFFIX}"
    fi
}
