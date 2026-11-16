#!/usr/bin/env bash
# Behavior tests for install-aliases.sh
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../helpers.bash"
REPO_ROOT="$REPO_ROOT"

INSTALLER="$REPO_ROOT/install-aliases.sh"
SBX=""

run_installer() {
    t_run_in "$HOME" - "$INSTALLER"
}

t_start "installs alias block into existing .bashrc exactly once"
t_sandbox
printf '# my rc\n' > "$HOME/.bashrc"
run_installer
assert_eq "$RC" 0 "installer exits 0"
grep -qF "# session-roam aliases" "$HOME/.bashrc"; assert_eq "$?" 0 "marker present in .bashrc"
grep -qF "cf() { cr --search" "$HOME/.bashrc"; assert_eq "$?" 0 "cf function installed (lock-routed)"
grep -qF "alias cs='cr --browse'" "$HOME/.bashrc"; assert_eq "$?" 0 "cs alias lock-routed"
grep -qF "cn() { claude -n" "$HOME/.bashrc"; assert_eq "$?" 0 "cn function installed"
grep -qF "cfork() { claude --resume" "$HOME/.bashrc"; assert_eq "$?" 0 "cfork function installed"
before="$(md5sum < "$HOME/.bashrc")"
run_installer
after="$(md5sum < "$HOME/.bashrc")"
assert_contains "$OUT" "already has session-roam aliases" "second run detected marker"
assert_eq "$after" "$before" "second run leaves .bashrc byte-identical"
t_end

t_start "prefers .bash_aliases over .bashrc when both exist"
t_sandbox
printf '# bashrc\n' > "$HOME/.bashrc"
printf '# aliases\n' > "$HOME/.bash_aliases"
run_installer
grep -qF "# session-roam aliases" "$HOME/.bash_aliases"; assert_eq "$?" 0 "block in .bash_aliases"
if grep -qF "# session-roam aliases" "$HOME/.bashrc"; then
    fail_msg ".bashrc should be untouched when .bash_aliases exists"
fi
t_end

t_start "zsh-only config receives the block; no bash fallback created"
t_sandbox
printf '# zsh\n' > "$HOME/.zshrc"
run_installer
grep -qF "# session-roam aliases" "$HOME/.zshrc"; assert_eq "$?" 0 "block in .zshrc"
assert_no_file "$HOME/.bash_aliases" "no bash target when none existed"
t_end

t_start "no rc files anywhere: creates .bash_aliases with a source hint warning"
t_sandbox
rm -rf "$HOME/.bashrc" "$HOME/.bash_aliases" "$HOME/.zshrc"
run_installer
assert_file "$HOME/.bash_aliases"
assert_contains "$OUT$ERR" "make sure your .bashrc sources it" "warns about sourcing"
t_end

t_start ".stignore copied into ~/.claude/projects/"
t_sandbox
run_installer
assert_file "$HOME/.claude/projects/.stignore"
grep -qF "worktrees" "$HOME/.claude/projects/.stignore"; assert_eq "$?" 0 "stignore content came from template"
t_end

t_start "existing .stignore is never overwritten"
t_sandbox
mkdir -p "$HOME/.claude/projects"
printf 'MY CUSTOM IGNORES\n' > "$HOME/.claude/projects/.stignore"
run_installer
assert_contains "$(cat "$HOME/.claude/projects/.stignore")" "MY CUSTOM IGNORES" "custom stignore preserved"
assert_contains "$OUT$ERR" "not overwriting" "warns about skipping"
t_end

# The block every install between 2026-04-11 and 2026-08-22 wrote (3559899):
# cs/cf call claude directly and bypass cr's lock.
april_block() {
    cat <<'APRIL'
# session-roam aliases — https://github.com/VirelNode/session-roam
# cr  = continue recent (smart wrapper in ~/.local/bin/cr)
# cs  = browse all sessions
# cf  = find/search sessions by keyword
# cn  = start a named session
# cfork = fork a past session (resume without overwriting)
# crf = branch off your last conversation
alias cs='claude -r'
cf() { claude -r "$*"; }
cn() { claude -n "$*"; }
cfork() { claude --resume "$1" --fork-session; }
alias crf='sleep 2 && claude -c --fork-session'
APRIL
}

# Source an rc file the way an interactive bash would (aliases expanded) and
# report what cs and cf resolve to. Sets SRC_RC, CS_DEF, CF_DEF.
resolve_shortcuts() {
    local out
    out="$("$BASH" -c 'shopt -s expand_aliases; . "$1"; echo "rc=$?"; alias cs 2>&1; declare -f cf 2>&1' _ "$1" 2>&1)"
    SRC_RC="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
    CS_DEF="$(printf '%s\n' "$out" | grep "^alias cs=")"
    CF_DEF="$(printf '%s\n' "$out" | grep -A3 '^cf ()' | tr -s ' \n' ' ')"
}

assert_routes_through_cr() { # assert_routes_through_cr <rc-file> <label>
    resolve_shortcuts "$1"
    assert_eq "$SRC_RC" 0 "$2: file sources cleanly with aliases on"
    assert_contains "$CS_DEF" "cr --browse" "$2: cs goes through cr"
    assert_contains "$CF_DEF" "cr --search" "$2: cf goes through cr"
}

t_start "exact April block is replaced; surrounding lines kept; backup; second run no-op"
t_sandbox
{ printf '# my stuff before\nalias ll='"'"'ls -l'"'"'\n\n'; april_block; printf '\n# my stuff after\nalias gs='"'"'git status'"'"'\n'; } > "$HOME/.bash_aliases"
run_installer
assert_eq "$RC" 0 "installer exits 0"
al="$(cat "$HOME/.bash_aliases")"
assert_eq "$(grep -c 'claude -r' "$HOME/.bash_aliases")" 0 "April cs/cf lines gone"
assert_eq "$(grep -cF '# session-roam aliases' "$HOME/.bash_aliases")" 1 "exactly one block"
assert_contains "$al" "alias ll='ls -l'" "line before block kept"
assert_contains "$al" "alias gs='git status'" "line after block kept"
assert_file "$HOME/.bash_aliases.session-roam.bak" "backup written"
assert_contains "$OUT$ERR" "Updated outdated session-roam aliases" "upgrade reported"
assert_routes_through_cr "$HOME/.bash_aliases" "April upgrade"
before="$(cat "$HOME/.bash_aliases")"
run_installer
assert_eq "$(cat "$HOME/.bash_aliases")" "$before" "second run changes nothing"
assert_contains "$OUT$ERR" "already has session-roam aliases" "second run reports current block"
t_end

t_start "exact April block in a CRLF file, and with no blank line after it, never takes user lines"
t_sandbox
{ april_block; printf 'alias gs='"'"'git status'"'"'\n'; } > "$HOME/.bash_aliases"
run_installer
assert_contains "$(cat "$HOME/.bash_aliases")" "alias gs='git status'" "user line right after block kept"
assert_eq "$(grep -c 'claude -r' "$HOME/.bash_aliases")" 0 "April lines gone"
t_sandbox
{ printf '# before\n\n'; april_block; printf '\n# after\nalias gs='"'"'git status'"'"'\n'; } | sed 's/$/\r/' > "$HOME/.bash_aliases"
run_installer
al="$(cat "$HOME/.bash_aliases")"
assert_contains "$al" "alias gs='git status'" "CRLF: line after block kept"
assert_contains "$al" "# before" "CRLF: line before block kept"
assert_eq "$(grep -c 'claude -r' "$HOME/.bash_aliases")" 0 "CRLF: April lines gone"
t_end

t_start "a block the user edited is left byte-for-byte; appended block still wins when sourced"
# Each case is a valid customization a line-matcher could split (Dex review r2).
for variant in multiline-alias nested-func alias-then-export user-alias-cf; do
    t_sandbox
    case "$variant" in
        multiline-alias)   printf "# session-roam aliases\nalias cs='\n  claude -r\n'\n" ;;
        nested-func)       printf '# session-roam aliases\ncf() { inner() { :; }\n  claude -r "$*"\n}\n' ;;
        alias-then-export) printf "# session-roam aliases\nalias cs='claude -r'; export KEEP_ME=yes\n" ;;
        user-alias-cf)     printf "# session-roam aliases\nalias cs='claude -r'\n# user adjustment\nalias cf='claude -r'\n" ;;
    esac > "$HOME/.bash_aliases"
    orig="$(cat "$HOME/.bash_aliases")"
    run_installer
    assert_eq "$RC" 0 "$variant: installer exits 0"
    now="$(cat "$HOME/.bash_aliases")"
    assert_eq "${now:0:${#orig}}" "$orig" "$variant: original content untouched"
    assert_contains "$OUT$ERR" "did not write" "$variant: user told their block was left alone"
    assert_routes_through_cr "$HOME/.bash_aliases" "$variant"
done
t_end

t_start "current block plus a stale duplicate: stale removed, one block left, backups never overwritten"
t_sandbox
run_installer
april_block >> "$HOME/.bash_aliases"
run_installer
assert_eq "$(grep -c 'claude -r' "$HOME/.bash_aliases")" 0 "stale duplicate removed"
assert_eq "$(grep -cF '# session-roam aliases' "$HOME/.bash_aliases")" 1 "exactly one block left"
first="$(cat "$HOME/.bash_aliases.session-roam.bak")"
april_block >> "$HOME/.bash_aliases"
run_installer
assert_eq "$(cat "$HOME/.bash_aliases.session-roam.bak")" "$first" "first backup preserved"
assert_eq "$(ls "$HOME"/.bash_aliases.session-roam.bak* | wc -l | tr -d ' ')" 2 "second backup written alongside"
assert_routes_through_cr "$HOME/.bash_aliases" "after duplicate cleanup"
t_end

t_start "a look-alike comment is not a block"
t_sandbox
printf '# session-roam aliases customization\nexport KEEP=1\n' > "$HOME/.bash_aliases"
run_installer
al="$(cat "$HOME/.bash_aliases")"
assert_contains "$al" "# session-roam aliases customization" "look-alike comment kept"
assert_contains "$al" "export KEEP=1" "line after look-alike kept"
t_end

t_start "existing .stignore gains rules added to the template since it was installed"
t_sandbox
mkdir -p "$HOME/.claude/projects"
# An install from before the session lock existed: has worktrees, lacks the lock temp rule.
printf 'MY CUSTOM IGNORES\n*worktrees*\n' > "$HOME/.claude/projects/.stignore"
run_installer
st="$(cat "$HOME/.claude/projects/.stignore")"
assert_contains "$st" "MY CUSTOM IGNORES" "custom rule kept"
assert_contains "$st" "*.roam-lock.tmp" "missing template rule appended"
assert_eq "$(grep -cxF '*worktrees*' "$HOME/.claude/projects/.stignore")" 1 "rule already present is not duplicated"
assert_eq "$(head -1 "$HOME/.claude/projects/.stignore")" "MY CUSTOM IGNORES" "existing lines stay first, in order"
before="$(cat "$HOME/.claude/projects/.stignore")"
run_installer
assert_eq "$(cat "$HOME/.claude/projects/.stignore")" "$before" "second run changes nothing"
t_end

t_start "missing stignore.template warns but installation continues"
t_sandbox
mkdir -p "$SBX/isolated"
cp "$INSTALLER" "$SBX/isolated/"
t_run_in "$HOME" - "$SBX/isolated/install-aliases.sh"
assert_contains "$OUT$ERR" "stignore.template not found" "template warning shown"
assert_contains "$OUT$ERR" "cr.sh not found" "missing cr.sh warning shown"
grep -qF "# session-roam aliases" "$HOME/.bash_aliases"; assert_eq "$?" 0 "aliases still installed"
assert_no_file "$HOME/.local/bin/cr" "no cr deployed without source"
t_end

t_start "deploys executable cr wrapper to ~/.local/bin/cr"
t_sandbox
run_installer
assert_exec "$HOME/.local/bin/cr"
cmp -s "$REPO_ROOT/cr.sh" "$HOME/.local/bin/cr"; assert_eq "$?" 0 "deployed copy matches source"
assert_file "$HOME/.local/lib/session-roam/session-lock.sh"
cmp -s "$REPO_ROOT/lib/session-lock.sh" "$HOME/.local/lib/session-roam/session-lock.sh"; assert_eq "$?" 0 "lock lib deployed matches source"
t_end

t_start "creates ~/.claude/projects when missing instead of failing hard"
t_sandbox
rm -rf "$HOME/.claude/projects"
run_installer
assert_eq "$RC" 0 "installer survives missing projects dir"
assert_file "$HOME/.claude/projects/.stignore" "stignore landed after implicit mkdir"
t_end

t_start "keeps an unrelated alias cr= and removes only the legacy claude one"
t_sandbox
printf "alias cr='/opt/tools/cr-launcher'\nalias cr='sleep 2 && claude -c'\nexport EDITOR=vim\n" > "$HOME/.bashrc"
run_installer
if grep -qF "/opt/tools/cr-launcher" "$HOME/.bashrc"; then :; else fail_msg "unrelated cr alias was deleted"; fi
if grep -qF "alias cr='sleep 2 && claude -c'" "$HOME/.bashrc"; then fail_msg "legacy claude alias survived cleanup"; fi
grep -qF "export EDITOR=vim" "$HOME/.bashrc"; assert_eq "$?" 0 "unrelated lines kept"
assert_contains "$OUT$ERR" "Removed legacy claude cr alias" "targeted removal announced"
t_end

t_start "removes a pre-existing plain 'alias cr=' line"
t_sandbox
printf 'alias cs="claude -r"\nalias cr='"'"'sleep 2 && claude -c'"'"'\nexport EDITOR=vim\n' > "$HOME/.bashrc"
run_installer
if grep -qF "alias cr=" "$HOME/.bashrc"; then
    fail_msg "old alias cr= line still present"
else
    : 
fi
grep -qF 'alias cs=' "$HOME/.bashrc"; assert_eq "$?" 0 "unrelated aliases kept"
grep -qF "export EDITOR=vim" "$HOME/.bashrc"; assert_eq "$?" 0 "unrelated lines kept"
assert_exec "$HOME/.local/bin/cr" "wrapper deployed to replace alias"
t_end

t_teardown_all
suite_tally_exit
