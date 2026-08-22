#!/usr/bin/env bash
# Behavior tests for cr.sh (pins current pre-lock behavior)
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../helpers.bash"
REPO_ROOT="$REPO_ROOT"

CR="$REPO_ROOT/cr.sh"
SBX=""
CWD=""

ns_for() { printf '%s/.claude/projects/-%s' "$HOME" "$(printf '%s' "${1#/}" | tr '/' '-')"; }

setup_cr_env() {
    t_sandbox
    CWD="$HOME/Desktop"
    mkdir -p "$CWD"
}

seed_session() {
    local ns="$1" epoch="$2" id
    mkdir -p "$ns"
    id="sess-$RANDOM$RANDOM"
    : > "$ns/$id.jsonl"
    touch -d "@$epoch" "$ns/$id.jsonl"
}

# CR_ANSWERS: text fed to the script's stdin ("-" = EOF immediately)
run_cr() {
    local f="$SBX/stdin.txt"
    if [[ "${CR_ANSWERS:--}" == "-" ]]; then
        f=/dev/null
    else
        printf '%s\n' "$CR_ANSWERS" > "$f"
    fi
    CLAUDE_STUB_LOG="${CLAUDE_STUB_LOG:-$SBX/claude.log}" \
    SLEEP_STUB_LOG="$SBX/sleep.log" \
    t_run_in "$CWD" "$f" "$CR" "$@"
}

t_start "force mode skips all prompts, sleeps, and execs claude -c with passthrough args"
setup_cr_env
CR_ANSWERS="n" run_cr --force extra-arg
assert_eq "$RC" 0 "force rc"
assert_contains "$(cat "$SBX/claude.log")" "-c extra-arg" "claude invoked with passthrough arg (flag consumed by wrapper)"
assert_contains "$(cat "$SBX/sleep.log")" "sleep 2" "propagation sleep ran"
assert_not_contains "$OUT$ERR" "Continue here anyway?" "no namespace prompt under --force"
t_end

t_start "non-Desktop cwd + answer n aborts without launching claude"
setup_cr_env
CWD="$HOME/Projects/somewhere"; mkdir -p "$CWD"
CR_ANSWERS="n" run_cr
assert_eq "$RC" 0 "abort rc is 0"
assert_contains "$OUT" "agent/project namespace" "namespace warning shown"
assert_contains "$OUT" "Aborted" "abort message shown"
assert_no_file "$SBX/claude.log" "claude never invoked"
t_end

t_start "non-Desktop cwd + answer y continues to claude"
setup_cr_env
CWD="$HOME/Projects/somewhere"; mkdir -p "$CWD"
CR_ANSWERS="y" run_cr
assert_eq "$RC" 0 "continue rc"
assert_file "$SBX/claude.log" "claude invoked after confirmation"
t_end

t_start "EOF stdin falls back to prompt defaults instead of crashing"
setup_cr_env
CWD="$HOME/Projects/somewhere"; mkdir -p "$CWD"
run_cr
assert_eq "$RC" 0 "EOF at namespace prompt aborts cleanly (default N)"
assert_contains "$OUT" "Aborted" "graceful abort message"
assert_no_file "$SBX/claude.log" "claude never launched"
t_end

t_start "EOF stdin at stale prompt takes the default (continue)"
setup_cr_env
now=$(date +%s)
seed_session "$(ns_for "$CWD")" $((now - 172800))
run_cr
assert_eq "$RC" 0 "EOF at stale prompt continues (default Y)"
assert_file "$SBX/claude.log" "claude ran on default"
t_end

t_start "EOF stdin at remote-stale lock prompt aborts safely (default N) leaving foreign lock"
setup_cr_env
mkdir -p "$(ns_for "$CWD")"
cat > "$(ns_for "$CWD")/.roam-lock.json" <<'LOCK'
{"node": "node03", "pid": 424242, "tty": "test", "started_epoch": 1, "started_iso": "test", "session_file": "x.jsonl"}
LOCK
run_cr
assert_eq "$RC" 0 "EOF at lock prompt declines cleanly"
grep -q '"node": "node03"' "$(ns_for "$CWD")/.roam-lock.json"; assert_eq "$?" 0 "foreign lock untouched"
assert_no_file "$SBX/claude.log" "no claude after decline"
t_end

t_start "Desktop cwd runs without namespace prompt"
setup_cr_env
run_cr
assert_not_contains "$OUT" "agent/project namespace" "no namespace warning in personal ns"
assert_file "$SBX/claude.log" "claude invoked directly"
t_end

t_start "fresh session produces no stale warning"
setup_cr_env
now=$(date +%s)
seed_session "$(ns_for "$CWD")" $((now - 60))
run_cr
assert_not_contains "$OUT$ERR" "Last session is" "no stale warning for fresh session"
assert_eq "$RC" 0 "rc"
t_end

t_start "stale session (>24h) warns; answer y proceeds"
setup_cr_env
now=$(date +%s)
seed_session "$(ns_for "$CWD")" $((now - 172800))
CR_ANSWERS="y" run_cr
assert_contains "$OUT$ERR" "2d 0h old" "stale warning names age"
assert_file "$SBX/claude.log" "proceeded on y"
t_end

t_start "stale session + answer n aborts"
setup_cr_env
now=$(date +%s)
seed_session "$(ns_for "$CWD")" $((now - 90000))
CR_ANSWERS="n" run_cr
assert_contains "$OUT" "Aborted" "abort message"
assert_no_file "$SBX/claude.log" "claude not launched after decline"
assert_eq "$RC" 0 "decline exits 0"
t_end

t_start "staleness judged by the NEWEST jsonl only"
setup_cr_env
ns="$(ns_for "$CWD")"
now=$(date +%s)
seed_session "$ns" $((now - 400000))
seed_session "$ns" $((now - 120))
run_cr
assert_not_contains "$OUT$ERR" "Last session is" "ancient older file does not trigger stale path"
assert_eq "$RC" 0 "rc"
t_end

t_start "missing namespace dir proceeds silently"
setup_cr_env
rm -rf "$(ns_for "$CWD")"
run_cr
assert_not_contains "$OUT$ERR" "Last session is" "no stale check without namespace"
assert_file "$SBX/claude.log" "still resumes"
t_end

t_start "--browse mode resumes via claude -r under the same lock ladder"
setup_cr_env
run_cr --browse
assert_eq "$RC" 0 "browse rc"
assert_contains "$(cat "$SBX/claude.log")" "-r" "claude -r invoked"
t_end

t_start "--search keyword resumes via claude -r <keyword> and holds the lock while running"
setup_cr_env
now=$(date +%s)
seed_session "$(ns_for "$CWD")" $((now - 120))
(
    cd "$CWD"
    export CLAUDE_STUB_MODE=wait-signal CLAUDE_STUB_MAX_WAIT=8
    export CLAUDE_STUB_RELEASE="$SBX/release.flag" CLAUDE_STUB_LOG="$SBX/claude.log"
    exec bash "$CR" --search "fix login bug"
) >"$SBX/out.txt" 2>&1 </dev/null &
wrapper=$!
wait_for_file "$SBX/claude.log" 10; assert_eq "$?" 0 "search resumed"
assert_contains "$(cat "$SBX/claude.log")" "-r fix login bug" "keyword passed through"
assert_file "$(ns_for "$CWD")/.roam-lock.json" "lock held during search-resume"
printf 'x' > "$SBX/release.flag"
wait_for_gone "$(ns_for "$CWD")/.roam-lock.json" 10; assert_eq "$?" 0 "lock released after search-resume"
wait "$wrapper"; assert_eq "$?" 0 "rc propagated"
t_end

t_start "force + search combination overrides a foreign lock and reaches claude -r"
setup_cr_env
mkdir -p "$(ns_for "$CWD")"
cat > "$(ns_for "$CWD")/.roam-lock.json" <<'LOCK'
{"node": "node02", "pid": 424242, "tty": "test", "started_epoch": 9999999999, "started_iso": "old", "session_file": "x.jsonl"}
LOCK
run_cr --force --search keyword
assert_eq "$RC" 0 "force+search overrides foreign lock"
assert_contains "$(cat "$SBX/claude.log")" "-r keyword" "search reached claude"
t_end

t_start "unknown flags still pass through to claude -c"
setup_cr_env
run_cr --model sonnet
assert_contains "$(cat "$SBX/claude.log")" "-c --model sonnet" "args forwarded"
t_end

t_teardown_all
suite_tally_exit
