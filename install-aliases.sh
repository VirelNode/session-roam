#!/usr/bin/env bash
set -euo pipefail

# session-roam: Install Claude Code session shortcuts
# https://github.com/VirelNode/session-roam

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf '%s[OK]%s %s\n' "$GREEN" "$NC" "$1"; }
warn() { printf '%s[!!]%s %s\n' "$YELLOW" "$NC" "$1"; }
info() { printf '%s[..]%s %s\n' "$NC" "$NC" "$1"; }

MARKER="# session-roam aliases"

ALIASES_BLOCK='
# session-roam aliases — https://github.com/VirelNode/session-roam
# cr  = continue recent (smart wrapper in ~/.local/bin/cr)
# cs  = browse all sessions
# cf  = find/search sessions by keyword
# cn  = start a named session
# cfork = fork a past session (resume without overwriting)
# crf = branch off your last conversation
alias cs='"'"'cr --browse'"'"'
cf() { cr --search "$*"; }
cn() { claude -n "$*"; }
cfork() { claude --resume "$1" --fork-session; }
alias crf='"'"'sleep 2 && claude -c --fork-session'"'"'
'

install_to_file() {
    local target="$1"
    local name="$2"

    if [[ ! -f "$target" ]]; then
        info "Creating $target"
        touch "$target"
    fi

    if grep -qF "$MARKER" "$target" 2>/dev/null; then
        ok "$name already has session-roam aliases (skipping)"
        return 0
    fi

    printf '\n%s\n' "$ALIASES_BLOCK" >> "$target"
    ok "Installed aliases to $name"
}

# ─── Install .stignore ────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STIGNORE_SRC="${SCRIPT_DIR}/stignore.template"
STIGNORE_DST="$HOME/.claude/projects/.stignore"

if [[ -f "$STIGNORE_SRC" ]]; then
    mkdir -p "$(dirname "$STIGNORE_DST")"
    if [[ -f "$STIGNORE_DST" ]]; then
        warn ".stignore already exists at $STIGNORE_DST (not overwriting)"
    else
        cp "$STIGNORE_SRC" "$STIGNORE_DST"
        ok "Installed .stignore to ~/.claude/projects/"
    fi
else
    warn "stignore.template not found in script directory (skipping)"
fi

# ─── Deploy cr.sh smart wrapper ───────────────────────────────
CR_SRC="${SCRIPT_DIR}/cr.sh"
CR_DST="$HOME/.local/bin/cr"

if [[ -f "$CR_SRC" ]]; then
    mkdir -p "$HOME/.local/bin"
    cp "$CR_SRC" "$CR_DST"
    chmod +x "$CR_DST"
    ok "Deployed cr.sh to ~/.local/bin/cr"
else
    warn "cr.sh not found in script directory (skipping)"
fi

# ─── Deploy session-lock library (used by cr + verify) ────────
LOCK_SRC="${SCRIPT_DIR}/lib/session-lock.sh"
LOCK_DST="$HOME/.local/lib/session-roam/session-lock.sh"

if [[ -f "$LOCK_SRC" ]]; then
    mkdir -p "$(dirname "$LOCK_DST")"
    cp "$LOCK_SRC" "$LOCK_DST"
    ok "Deployed session-lock library to ~/.local/lib/session-roam/"
else
    warn "lib/session-lock.sh not found in script directory (skipping)"
fi

# ─── Install aliases ──────────────────────────────────────────
echo ""
printf '%s%s%s\n' "$BOLD" "Installing Claude Code session shortcuts..." "$NC"
echo ""

# Detect shell config files
installed=false

# bash
if [[ -f "$HOME/.bash_aliases" ]]; then
    install_to_file "$HOME/.bash_aliases" "~/.bash_aliases"
    installed=true
elif [[ -f "$HOME/.bashrc" ]]; then
    install_to_file "$HOME/.bashrc" "~/.bashrc"
    installed=true
fi

# zsh
if [[ -f "$HOME/.zshrc" ]]; then
    install_to_file "$HOME/.zshrc" "~/.zshrc"
    installed=true
fi

# Fallback: create .bash_aliases if nothing found
if [[ "$installed" == "false" ]]; then
    install_to_file "$HOME/.bash_aliases" "~/.bash_aliases"
    warn "Created ~/.bash_aliases — make sure your .bashrc sources it"
fi

# ─── Remove old cr alias (now handled by ~/.local/bin/cr) ─────
for rc_file in "$HOME/.bash_aliases" "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc_file" ]] && grep -qF "alias cr=" "$rc_file"; then
        tmp_file="${rc_file}.roam-tmp.$$"
        awk '!/^alias cr=/ || index($0, "claude") == 0' "$rc_file" > "$tmp_file"
        if cmp -s "$tmp_file" "$rc_file"; then
            rm -f "$tmp_file"
            info "Left unrelated alias cr= in $(basename "$rc_file") untouched"
        else
            mv "$tmp_file" "$rc_file"
            ok "Removed legacy claude cr alias from $(basename "$rc_file") (now using ~/.local/bin/cr)"
        fi
    fi
done

# ─── Summary ──────────────────────────────────────────────────
echo ""
printf '%s%s%s\n' "$BOLD" "Shortcuts installed:" "$NC"
echo ""
echo "  cr            Smart resume -- namespace check + stale warning (cross-node)"
echo "  cs            Browse all past sessions interactively"
echo '  cf "keyword"  Search sessions by keyword'
echo '  cn "name"     Start a new named session'
echo "  cfork ID      Resume a past session without modifying it"
echo "  crf           Branch off your last conversation"
echo ""
info "Reload your shell to use: source ~/.bashrc  or  source ~/.zshrc"
