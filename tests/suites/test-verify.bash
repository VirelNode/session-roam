#!/usr/bin/env bash
# Behavior tests for verify.sh (9-dimension health check)
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../helpers.bash"
REPO_ROOT="$REPO_ROOT"

VERIFY="$REPO_ROOT/verify.sh"
SBX=""

build_green_env() {
    t_sandbox

    local FIX="$SBX/fixtures/sync"
    export SYNC_FIXTURE="$FIX"; mkdir -p "$FIX"
    printf 'SELFID00000000000000000000000000000' > "$FIX/myid"
    { echo "SELFID00000000000000000000000000000"; echo "PEERAAAA0000000000000000000000000"; } > "$FIX/devices.list"
    printf 'claude-sessions\n' > "$FIX/folders.list"
    printf '%s' "$HOME/.claude/projects" > "$FIX/folder.claude-sessions.path"
    printf 'sendreceive' > "$FIX/folder.claude-sessions.type"
    printf '2' > "$FIX/folder.claude-sessions.fswatcher-delays"

    local CF="$SBX/fixtures/curl"
    export CURL_FIXTURE="$CF"; mkdir -p "$CF"
    printf '{}\n' > "$CF/system-status.json"
    printf '{"connections": {"PEERAAAA": {"connected": true}, "PEERBBBB": {"connected": false}}}\n' > "$CF/connections.json"
    printf '{"requiresRestart": false}\n' > "$CF/restart-required.json"

    mkdir -p "$HOME/.local/state/syncthing"
    cat > "$HOME/.local/state/syncthing/config.xml" <<'XML'
<config>
  <gui>
    <apikey>TESTKEY123</apikey>
  </gui>
</config>
XML

    t_run_in "$HOME" - "$REPO_ROOT/install-aliases.sh"
    (( RC == 0 )) || fail_msg "fixture installer failed rc=$RC: $ERR"

    local now ns
    now=$(date +%s)
    ns="$HOME/.claude/projects/-sbx-Desktop"
    mkdir -p "$ns"
    : > "$ns/fresh-session.jsonl"
    touch -d "@$((now - 120))" "$ns/fresh-session.jsonl"
}

run_verify() { t_run_in "$HOME" - "$VERIFY"; }

t_start "fully green environment passes with zero errors and exits 0"
build_green_env
run_verify
assert_eq "$RC" 0 "exit code is error count (0)"
assert_contains "$OUT" "All checks passed." "clean summary"
assert_contains "$OUT" "Syncthing process is running" "service ok line"
assert_contains "$OUT" "API responding on port 8384" "api ok line"
assert_contains "$OUT" "1 peer(s) connected" "connected peer counted from connections JSON"
assert_contains "$OUT" "No sync conflicts found" "conflict section clean"
t_end

t_start "conflict files are errors: listed by name, exit nonzero"
build_green_env
ns="$HOME/.claude/projects/-sbx-Desktop"
: > "$ns/transcript.jsonl.sync-conflict-20260822-043000"
run_verify
if [[ "$RC" -eq 0 ]]; then fail_msg "expected nonzero exit with a conflict present"; fi
assert_contains "$OUT" "1 sync conflict(s) detected" "conflict count reported"
assert_contains "$OUT" "transcript.jsonl.sync-conflict-20260822-043000" "conflict filename listed"
t_end

t_start "exit status equals the number of failing dimensions"
build_green_env
export PGREP_SYNCTHING=0
: > "$HOME/.claude/projects/-sbx-Desktop/broken.jsonl.sync-conflict-20260822-000000"
run_verify
unset PGREP_SYNCTHING
assert_eq "$RC" 2 "two failures -> exit 2"
t_end

t_start "warnings alone still exit 0"
build_green_env
rm -f "$HOME/.claude/projects/.stignore"
run_verify
assert_eq "$RC" 0 "warning-only run exits 0"
assert_contains "$OUT" "Passed with 1 warning(s)" "summary names the warning count"
assert_contains "$OUT" ".stignore" "stignore warning present"
t_end

t_start "API not responding is an error"
build_green_env
rm -f "$SBX/fixtures/curl/system-status.json"
run_verify
if [[ "$RC" -eq 0 ]]; then fail_msg "expected nonzero when API down"; fi
assert_contains "$OUT" "API not responding" "api failure reported"
t_end

t_start "wrong watcher delay warns with expected value"
build_green_env
printf '10' > "$SBX/fixtures/sync/folder.claude-sessions.fswatcher-delays"
run_verify
assert_eq "$RC" 0 "delay drift is warning only"
assert_contains "$OUT" "File watcher delay is 10s (expected 2s)" "delay warning text"
t_end

t_start "wrong folder type warns"
build_green_env
printf 'sendonly' > "$SBX/fixtures/sync/folder.claude-sessions.type"
run_verify
assert_eq "$RC" 0 "type drift is warning only"
assert_contains "$OUT" "Folder type is 'sendonly' (expected sendreceive)" "type warning text"
t_end

t_start "unexpected folder path is an error"
build_green_env
printf '%s' "$HOME/somewhere-else" > "$SBX/fixtures/sync/folder.claude-sessions.path"
run_verify
if [[ "$RC" -eq 0 ]]; then fail_msg "expected nonzero on wrong folder path"; fi
assert_contains "$OUT" "Unexpected path" "path failure reported"
t_end

t_start "folder not configured fails with fix hint"
build_green_env
: > "$SBX/fixtures/sync/folders.list"
run_verify
if [[ "$RC" -eq 0 ]]; then fail_msg "expected nonzero without claude-sessions folder"; fi
assert_contains "$OUT" "claude-sessions folder not configured" "missing folder reported"
assert_contains "$OUT" "Fix: run setup.sh" "fix hint shown"
t_end

t_start "zero connected peers warns but does not fail"
build_green_env
printf '{"connections": {"PEERAAAA": {"connected": false}}}\n' > "$SBX/fixtures/curl/connections.json"
run_verify
assert_eq "$RC" 0 "no peers is warning only"
assert_contains "$OUT" "No peers connected" "peer warning text"
t_end

t_start "syncthing down produces the service failure and fix hint"
build_green_env
PGREP_SYNCTHING=0 run_verify
if [[ "$RC" -eq 0 ]]; then fail_msg "expected nonzero when syncthing not running"; fi
assert_contains "$OUT" "Syncthing is not running" "service failure reported"
assert_contains "$OUT" "systemctl --user start syncthing" "fix hint shown"
t_end

t_start "agent session in personal namespace is flagged"
build_green_env
local_ns="$HOME/.claude/projects/-home-joe-Desktop"
now=$(date +%s)
mkdir -p "$local_ns"
printf '{"type":"user","msg":"hi"} FEDERATION_AGENT_ID=xyz\n' > "$local_ns/agentsession.jsonl"
touch -d "@$((now - 60))" "$local_ns"   # ensure the jsonl is strictly newer than its dir (find -newer)
run_verify
assert_eq "$RC" 0 "agent contamination is warning severity"
assert_contains "$OUT" "Possible agent session in personal namespace" "contamination warning"
t_end

t_start "large session store survives the newest-file scan (SIGPIPE regression)"
build_green_env
ns="$HOME/.claude/projects/-sbx-bulk"
mkdir -p "$ns"
i=0
while (( i < 1200 )); do
    : > "$ns/bulk-$i.jsonl"
    i=$((i + 1))
done
run_verify
assert_eq "$RC" 0 "script completed despite head closing the pipe early"
assert_contains "$OUT" "session file(s) found" "session count line printed"
t_end

t_teardown_all
suite_tally_exit
