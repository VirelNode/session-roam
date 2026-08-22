#!/usr/bin/env bash
# session-roam tests: shared harness helpers (plain bash, no dependencies)

T_PASS=0 T_FAIL=0 T_SKIP=0
T_CURRENT="" T_FAILED_NOW=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUB_DIR="$REPO_ROOT/tests/stubs"

t_start() { T_CURRENT="$1"; T_FAILED_NOW=0; }

t_end() {
    local n=$((T_PASS + T_FAIL + T_SKIP + 1))
    if [[ $T_FAILED_NOW -eq 0 ]]; then
        T_PASS=$((T_PASS + 1))
        printf 'ok %d - %s\n' "$n" "$T_CURRENT"
    else
        T_FAIL=$((T_FAIL + 1))
        printf 'not ok %d - %s\n' "$n" "$T_CURRENT"
    fi
}

t_skip() {
    T_SKIP=$((T_SKIP + 1))
    printf 'ok %d - # SKIP %s\n' "$((T_PASS + T_FAIL + T_SKIP))" "${1:-}"
}

fail_msg() {
    T_FAILED_NOW=$((T_FAILED_NOW + 1))
    printf '      ✗ %s\n' "$1"
}

assert_eq() {
    local got="$1" want="$2" msg="$3"
    [[ "$got" == "$want" ]] && return 0
    fail_msg "$msg: want [$want] got [$got]"
}

assert_contains() {
    local hay="$1" needle="$2" msg="$3"
    [[ "$hay" == *"$needle"* ]] && return 0
    fail_msg "$msg: missing [$needle]"
}

assert_not_contains() {
    local hay="$1" needle="$2" msg="$3"
    [[ "$hay" != *"$needle"* ]] && return 0
    fail_msg "$msg: unexpectedly contains [$needle]"
}

assert_file() { [[ -e "$1" ]] && return 0; fail_msg "file absent: $1"; }
assert_no_file() { [[ ! -e "$1" ]] && return 0; fail_msg "file present: $1"; }
assert_exec() { [[ -x "$1" ]] && return 0; fail_msg "not executable: $1"; }

t_sandbox() {
    [[ -n "${SBX:-}" && -d "$SBX" ]] && rm -rf "$SBX"
    SBX="$(mktemp -d "${TMPDIR:-/tmp}/session-roam-test.XXXXXXXX")"
    export HOME="$SBX/home"
    mkdir -p "$HOME/.local/bin" "$HOME/.claude/projects" "$SBX/fixtures" "$SBX/logs"
    export PATH="$STUB_DIR:$PATH"
    export STUB_LOG="$SBX/logs/stubs.log"
    : > "$STUB_LOG"
    unset ROAM_LOCK_FRESH_SECS 2>/dev/null || true
}

t_teardown_all() { [[ -n "${SBX:-}" && -d "$SBX" ]] && rm -rf "$SBX"; return 0; }

# t_run_in <workdir> <stdin-file|-> <script-path> [args...]
# Runs the target script in a subshell so exec/exit cannot kill the suite;
# captures stdout, stderr, and status into OUT / ERR / RC.
t_run_in() {
    local wd="$1" stdin_file="$2"
    shift 2
    if [[ "$stdin_file" == "-" ]]; then
        stdin_file="/dev/null"
    fi
    ( cd "$wd" && bash "$@" ) >"$SBX/out.txt" 2>"$SBX/err.txt" <"$stdin_file"
    RC=$?
    OUT="$(<"$SBX/out.txt")"
    ERR="$(<"$SBX/err.txt")"
}

wait_for_file() {
    local f="$1" deadline=$(( SECONDS + ${2:-10} ))
    while (( SECONDS < deadline )); do
        [[ -f "$f" ]] && return 0
        /bin/sleep 0.05
    done
    return 1
}

wait_for_gone() {
    local f="$1" deadline=$(( SECONDS + ${2:-10} ))
    while (( SECONDS < deadline )); do
        [[ ! -e "$f" ]] && return 0
        /bin/sleep 0.05
    done
    return 1
}

suite_tally_exit() {
    printf 'SUITE_TALLY pass=%d fail=%d skip=%d\n' "$T_PASS" "$T_FAIL" "$T_SKIP"
    (( T_FAIL == 0 )) && exit 0
    exit 1
}
