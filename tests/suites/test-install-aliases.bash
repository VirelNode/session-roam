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

t_start "outdated session-roam alias block is replaced; surrounding lines and a backup kept"
t_sandbox
# The April 2026 block: same marker, but cs/cf call claude directly and bypass cr's lock.
cat > "$HOME/.bash_aliases" <<'OLD'
# my stuff before
alias ll='ls -l'

# session-roam aliases — https://github.com/VirelNode/session-roam
# cs  = browse all sessions
alias cs='claude -r'
cf() { claude -r "$*"; }
alias crf='sleep 2 && claude -c --fork-session'

# my stuff after
alias gs='git status'
OLD
run_installer
assert_eq "$RC" 0 "installer exits 0"
al="$(cat "$HOME/.bash_aliases")"
assert_contains "$al" "alias cs='cr --browse'" "cs now routes through cr"
assert_contains "$al" 'cf() { cr --search' "cf now routes through cr"
assert_eq "$(grep -c "alias cs='claude -r'" "$HOME/.bash_aliases")" 0 "old cs alias gone"
assert_eq "$(grep -cF '# session-roam aliases' "$HOME/.bash_aliases")" 1 "exactly one block"
assert_contains "$al" "alias ll='ls -l'" "line before block kept"
assert_contains "$al" "alias gs='git status'" "line after block kept"
assert_file "$HOME/.bash_aliases.session-roam.bak" "backup of the pre-upgrade file written"
assert_contains "$OUT$ERR" "Updated outdated session-roam aliases" "upgrade reported"
before="$(cat "$HOME/.bash_aliases")"
run_installer
assert_eq "$(cat "$HOME/.bash_aliases")" "$before" "second run changes nothing"
assert_contains "$OUT$ERR" "already has session-roam aliases" "second run reports current block"
t_end

t_start "outdated block upgrade never deletes user lines (no blank line after block, CRLF file)"
t_sandbox
printf "# session-roam aliases — https://github.com/VirelNode/session-roam\nalias cs='claude -r'\nalias gs='git status'\n" > "$HOME/.bash_aliases"
run_installer
assert_contains "$(cat "$HOME/.bash_aliases")" "alias gs='git status'" "user line right after block kept"
assert_eq "$(grep -c "alias cs='claude -r'" "$HOME/.bash_aliases")" 0 "old cs alias gone"
t_sandbox
printf "# before\r\n\r\n# session-roam aliases — https://github.com/VirelNode/session-roam\r\n# cs  = browse all sessions\r\nalias cs='claude -r'\r\n\r\n# after\r\nalias gs='git status'\r\n" > "$HOME/.bash_aliases"
run_installer
al="$(cat "$HOME/.bash_aliases")"
assert_contains "$al" "alias gs='git status'" "CRLF: line after block kept"
assert_contains "$al" "# before" "CRLF: line before block kept"
assert_eq "$(grep -c "alias cs='claude -r'" "$HOME/.bash_aliases")" 0 "CRLF: old cs alias gone"
assert_contains "$al" "alias cs='cr --browse'" "CRLF: current block present"
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
