#!/usr/bin/env bash
set -euo pipefail

# session-roam: Install Claude Code session shortcuts
# https://github.com/VirelNode/session-roam

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
# unalias: drop any earlier alias of these names so the definitions below
# win and `cf()` etc. parse even if a user or older block aliased them.
unalias cr cs cf cn cfork crf 2>/dev/null || true
alias cs='"'"'cr --browse'"'"'
cf() { cr --search "$*"; }
cn() { claude -n "$*"; }
cfork() { claude --resume "$1" --fork-session; }
alias crf='"'"'sleep 2 && claude -c --fork-session'"'"'
'

# Every alias block earlier versions of this installer wrote, byte for byte
# (from git history: ce8146c 2026-04-11, 3559899 2026-04-11..2026-08-22,
# d96252a 2026-08-22..2026-11-16). On upgrade only exact copies of these, or
# of the current block, are removed. Anything else in the file, including a
# block the user edited, is never touched; the current block appended at the
# end overrides it. Blocks are separated by a line containing only "@@".
known_old_blocks() {
    cat <<'KNOWN'
# session-roam aliases — https://github.com/VirelNode/session-roam
# cr  = continue recent (2s Syncthing delay)
# cs  = browse all sessions
# cf  = find/search sessions by keyword
# cn  = start a named session
# cfork = fork a past session (resume without overwriting)
# crf = branch off your last conversation
alias cr='sleep 2 && claude -c'
alias cs='claude -r'
cf() { claude -r "$*"; }
cn() { claude -n "$*"; }
cfork() { claude --resume "$1" --fork-session; }
alias crf='sleep 2 && claude -c --fork-session'
@@
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
@@
# session-roam aliases — https://github.com/VirelNode/session-roam
# cr  = continue recent (smart wrapper in ~/.local/bin/cr)
# cs  = browse all sessions
# cf  = find/search sessions by keyword
# cn  = start a named session
# cfork = fork a past session (resume without overwriting)
# crf = branch off your last conversation
alias cs='cr --browse'
cf() { cr --search "$*"; }
cn() { claude -n "$*"; }
cfork() { claude --resume "$1" --fork-session; }
alias crf='sleep 2 && claude -c --fork-session'
@@
KNOWN
}

# Exact-block scanner. First input: blocks separated by "@@" lines (block 1 is
# the current one). Second input: the rc file. Trailing \r is ignored when
# comparing. mode=count prints "<current> <old>" occurrence counts;
# mode=strip prints the rc file without those blocks (and one blank line
# after each), every other line unchanged. count also prints how many
# non-blank lines follow the last current block (it must be last to win).
BLOCK_SCAN_AWK='
    BEGIN { nb = 1 }
    FNR == NR { if ($0 == "@@") { nb++; next } k[nb, ++kl[nb]] = $0; next }
    { l = $0; sub(/\r$/, "", l); n++; L[n] = l; R[n] = $0 }
    END {
        i = 1
        while (i <= n) {
            hit = 0
            for (b = 1; b <= nb; b++) {
                m = kl[b] + 0; if (m == 0) continue
                ok = 1
                for (j = 1; j <= m; j++) if (i + j - 1 > n || L[i + j - 1] != k[b, j]) { ok = 0; break }
                if (ok) { cnt[b]++; if (b == 1) after = 0; i += m; if (i <= n && L[i] == "") i++; hit = 1; break }
            }
            if (!hit) { if (mode == "strip") print R[i]; if (L[i] != "") after++; i++ }
        }
        if (mode == "count") { old = 0; for (b = 2; b <= nb; b++) old += cnt[b]; print cnt[1] + 0, old, after + 0 }
    }'

# rewrite_keeps_syntax <original> <candidate>: true only if a parser for the
# file's shell is available and it accepts the candidate (or rejected the
# original too, so the rewrite cannot be what broke it).
rewrite_keeps_syntax() {
    local checker
    case "$1" in
        *zshrc) checker="$(command -v zsh 2>/dev/null)" ;;
        *)      checker="${BASH:-$(command -v bash)}" ;;
    esac
    [[ -n "$checker" ]] || return 1
    "$checker" -n "$2" 2>/dev/null && return 0
    ! "$checker" -n "$1" 2>/dev/null
}

install_to_file() {
    local target="$1"
    local name="$2"

    if [[ ! -f "$target" ]]; then
        info "Creating $target"
        touch "$target"
    fi

    local known tmp_file counts n_cur n_old backup
    known="${target}.roam-known.$$"
    # Current block first (leading blank line dropped), then every old one.
    { printf '%s\n' "$ALIASES_BLOCK" | sed '1{/^$/d;}'; printf '@@\n'; known_old_blocks; } > "$known"
    counts="$(awk -v mode=count "$BLOCK_SCAN_AWK" "$known" "$target")"
    local n_after
    read -r n_cur n_old n_after <<<"$counts"

    if [[ "$n_cur" == 1 && "$n_old" == 0 && "$n_after" == 0 ]]; then
        rm -f "$known"
        ok "$name already has session-roam aliases (skipping)"
        return 0
    fi

    if [[ "$n_cur" == 0 && "$n_old" == 0 ]]; then
        rm -f "$known"
        if grep -qF "$MARKER" "$target" 2>/dev/null; then
            warn "$name has a session-roam block this installer did not write (edited?); leaving it untouched"
        fi
        printf '\n%s\n' "$ALIASES_BLOCK" >> "$target"
        ok "Installed aliases to $name"
        return 0
    fi

    # Old block(s) and/or duplicate current blocks: back up (never overwriting
    # an earlier backup), remove the exact copies, append one current block.
    tmp_file="${target}.roam-tmp.$$"
    awk -v mode=strip "$BLOCK_SCAN_AWK" "$known" "$target" > "$tmp_file"
    printf '%s\n' "$ALIASES_BLOCK" >> "$tmp_file"
    rm -f "$known"
    # Removal ignores shell context (a shipped block could sit inside a
    # function or heredoc). If the rewrite would stop the file parsing, or no
    # parser is available to check it, remove nothing and only append.
    if ! rewrite_keeps_syntax "$target" "$tmp_file"; then
        rm -f "$tmp_file"
        printf '\n%s\n' "$ALIASES_BLOCK" >> "$target"
        warn "$name: removing the old block would break its syntax (or could not be checked); appended the current block instead, which overrides it"
        return 0
    fi
    backup="${target}.session-roam.bak"
    [[ -e "$backup" ]] && backup="${backup}.$(date +%Y%m%d%H%M%S).$$"
    cp "$target" "$backup"
    cat "$tmp_file" > "$target"
    rm -f "$tmp_file"
    ok "Updated outdated session-roam aliases in $name (backup: $backup)"
}

# ─── Install .stignore ────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STIGNORE_SRC="${SCRIPT_DIR}/stignore.template"
STIGNORE_DST="$HOME/.claude/projects/.stignore"

if [[ -f "$STIGNORE_SRC" ]]; then
    mkdir -p "$(dirname "$STIGNORE_DST")"
    if [[ -f "$STIGNORE_DST" ]]; then
        warn ".stignore already exists at $STIGNORE_DST (not overwriting)"
        # Upgrade path: append template rules the existing file lacks, so older
        # installs pick up new patterns. Existing lines are never removed or reordered.
        missing=""
        while IFS= read -r rule || [[ -n "$rule" ]]; do
            case "$rule" in ''|//*) continue ;; esac
            grep -qxF -- "$rule" "$STIGNORE_DST" || missing="${missing}${rule}"$'\n'
        done < "$STIGNORE_SRC"
        if [[ -n "$missing" ]]; then
            [[ -s "$STIGNORE_DST" && -n "$(tail -c1 "$STIGNORE_DST")" ]] && printf '\n' >> "$STIGNORE_DST"
            printf '\n// ─── added by session-roam install-aliases.sh ───\n%s' "$missing" >> "$STIGNORE_DST"
            ok "Appended $(printf '%s' "$missing" | grep -c .) new template rule(s) to .stignore"
        fi
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
    install_to_file "$HOME/.bash_aliases" "$HOME/.bash_aliases"
    installed=true
elif [[ -f "$HOME/.bashrc" ]]; then
    install_to_file "$HOME/.bashrc" "$HOME/.bashrc"
    installed=true
fi

# zsh
if [[ -f "$HOME/.zshrc" ]]; then
    install_to_file "$HOME/.zshrc" "$HOME/.zshrc"
    installed=true
fi

# Fallback: create .bash_aliases if nothing found
if [[ "$installed" == "false" ]]; then
    install_to_file "$HOME/.bash_aliases" "$HOME/.bash_aliases"
    warn "Created $HOME/.bash_aliases — make sure your .bashrc sources it"
fi

# ─── Remove old cr alias (now handled by ~/.local/bin/cr) ─────
for rc_file in "$HOME/.bash_aliases" "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc_file" ]] && grep -qF "alias cr=" "$rc_file"; then
        tmp_file="${rc_file}.roam-tmp.$$"
        # Only the exact legacy line (trailing \r ignored); anything else on or
        # around it is kept. The current block also runs `unalias cr`.
        awk '{ l = $0; sub(/\r$/, "", l) } l != "alias cr='"'"'sleep 2 && claude -c'"'"'"' "$rc_file" > "$tmp_file"
        if cmp -s "$tmp_file" "$rc_file"; then
            rm -f "$tmp_file"
            info "Left unrelated alias cr= in $(basename "$rc_file") untouched"
        else
            cat "$tmp_file" > "$rc_file"; rm -f "$tmp_file"
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
