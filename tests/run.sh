#!/usr/bin/env bash
# session-roam test runner: discovers suites in tests/suites/, aggregates tallies

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_DIR="$REPO_ROOT/tests"

total_pass=0 total_fail=0 total_skip=0
failed_suites=()

for suite in "$RUNNER_DIR"/suites/test-*.bash; do
    [[ -e "$suite" ]] || { echo "no suites found" >&2; exit 1; }
    name="$(basename "$suite")"
    printf '\n=== %s ===\n' "$name"
    out="$(bash "$suite" 2>&1)"
    rc=$?
    printf '%s\n' "$out"
    tally="$(printf '%s\n' "$out" | grep -oE 'SUITE_TALLY pass=[0-9]+ fail=[0-9]+ skip=[0-9]+' | tail -1)"
    p="$(printf '%s' "$tally" | sed -n 's/.*pass=\([0-9]*\).*/\1/p')"
    f="$(printf '%s' "$tally" | sed -n 's/.*fail=\([0-9]*\).*/\1/p')"
    s="$(printf '%s' "$tally" | sed -n 's/.*skip=\([0-9]*\).*/\1/p')"
    total_pass=$((total_pass + ${p:-0}))
    total_fail=$((total_fail + ${f:-0}))
    total_skip=$((total_skip + ${s:-0}))
    (( rc == 0 )) || failed_suites+=("$name")
done

printf '\n======================================\n'
printf 'TOTAL: %d passed, %d failed, %d skipped\n' "$total_pass" "$total_fail" "$total_skip"
if (( ${#failed_suites[@]} > 0 )); then
    printf 'Failing suites: %s\n' "${failed_suites[*]}"
fi
(( total_fail == 0 )) && exit 0
exit 1
