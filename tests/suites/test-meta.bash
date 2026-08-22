#!/usr/bin/env bash
# Meta checks: syntax, line endings, template sanity
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../helpers.bash"
REPO_ROOT="$REPO_ROOT"

t_start "every shell script passes bash -n"
rc_total=0
errfile="$(mktemp)"
for f in setup.sh cr.sh verify.sh install-aliases.sh tests/run.sh tests/helpers.bash tests/suites/*.bash; do
    bash -n "$REPO_ROOT/$f" 2>"$errfile" || { fail_msg "syntax error in $f: $(cat "$errfile")"; rc_total=1; }
done
rm -f "$errfile"
[[ $rc_total -eq 0 ]] || T_FAILED_NOW=$((T_FAILED_NOW + 1))
t_end

t_start "no CRLF line endings in tracked scripts or templates"
bad=""
for f in "$REPO_ROOT"/*.sh "$REPO_ROOT"/stignore.template "$REPO_ROOT"/tests/stubs/*; do
    if grep -q $'\r' "$f" 2>/dev/null; then bad="$bad ${f##*/}"; fi
done
[[ -z "$bad" ]] || fail_msg "CRLF found in:$bad"
t_end

t_start "stignore.template keeps sessions and excludes the heavy junk"
tmpl="$(cat "$REPO_ROOT/stignore.template")"
assert_contains "$tmpl" "**/subagents" "subagents excluded"
assert_contains "$tmpl" "*worktrees*" "worktrees excluded"
assert_contains "$tmpl" "**/node_modules" "node_modules excluded"
active_rules="$(grep -vE '^[[:space:]]*//' "$REPO_ROOT/stignore.template" | grep -v '^[[:space:]]*$')"
if printf '%s' "$active_rules" | grep -Eq 'jsonl|memory|MEMORY'; then
    fail_msg "an active rule excludes sessions or memory"
fi
if grep -E '^\s*//\s*\*\*\.sync-conflict' "$REPO_ROOT/stignore.template" >/dev/null; then :; else
    fail_msg "conflict-ignore rule should stay commented out"
fi
t_end

t_start "shellcheck clean (skipped when shellcheck absent)"
if ! command -v shellcheck >/dev/null 2>&1; then
    t_skip "shellcheck not installed on this node"
else
    sc_fail=0
    for f in "$REPO_ROOT"/*.sh; do
        shellcheck -S warning "$f" || sc_fail=1
    done
    (( sc_fail == 0 )) || fail_msg "shellcheck reported issues"
    t_end
fi

suite_tally_exit
