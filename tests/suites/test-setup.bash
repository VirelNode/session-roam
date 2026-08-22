#!/usr/bin/env bash
# Behavior tests for setup.sh — argument parsing, bootstrap order, idempotency claims.
# Full daemon flows are out of scope; the stubs make the CLI surface deterministic.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../helpers.bash"
REPO_ROOT="$REPO_ROOT"

SETUP="$REPO_ROOT/setup.sh"
SBX=""

setup_env() {
    t_sandbox
    FIX="$SBX/fixtures/sync"
    export SYNC_FIXTURE="$FIX"; mkdir -p "$FIX"
    printf 'SELFID00000000000000000000000000000' > "$FIX/myid"
    printf 'SELFID00000000000000000000000000000\n' > "$FIX/devices.list"

    CF="$SBX/fixtures/curl"
    export CURL_FIXTURE="$CF"; mkdir -p "$CF"
    printf '{}\n' > "$CF/system-status.json"
    printf '{"requiresRestart": false}\n' > "$CF/restart-required.json"

    mkdir -p "$HOME/.local/state/syncthing"
    cat > "$HOME/.local/state/syncthing/config.xml" <<'XML'
<config>
  <gui>
    <apikey>TESTKEY123</apikey>
  </gui>
</config>
XML
}

run_setup() {
    printf '\n' > "$SBX/stdin.txt"
    t_run_in "$HOME" "$SBX/stdin.txt" "$SETUP" "$@"
}

t_start "--help exits 0 and prints usage without touching anything"
t_sandbox
run_setup --help
assert_eq "$RC" 0 "help rc"
assert_contains "$OUT" "Usage: setup.sh" "usage text"
assert_no_file "$SBX/fixtures/sync/generated" "no config generated on help"
t_end

t_start "unknown option dies nonzero with guidance"
t_sandbox
run_setup --bogus
if [[ "$RC" -eq 0 ]]; then fail_msg "unknown option should fail"; fi
assert_contains "$OUT$ERR" "Unknown option: --bogus" "error names the option"
t_end

t_start "repeated --device-id flags accumulate as peers"
setup_env
run_setup --device-id PEER1111 --device-id PEER2222
assert_eq "$RC" 0 "rc"
assert_contains "$(cat "$FIX/devices.list")" "PEER1111" "first peer added"
assert_contains "$(cat "$FIX/devices.list")" "PEER2222" "second peer added"
assert_eq "$(grep -c . "$FIX/folder.claude-sessions.devices")" 2 "both peers share claude-sessions folder"
t_end

t_start "existing config: no syncthing generate, folder created once with correct settings"
setup_env
run_setup
assert_eq "$RC" 0 "rc"
assert_no_file "$FIX/generated" "generate NOT called when config exists"
assert_contains "$(cat "$FIX/folders.list")" "claude-sessions" "folder registered"
assert_eq "$(cat "$FIX/folder.claude-sessions.fswatcher-delays")" "2" "watcher delay set to 2"
assert_eq "$(cat "$FIX/folder.claude-sessions.type")" "sendreceive" "folder type sendreceive"
assert_contains "$(cat "$STUB_LOG")" "rest/db/scan" "rescan triggered for folder marker"
t_end

t_start "missing config: generate runs before api-key extraction fails honestly"
setup_env
rm -f "$HOME/.local/state/syncthing/config.xml"
run_setup
assert_file "$FIX/generated" "syncthing generate was invoked"
if [[ "$RC" -eq 0 ]]; then fail_msg "expected failure at API key stage (stub creates no config.xml)"; fi
t_end

t_start "already-known device is skipped but folder sharing still applied"
setup_env
printf 'SELFID00000000000000000000000000000\nPEER1111\n' > "$FIX/devices.list"
run_setup --device-id PEER1111
assert_eq "$RC" 0 "rc"
assert_eq "$(grep -c . "$FIX/devices.list")" 2 "no duplicate device entry"
assert_contains "$(cat "$FIX/folder.claude-sessions.devices")" "PEER1111" "folder still shared"
assert_contains "$OUT" "already known" "idempotent add message"
t_end

t_start "folder already configured: not re-added, settings reasserted"
setup_env
printf 'claude-sessions\n' > "$FIX/folders.list"
printf '%s' "/wrong/path" > "$FIX/folder.claude-sessions.path"
printf 'receiveonly' > "$FIX/folder.claude-sessions.type"
run_setup
assert_eq "$RC" 0 "rc"
assert_eq "$(grep -c . "$FIX/folders.list")" 1 "no duplicate folder entry"
assert_eq "$(cat "$FIX/folder.claude-sessions.type")" "sendreceive" "type corrected"
assert_eq "$(cat "$FIX/folder.claude-sessions.fswatcher-delays")" "2" "delay reasserted"
t_end

t_start "restart-required triggers a restart call"
setup_env
printf '{"requiresRestart": true}\n' > "$CF/restart-required.json"
run_setup
assert_eq "$RC" 0 "rc"
assert_contains "$(cat "$STUB_LOG")" "rest/system/restart" "restart endpoint hit"
assert_contains "$(cat "$STUB_LOG" | tail -3)" "rest/system/status" "health re-checked after restart"
t_end

t_teardown_all
suite_tally_exit
