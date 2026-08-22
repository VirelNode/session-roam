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
grep -qF "cf() { claude -r" "$HOME/.bashrc"; assert_eq "$?" 0 "cf function installed"
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
