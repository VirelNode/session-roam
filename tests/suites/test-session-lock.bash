#!/usr/bin/env bash
# Tests for the cross-node session lock: lib behavior, cr.sh ladder, signal handling
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../helpers.bash"
REPO_ROOT="$REPO_ROOT"

CR="$REPO_ROOT/cr.sh"
LIB="$REPO_ROOT/lib/session-lock.sh"
SBX=""
CWD=""

ns_for() { printf '%s/.claude/projects/-%s' "$HOME" "$(printf '%s' "${1#/}" | tr '/' '-')"; }
lockpath() { printf '%s/.roam-lock.json' "$(ns_for "$CWD")"; }

write_lock() { # write_lock <node> <pid> <age_secs>
    local node="$1" pid="$2" age="$3" lp ep
    mkdir -p "$(dirname "$(lockpath)")"
    ep=$(( $(date +%s) - age ))
    cat > "$(lockpath)" <<EOF
{"node": "$node", "pid": $pid, "tty": "test", "started_epoch": $ep, "started_iso": "test", "session_file": "x.jsonl"}
EOF
}

lib_classify() { # lib_classify <dir> [fresh_secs] -> prints LOCK_CLASS
    local dir="$1" fresh="${2:-}"
    REPO_ROOT_X="$REPO_ROOT" FRESH_X="$fresh" bash -c '
        [[ -n "$FRESH_X" ]] && export ROAM_FRESH_SECS="$FRESH_X"
        source "$REPO_ROOT_X/lib/session-lock.sh"
        lock_classify "$1"
        printf "%s" "$LOCK_CLASS"
    ' _ "$dir"
}

setup_env() {
    t_sandbox
    CWD="$HOME/Desktop"
    mkdir -p "$CWD"
}

# ─── Library unit behavior ────────────────────────────────────

t_start "lock_acquire writes a parseable lock owned by this node and leaves no temp residue"
setup_env
( source "$LIB"; lock_acquire "$(ns_for "$CWD")" "hint.jsonl" )
assert_file "$(lockpath)"
python3 -c "
import json,sys
d=json.load(open('$(lockpath)'))
sys.exit(0 if d['node']=='$(hostname)' and isinstance(d['pid'],int) else 3)
"; assert_eq "$?" 0 "lock JSON has our hostname + integer pid"
assert_no_file "$(lockpath).roam-lock.tmp" "no temp residue after atomic move"
grep -q 'hint.jsonl' "$(lockpath)"; assert_eq "$?" 0 "session hint recorded"
t_end

t_start "lock_release removes own lock but never a foreign one"
setup_env
( source "$LIB"; lock_acquire "$(ns_for "$CWD")" )
assert_file "$(lockpath)"
( source "$LIB"; lock_release "$(ns_for "$CWD")" )
assert_no_file "$(lockpath)" "own lock released"
write_lock "node-remote" 999999999 60
( source "$LIB"; lock_release "$(ns_for "$CWD")" )
assert_file "$(lockpath)" "foreign lock survives release attempt"
rm -f "$(lockpath)"
t_end

t_start "classify covers all six states"
setup_env
assert_eq "$(lib_classify "$(ns_for "$CWD")")" "none" "no lock -> none"
/bin/sleep 300 & live_pid=$!
write_lock "$(hostname)" "$live_pid" 30
assert_eq "$(lib_classify "$(ns_for "$CWD")")" "self-active" "own node live pid -> self-active"
lib_tty() {
    bash -c '
        source "'"$LIB"'"
        lock_classify "$1"
        printf "%s" "${LOCK_TTY:-<unset>}"
    ' _ "$(ns_for "$CWD")"
}
assert_eq "$(lib_tty)" "test" "tty field extracted from lock JSON"
kill -9 "$live_pid" 2>/dev/null; wait "$live_pid" 2>/dev/null
assert_eq "$(lib_classify "$(ns_for "$CWD")")" "self-stale" "own node dead pid -> self-stale"
write_lock "node-remote" 424242 10
assert_eq "$(lib_classify "$(ns_for "$CWD")")" "remote-fresh" "remote young lock -> remote-fresh"
assert_eq "$(lib_classify "$(ns_for "$CWD")" 5)" "remote-stale" "custom threshold flips classification (boundary above)"
write_lock "node-remote" 424242 5000
assert_eq "$(lib_classify "$(ns_for "$CWD")")" "remote-stale" "remote old lock -> remote-stale"
printf 'this is not json {' > "$(lockpath)"
assert_eq "$(lib_classify "$(ns_for "$CWD")")" "unknown" "corrupt lock -> unknown (fail closed)"
t_end

t_start "ROAM_FRESH_SECS boundary is honored exactly"
setup_env
export ROAM_FRESH_SECS=100
write_lock "node-remote" 424242 99
assert_eq "$(lib_classify "$(ns_for "$CWD")")" "remote-fresh" "age < threshold stays fresh"
write_lock "node-remote" 424242 101
assert_eq "$(lib_classify "$(ns_for "$CWD")")" "remote-stale" "age > threshold goes stale"
unset ROAM_FRESH_SECS
t_end

# ─── cr.sh ladder end-to-end ──────────────────────────────────

t_start "cr acquires the lock before claude starts and releases after clean exit"
setup_env
(
    cd "$CWD"
    export CLAUDE_STUB_MODE=wait-signal CLAUDE_STUB_MAX_WAIT=8
    export CLAUDE_STUB_RELEASE="$SBX/release.flag" CLAUDE_STUB_LOG="$SBX/claude.log"
    exec bash "$CR"
) >"$SBX/out.txt" 2>&1 </dev/null &
wrapper=$!
wait_for_file "$SBX/claude.log" 10; assert_eq "$?" 0 "claude started"
assert_file "$(lockpath)" "lock held while session runs"
printf 'x' > "$SBX/release.flag"
wait_for_gone "$(lockpath)" 10; assert_eq "$?" 0 "lock released after clean exit"
wait "$wrapper"; assert_eq "$?" 0 "wrapper exit code propagated"
t_end

t_start "cr releases the lock when claude fails, propagating nonzero rc"
setup_env
CLAUDE_STUB_EXIT=7 t_run_in "$CWD" - "$CR"
assert_eq "$RC" 7 "claude failure code surfaces through the wrapper"
assert_no_file "$(lockpath)" "EXIT trap released the lock despite failure"
t_end

t_start "fresh remote lock hard-blocks without launching claude"
setup_env
write_lock "node02" 424242 45
t_run_in "$CWD" - "$CR"
assert_eq "$RC" 1 "blocked with rc 1"
assert_contains "$OUT$ERR" "ACTIVE on 'node02'" "block names holder node"
assert_contains "$OUT$ERR" "--force" "escape hatch documented in output"
assert_no_file "$SBX/claude.log" "claude never launched"
t_end

t_start "--force overrides a fresh remote lock and takes ownership"
setup_env
write_lock "node02" 424242 45
(
    cd "$CWD"
    export CLAUDE_STUB_MODE=wait-signal CLAUDE_STUB_MAX_WAIT=8
    export CLAUDE_STUB_RELEASE="$SBX/release.flag" CLAUDE_STUB_LOG="$SBX/claude.log"
    exec bash "$CR" --force
) >"$SBX/out.txt" 2>&1 </dev/null &
wrapper=$!
wait_for_file "$SBX/claude.log" 10; assert_eq "$?" 0 "claude launched under force"
assert_contains "$(cat "$SBX/out.txt")" "Taking ownership" "takeover announced"
python3 -c "
import json,sys
d=json.load(open('$(lockpath)'))
sys.exit(0 if d['node']=='$(hostname)' else 3)
"; assert_eq "$?" 0 "lock owned by this node while session runs"
printf 'x' > "$SBX/release.flag"
wait_for_gone "$(lockpath)" 10; assert_eq "$?" 0 "released at exit"
wait "$wrapper"; assert_eq "$?" 0 "rc propagated"
t_end

t_start "stale remote lock prompts: n aborts leaving foreign lock untouched"
setup_env
write_lock "node03" 424242 7200
printf 'n\n' > "$SBX/stdin.txt"
t_run_in "$CWD" "$SBX/stdin.txt" "$CR"
assert_eq "$RC" 0 "decline exits 0"
assert_no_file "$SBX/claude.log" "no claude after decline"
grep -q '"node": "node03"' "$(lockpath)"; assert_eq "$?" 0 "foreign lock left intact on decline"
t_end

t_start "stale remote lock prompts: y takes ownership and resumes"
setup_env
now=$(date +%s)
ns="$(ns_for "$CWD")"; mkdir -p "$ns"
: > "$ns/recent.jsonl"; set_file_mtime "$ns/recent.jsonl" $((now - 60))
write_lock "node03" 424242 7200
printf 'y\n' > "$SBX/stdin.txt"
(
    cd "$CWD"
    export CLAUDE_STUB_MODE=wait-signal CLAUDE_STUB_MAX_WAIT=8
    export CLAUDE_STUB_RELEASE="$SBX/release.flag" CLAUDE_STUB_LOG="$SBX/claude.log"
    exec bash "$CR" < "$SBX/stdin.txt"
) >"$SBX/out.txt" 2>&1 &
wrapper=$!
wait_for_file "$SBX/claude.log" 10; assert_eq "$?" 0 "claude resumed after accept"
python3 -c "
import json,sys
d=json.load(open('$(lockpath)'))
sys.exit(0 if d['node']=='$(hostname)' else 3)
"; assert_eq "$?" 0 "ownership transferred on accept"
printf 'x' > "$SBX/release.flag"
wait "$wrapper"; assert_eq "$?" 0 "rc clean"
t_end

t_start "self-stale lock (dead pid) auto-clears and resumes without prompting"
setup_env
sleep 300 & dead_pid=$!; kill -9 "$dead_pid" 2>/dev/null; wait "$dead_pid" 2>/dev/null || true
write_lock "$(hostname)" "$dead_pid" 90000
CLAUDE_STUB_LOG="$SBX/claude.log" t_run_in "$CWD" - "$CR"
assert_eq "$RC" 0 "resumed past own stale lock"
assert_contains "$OUT$ERR" "stale lock" "cleanup was announced"
assert_file "$SBX/claude.log" "claude ran"
t_end

t_start "self-active lock (live pid) hard-blocks even without force flag"
setup_env
/bin/sleep 300 & live_pid=$!
write_lock "$(hostname)" "$live_pid" 15
t_run_in "$CWD" - "$CR"
assert_eq "$RC" 1 "local double-open blocked"
assert_contains "$OUT$ERR" "THIS node" "message identifies local holder"
assert_contains "$OUT$ERR" ", tty test," "message shows the real holder tty, not the timestamp"
assert_no_file "$SBX/claude.log" "no second writer launched"
kill -9 "$live_pid" 2>/dev/null; wait "$live_pid" 2>/dev/null || true
t_end

t_start "unreadable lock file fails closed"
setup_env
mkdir -p "$(dirname "$(lockpath)")"
printf 'garbage {{{' > "$(lockpath)"
t_run_in "$CWD" - "$CR"
assert_eq "$RC" 1 "fail-closed on unparseable lock"
assert_contains "$OUT$ERR" "UNREADABLE" "corruption reported"
assert_no_file "$SBX/claude.log" "no claude on fail-closed path"
t_end

# ─── Signal handling (SIGHUP = SSH/tmux disconnect case) ──────

signal_case() { # signal_case <sig> <expected_rc>
    local sig="$1" want_rc="$2" wrapper
    setup_env
    (
        cd "$CWD"
        export CLAUDE_STUB_MODE=wait-signal CLAUDE_STUB_MAX_WAIT=5
        export CLAUDE_STUB_RELEASE="$SBX/release.flag" CLAUDE_STUB_LOG="$SBX/claude.log"
        exec bash "$CR"
    ) >"$SBX/out.txt" 2>&1 </dev/null &
    wrapper=$!
    wait_for_file "$(lockpath)" 10 || { fail_msg "lock never appeared before $sig"; kill -9 "$wrapper" 2>/dev/null; return 1; }
    kill -"$sig" "$wrapper" 2>/dev/null
    wait "$wrapper"; local rc=$?
    assert_eq "$rc" "$want_rc" "$sig produced expected exit code"
    assert_no_file "$(lockpath)" "lock released on $sig"
    printf 'x' > "$SBX/release.flag" 2>/dev/null || true
    return 0
}

t_start "SIGHUP mid-session releases the lock (terminal-disconnect scenario)"
signal_case HUP 129
t_end

t_start "SIGTERM mid-session releases the lock"
signal_case TERM 143
t_end

t_start "SIGINT mid-session releases the lock"
signal_case INT 130
t_end

# ─── verify.sh dimension 10 reporting ─────────────────────────

build_verify_min_env() {
    t_sandbox
    FIX="$SBX/fixtures/sync"; export SYNC_FIXTURE="$FIX"; mkdir -p "$FIX"
    printf 'SELFID' > "$FIX/myid"
    printf 'SELFID\nPEERAAAA\n' > "$FIX/devices.list"
    printf 'claude-sessions\n' > "$FIX/folders.list"
    printf '%s' "$HOME/.claude/projects" > "$FIX/folder.claude-sessions.path"
    printf 'sendreceive' > "$FIX/folder.claude-sessions.type"
    printf '2' > "$FIX/folder.claude-sessions.fswatcher-delays"
    CF="$SBX/fixtures/curl"; export CURL_FIXTURE="$CF"; mkdir -p "$CF"
    printf '{}\n' > "$CF/system-status.json"
    printf '{"connections": {"PEERAAAA": {"connected": true}}}\n' > "$CF/connections.json"
    printf '{"requiresRestart": false}\n' > "$CF/restart-required.json"
    mkdir -p "$HOME/.local/state/syncthing"
    printf '<config><gui><apikey>K</apikey></gui></config>\n' > "$HOME/.local/state/syncthing/config.xml"
    now=$(date +%s)
    ns="$HOME/.claude/projects/-sbx-Desktop"; mkdir -p "$ns"
    : > "$ns/fresh.jsonl"; set_file_mtime "$ns/fresh.jsonl" $((now - 120))
}

t_start "verify dimension 10 reports locks by holder class and flags abandoned temps"
build_verify_min_env
run_v() { t_run_in "$HOME" - "$REPO_ROOT/verify.sh"; }
run_v
assert_contains "$OUT" "No session locks present" "clean report"
write_lock_in() { # <nspath> <node> <pid> <age>
    local d="$1" n="$2" p="$3" a="$4"
    printf '{"node":"%s","pid":%s,"started_epoch":%s,"started_iso":"t"}\n' "$n" "$p" "$(( $(date +%s) - a ))" > "$d/.roam-lock.json"
}
write_lock_in "$HOME/.claude/projects/-sbx-Desktop" "node09" 424242 60
run_v
assert_contains "$OUT" "likely ACTIVE on 'node09'" "fresh foreign lock surfaced as warning"
old_tmp="$HOME/.claude/projects/-sbx-Desktop/.roam-lock.json.roam-lock.tmp"
printf '{}' > "$old_tmp"
set_file_mtime "$old_tmp" $(( $(date +%s) - 7200 ))
run_v
assert_contains "$OUT" "abandoned lock temp file" "crash-mid-write residue flagged"
t_end

t_teardown_all
suite_tally_exit
