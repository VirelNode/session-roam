#!/usr/bin/env bash
# Meta checks: syntax, line endings, template sanity
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../helpers.bash"
REPO_ROOT="$REPO_ROOT"

t_start "every shell script passes the syntax check (-n) of the bash under test"
rc_total=0
errfile="$(mktemp)"
for f in setup.sh cr.sh verify.sh install-aliases.sh tests/run.sh tests/helpers.bash tests/suites/*.bash; do
    "$BASH" -n "$REPO_ROOT/$f" 2>"$errfile" || { fail_msg "syntax error in $f: $(cat "$errfile")"; rc_total=1; }
done
rm -f "$errfile"
[[ $rc_total -eq 0 ]] || T_FAILED_NOW=$((T_FAILED_NOW + 1))
t_end

t_start "scripts under test run with the invoking bash, not PATH bash"
t_sandbox
printf 'printf "%%s" "$BASH_VERSION"\n' > "$SBX/ver.sh"
t_run_in "$SBX" - "$SBX/ver.sh"
assert_eq "$OUT" "$BASH_VERSION" "t_run_in child reports the suite's bash version"
# A launch of PATH bash (`bash <script>`, `bash -opts "$x"`, `bash -c`, `bash -n`,
# `exec bash`, `$(bash ...)`) in the harness would bypass "$BASH".
LAUNCH_RE='(^|[^A-Za-z0-9_/"$.-])bash[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(["'"'"'$]|[A-Za-z0-9_./-]+\.(ba)?sh([^A-Za-z0-9]|$))'
for good in 'bash tests/example.bash' 'bash -eu "$x"' "bash 'x.sh'" $'bash\t"$x"' 'exec bash "$CR"' "bash -c 'echo'" 'bash -n "$f"' 'x=$(bash "$s")'; do
    printf '%s\n' "$good" | grep -qE "$LAUNCH_RE" || fail_msg "guard misses launch: $good"
done
for bad in "printf 'bash -c example\n'" '"$BASH" "$CR"' 'printf "bash under test: %s"' 't_start "of the bash under test"'; do
    printf '%s\n' "$bad" | grep -qE "$LAUNCH_RE" && fail_msg "guard flags non-launch: $bad"
done
hits="$(grep -nE "$LAUNCH_RE" "$REPO_ROOT"/tests/run.sh "$REPO_ROOT"/tests/helpers.bash "$REPO_ROOT"/tests/suites/*.bash | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v 'LAUNCH_RE=' | grep -vE ':[0-9]+:for (good|bad) in ')"
[[ -z "$hits" ]] || fail_msg "PATH-bash launches found: $hits"
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
assert_contains "$tmpl" "*.roam-lock.tmp" "lock temp flicker excluded from sync"
active_rules="$(grep -vE '^[[:space:]]*//' "$REPO_ROOT/stignore.template" | grep -v '^[[:space:]]*$')"
if printf '%s' "$active_rules" | grep -Eq 'jsonl|memory|MEMORY'; then
    fail_msg "an active rule excludes sessions or memory"
fi
if printf '%s' "$active_rules" | grep -qF '.roam-lock.json'; then
    fail_msg "the live lock file itself must stay synced"
fi
if grep -E '^\s*//\s*\*\*\.sync-conflict' "$REPO_ROOT/stignore.template" >/dev/null; then :; else
    fail_msg "conflict-ignore rule should stay commented out"
fi
t_end

t_start "portability lint: no bash4-only expansion, suffix-less sed -i, GNU-only find/stat"
bad=""
if grep -n ',,' setup.sh cr.sh verify.sh install-aliases.sh lib/session-lock.sh >/dev/null 2>&1; then bad="$bad lowercase-expansion"; fi
if grep -nE 'sed -i [^.]' install-aliases.sh setup.sh >/dev/null 2>&1; then bad="$bad suffixless-sed-i"; fi
if grep -n 'find.*-printf' cr.sh verify.sh >/dev/null 2>&1; then bad="$bad gnu-find-printf"; fi
while IFS= read -r pline; do
    case "$pline" in *"|| stat -f"*) ;; *) bad="$bad bare-stat-c";; esac
done < <(grep -h 'stat -c' cr.sh verify.sh install-aliases.sh lib/session-lock.sh 2>/dev/null)
[[ -z "$bad" ]] || fail_msg "portability offenders:$bad"
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
