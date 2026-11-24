#!/bin/sh
# fakeauthor — fake AI co-author trailers for git. Parody; not affiliated with any vendor.

set -eu

IS_WINDOWS=0
case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
esac
CR_CH=$(printf '\r')

norm_slashes() {
    case "$1" in
        *\\*) printf '%s\n' "$1" | tr '\\' '/' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

DEFAULT_FAKEAUTHOR_DIR=$(norm_slashes "$HOME/.local/share/fakeauthor")
FAKEAUTHOR_DIR=$(norm_slashes "${FAKEAUTHOR_DIR:-$DEFAULT_FAKEAUTHOR_DIR}")
STUB_HOOKS="applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit prepare-commit-msg post-commit pre-rebase post-checkout post-merge pre-push post-rewrite sendemail-validate"
ALL_PERSONAS="claude copilot codex cursor aider devin"

usage() {
    cat >&2 <<'EOF'
usage: sh install.sh [--local|--global] [--force] [persona[,persona...]|all|on|off|status|uninstall|show <persona>]
EOF
}

canon_path() {
    p=${1:-}
    [ -z "$p" ] && return 0
    p=$(norm_slashes "$p")
    orig_p=$p
    suffix=""
    while [ ! -d "$p" ] && [ "$p" != "/" ] && [ "$p" != "." ]; do
        case "$p" in [A-Za-z]:|[A-Za-z]:/) break ;; esac
        parent=$(dirname "$p")
        case "$parent" in [A-Za-z]:) parent="$parent/" ;; esac
        [ "$parent" = "$p" ] && break
        b=$(basename "$p")
        suffix="/$b$suffix"
        p=$parent
    done
    if [ -d "$p" ]; then
        cp=$(cd "$p" 2>/dev/null && pwd -P) || cp=$p
        printf '%s%s\n' "${cp%/}" "$suffix"
    else
        printf '%s\n' "${orig_p%/}"
    fi
}

same_path() {
    sp_a=$(canon_path "$1")
    sp_b=$(canon_path "$2")
    [ "$sp_a" = "$sp_b" ] && return 0
    if [ "$IS_WINDOWS" -eq 1 ]; then
        sp_a=$(printf '%s' "$sp_a" | tr '[:upper:]' '[:lower:]')
        sp_b=$(printf '%s' "$sp_b" | tr '[:upper:]' '[:lower:]')
        [ "$sp_a" = "$sp_b" ] && return 0
    fi
    return 1
}

to_git_path() {
    if [ "$IS_WINDOWS" -eq 1 ] && command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1" 2>/dev/null || printf '%s\n' "$1"
    else
        printf '%s\n' "$1"
    fi
}

trim_ws() {
    t=$1
    while [ "${t# }" != "$t" ] || [ "${t#	}" != "$t" ] || [ "${t#"$CR_CH"}" != "$t" ]; do t=${t#?}; done
    while [ "${t% }" != "$t" ] || [ "${t%	}" != "$t" ] || [ "${t%"$CR_CH"}" != "$t" ]; do t=${t%?}; done
    printf '%s' "$t"
}

check_no_cr() {
    [ "$(LC_ALL=C tr -cd '\r' < "$1" | wc -c)" -eq 0 ] && return 0
    echo "fakeauthor: error: CR bytes found in $1; LF-only output required" >&2
    exit 1
}

get_identity() {
    case "$1" in
        claude)
            ID_KEY="Co-Authored-By"
            ID_NAME="Claude"
            ID_EMAIL="noreply@anthropic.com"
            ;;
        copilot)
            ID_KEY="Co-authored-by"
            ID_NAME="Copilot"
            ID_EMAIL="223556219+Copilot@users.noreply.github.com"
            ;;
        codex)
            ID_KEY="Co-authored-by"
            ID_NAME="Codex"
            ID_EMAIL="noreply@openai.com"
            ;;
        cursor)
            ID_KEY="Co-authored-by"
            ID_NAME="Cursor"
            ID_EMAIL="cursoragent@cursor.com"
            ;;
        aider)
            ID_KEY="Co-authored-by"
            ID_NAME="aider (sonnet)"
            ID_EMAIL="aider@aider.chat"
            ;;
        devin)
            ID_KEY=""
            ID_NAME="Devin"
            ID_EMAIL="158243242+devin-ai-integration[bot]@users.noreply.github.com"
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_personas() {
    raw=$1
    [ -z "$raw" ] && return 1
    sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0 sel_devin=0
    plist="$raw,"
    while [ -n "$plist" ]; do
        item=${plist%%,*}
        plist=${plist#*,}
        item=$(trim_ws "$item")
        [ -n "$item" ] || return 1
        case "$item" in
            all)
                sel_claude=1 sel_copilot=1 sel_codex=1 sel_cursor=1 sel_aider=1
                ;;
            claude) sel_claude=1 ;;
            copilot) sel_copilot=1 ;;
            codex) sel_codex=1 ;;
            cursor) sel_cursor=1 ;;
            aider) sel_aider=1 ;;
            devin) sel_devin=1 ;;
            *)
                BAD_PERSONA=$item
                return 1
                ;;
        esac
    done
    NORM_CSV=""
    NORM_LIST=""
    for p in $ALL_PERSONAS; do
        eval "flag=\$sel_$p"
        if [ "$flag" -eq 1 ]; then
            NORM_CSV="${NORM_CSV:+$NORM_CSV,}$p"
            NORM_LIST="${NORM_LIST:+$NORM_LIST }$p"
        fi
    done
    [ -n "$NORM_CSV" ]
}

cmd_show() {
    persona=${1:-}
    if [ -z "$persona" ]; then
        echo "fakeauthor: show requires a persona" >&2
        exit 1
    fi
    if ! get_identity "$persona"; then
        echo "fakeauthor: unknown persona: $persona" >&2
        exit 1
    fi
    if [ -z "$ID_KEY" ]; then
        echo "fakeauthor: $persona is author-mode only (git $persona commit), no trailer" >&2
        exit 1
    fi
    echo "$ID_KEY: $ID_NAME <$ID_EMAIL>"
}

sq_escape() {
    s=$1
    out=""
    while [ -n "$s" ]; do
        case "$s" in
            *"'"*)
                prefix=${s%%\'*}
                out="$out$prefix'\\''"
                s=${s#*\'}
                ;;
            *)
                out="$out$s"
                s=""
                ;;
        esac
    done
    printf '%s' "$out"
}

build_alias_val() {
    n_esc=$(sq_escape "$1")
    e_esc=$(sq_escape "$2")
    printf "!f(){ [ -n \"\$GIT_PREFIX\" ] && cd \"\$GIT_PREFIX\"; GIT_AUTHOR_NAME='%s' GIT_AUTHOR_EMAIL='%s' NO_FAKEAUTHOR=1 git \"\$@\"; };f" "$n_esc" "$e_esc"
}

TUI_ESC=$(printf '\033')
TUI_CR=$(printf '\r')
TUI_NL=$(printf '\nx'); TUI_NL=${TUI_NL%x}
TUI_CTRL_C=$(printf '\003')
TUI_OLD_STTY=""
TUI_CURSOR_HIDDEN=0
TUI_NOWRAP=0

has_tty() {
    [ -n "${FAKEAUTHOR_TTY:-}" ] && [ -r "$FAKEAUTHOR_TTY" ] && return 0
    [ -t 1 ] && { [ -r /dev/tty ] || { [ "$IS_WINDOWS" -eq 1 ] && [ -t 0 ]; }; }
}

can_raw_tui() {
    [ -t 3 ] && [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] || return 1
    if [ "$IS_WINDOWS" -eq 1 ]; then
        case "$(tty <&3 2>/dev/null || true)" in
            /dev/cons*) return 1 ;;
        esac
    fi
    command -v stty >/dev/null 2>&1 && command -v dd >/dev/null 2>&1 || return 1
    stty -g <&3 >/dev/null 2>&1
}

find_win_ps() {
    if command -v pwsh.exe >/dev/null 2>&1; then
        command -v pwsh.exe
    elif command -v powershell.exe >/dev/null 2>&1; then
        command -v powershell.exe
    elif [ -x "/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
        printf '%s\n' "/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    else
        return 1
    fi
}

can_win_ps_tui() {
    [ "$IS_WINDOWS" -eq 1 ] && [ -z "${FAKEAUTHOR_TTY:-}" ] && [ -t 0 ] && [ -t 1 ] || return 1
    case "$(tty <&3 2>/dev/null || true)" in
        /dev/cons*) ;;
        *)
            [ -z "${MSYSTEM:-}" ] || [ "${TERM:-dumb}" = "dumb" ] || return 1
            ;;
    esac
    command -v cygpath >/dev/null 2>&1 || return 1
    find_win_ps >/dev/null 2>&1
}

win_ps_run() {
    ps_bin=$(find_win_ps) || return 2
    ps_out=$(mktemp 2>/dev/null) || return 2
    ps_out_win=$(cygpath -w "$ps_out" 2>/dev/null) || { rm -f "$ps_out"; return 2; }
    ps_script=$(mktemp 2>/dev/null) || { rm -f "$ps_out"; return 2; }
    ps_script_win=$(cygpath -w "$ps_script" 2>/dev/null) || { rm -f "$ps_out" "$ps_script"; return 2; }
    cat > "$ps_script" <<'PS_EOF'
$ErrorActionPreference = 'Stop'
if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { exit 2 }
$mode = $env:FA_PS_MODE
$outPath = $env:FA_PS_OUT
$noColor = -not [string]::IsNullOrEmpty($env:NO_COLOR)
$oldVis = $true
$oldCtrlC = $false
try { $oldVis = [Console]::CursorVisible } catch {}
try { $oldCtrlC = [Console]::TreatControlCAsInput } catch {}

function Write-Seg($txt, $fg) {
  if ($noColor -or $null -eq $fg) {
    [Console]::Write($txt)
  } else {
    $prev = [Console]::ForegroundColor
    [Console]::ForegroundColor = $fg
    [Console]::Write($txt)
    [Console]::ForegroundColor = $prev
  }
}

function Pad-End($used, $bw) {
  $rem = $bw - $used
  if ($rem -gt 0) { [Console]::Write((' ' * $rem)) }
  [Console]::Write("`n")
}

try {
  try { [Console]::CursorVisible = $false } catch {}
  try { [Console]::TreatControlCAsInput = $true } catch {}
  if ([Console]::CursorLeft -gt 0) { [Console]::Write("`n") }

  if ($mode -eq 'scope') {
    $title = $env:FA_PS_TITLE
    $opts = @($env:FA_PS_OPT1, $env:FA_PS_OPT2)
    $cur = 0
    $n = 4
    for ($i = 0; $i -lt $n; $i++) { [Console]::Write("`n") }
    $baseTop = [Math]::Max(0, [Console]::CursorTop - $n)
    while ($true) {
      $bw = 80
      try { $bw = [Math]::Max(20, [Console]::BufferWidth - 1) } catch {}
      [Console]::SetCursorPosition(0, $baseTop)
      $t = if ($title.Length -gt $bw) { $title.Substring(0, $bw) } else { $title }
      Write-Seg $t $null
      Pad-End $t.Length $bw
      for ($i = 0; $i -lt 2; $i++) {
        $num = [string]($i + 1)
        $lbl = $opts[$i]
        if ($i -eq $cur) {
          $pre = '  > '
          $rest = "$num) $lbl"
          $maxRest = [Math]::Max(0, $bw - $pre.Length)
          if ($rest.Length -gt $maxRest) { $rest = $rest.Substring(0, $maxRest) }
          Write-Seg '  ' $null
          Write-Seg '>' ([ConsoleColor]::Cyan)
          Write-Seg ' ' $null
          Write-Seg $rest $null
          Pad-End ($pre.Length + $rest.Length) $bw
        } else {
          $line = "    $num) $lbl"
          if ($line.Length -gt $bw) { $line = $line.Substring(0, $bw) }
          Write-Seg $line $null
          Pad-End $line.Length $bw
        }
      }
      $hint = '  Move: arrows/j/k | Select: Enter | Cancel: q/Esc'
      if ($hint.Length -gt $bw) { $hint = $hint.Substring(0, $bw) }
      Write-Seg $hint ([ConsoleColor]::DarkGray)
      Pad-End $hint.Length $bw

      $k = [Console]::ReadKey($true)
      $ch = [string]$k.KeyChar
      $isCtrlC = ([int]$k.KeyChar -eq 3) -or (($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq [ConsoleKey]::C))
      if ($isCtrlC -or $k.Key -eq [ConsoleKey]::Escape -or $ch -ieq 'q') {
        [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
        exit 1
      } elseif ($k.Key -eq [ConsoleKey]::UpArrow -or $k.Key -eq [ConsoleKey]::DownArrow -or $ch -ieq 'j' -or $ch -ieq 'k') {
        $cur = 1 - $cur
      } elseif ($ch -eq '1') {
        $cur = 0
      } elseif ($ch -eq '2') {
        $cur = 1
      } elseif ($k.Key -eq [ConsoleKey]::Enter -or $k.Key -eq [ConsoleKey]::Spacebar -or $ch -eq ' ') {
        [IO.File]::WriteAllText($outPath, [string]($cur + 1), (New-Object System.Text.UTF8Encoding($false)))
        [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
        exit 0
      }
    }
  } else {
    $names = @('claude','copilot','codex','cursor','aider','devin')
    $labels = @(
      'Claude   <noreply@anthropic.com>',
      'Copilot  <223556219+Copilot@users.noreply.github.com>',
      'Codex    <noreply@openai.com>',
      'Cursor   <cursoragent@cursor.com>',
      'aider    <aider@aider.chat>',
      'Devin    (author mode: git devin commit)'
    )
    $sel = [bool[]]@($false,$false,$false,$false,$false,$false)
    foreach ($item in ($env:FA_PS_INIT -split ',')) {
      $t = $item.Trim()
      if ($t -eq 'all') {
        for ($i = 0; $i -lt 5; $i++) { $sel[$i] = $true }
      } else {
        $idx = [Array]::IndexOf($names, $t)
        if ($idx -ge 0) { $sel[$idx] = $true }
      }
    }
    $cur = 0
    $errMsg = ''
    $n = 8
    for ($i = 0; $i -lt $n; $i++) { [Console]::Write("`n") }
    $baseTop = [Math]::Max(0, [Console]::CursorTop - $n)
    while ($true) {
      $bw = 80
      try { $bw = [Math]::Max(20, [Console]::BufferWidth - 1) } catch {}
      [Console]::SetCursorPosition(0, $baseTop)
      $hdr = 'Pick co-author(s) (arrows/j/k move, Space toggle, a all, Enter):'
      if ($hdr.Length -gt $bw) { $hdr = $hdr.Substring(0, $bw) }
      Write-Seg $hdr $null
      Pad-End $hdr.Length $bw
      for ($i = 0; $i -lt 6; $i++) {
        $num = [string]($i + 1)
        $box = if ($sel[$i]) { '[x]' } else { '[ ]' }
        $lbl = $labels[$i]
        $prefixLen = 8
        $rest = "$num) $lbl"
        $maxRest = [Math]::Max(0, $bw - $prefixLen)
        if ($rest.Length -gt $maxRest) { $rest = $rest.Substring(0, $maxRest) }
        Write-Seg '  ' $null
        if ($i -eq $cur) { Write-Seg '>' ([ConsoleColor]::Cyan) } else { Write-Seg ' ' $null }
        Write-Seg ' ' $null
        if ($sel[$i]) { Write-Seg $box ([ConsoleColor]::Green) } else { Write-Seg $box $null }
        Write-Seg ' ' $null
        Write-Seg $rest $null
        Pad-End ($prefixLen + $rest.Length) $bw
      }
      if (-not [string]::IsNullOrEmpty($errMsg)) {
        $foot = "  $errMsg"
        if ($foot.Length -gt $bw) { $foot = $foot.Substring(0, $bw) }
        Write-Seg $foot ([ConsoleColor]::Yellow)
        Pad-End $foot.Length $bw
      } else {
        $picked = @()
        for ($i = 0; $i -lt 6; $i++) { if ($sel[$i]) { $picked += $names[$i] } }
        $csv = if ($picked.Count -gt 0) { $picked -join ',' } else { 'none' }
        $foot = "  Selected: $csv (q/Esc cancel)"
        if ($foot.Length -gt $bw) { $foot = $foot.Substring(0, $bw) }
        Write-Seg $foot ([ConsoleColor]::DarkGray)
        Pad-End $foot.Length $bw
      }

      $k = [Console]::ReadKey($true)
      $ch = [string]$k.KeyChar
      $isCtrlC = ([int]$k.KeyChar -eq 3) -or (($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq [ConsoleKey]::C))
      if ($isCtrlC -or $k.Key -eq [ConsoleKey]::Escape -or $ch -ieq 'q') {
        [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
        exit 1
      } elseif ($k.Key -eq [ConsoleKey]::UpArrow -or $ch -ieq 'k') {
        $cur = ($cur + 5) % 6
      } elseif ($k.Key -eq [ConsoleKey]::DownArrow -or $ch -ieq 'j') {
        $cur = ($cur + 1) % 6
      } elseif ($k.Key -eq [ConsoleKey]::Spacebar -or $ch -eq ' ') {
        $sel[$cur] = -not $sel[$cur]
        $errMsg = ''
      } elseif ($ch -ge '1' -and $ch -le '6') {
        $cur = [int]::Parse($ch) - 1
        $sel[$cur] = -not $sel[$cur]
        $errMsg = ''
      } elseif ($ch -ieq 'a') {
        $allOn = $sel[0] -and $sel[1] -and $sel[2] -and $sel[3] -and $sel[4]
        for ($i = 0; $i -lt 5; $i++) { $sel[$i] = -not $allOn }
        $errMsg = ''
      } elseif ($ch -ieq 'n') {
        for ($i = 0; $i -lt 6; $i++) { $sel[$i] = $false }
        $errMsg = ''
      } elseif ($k.Key -eq [ConsoleKey]::Enter) {
        $picked = @()
        for ($i = 0; $i -lt 6; $i++) { if ($sel[$i]) { $picked += $names[$i] } }
        if ($picked.Count -gt 0) {
          [IO.File]::WriteAllText($outPath, ($picked -join ','), (New-Object System.Text.UTF8Encoding($false)))
          [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
          exit 0
        }
        $errMsg = 'Select at least one (Space to toggle, q to cancel)'
      }
    }
  }
} finally {
  try { [Console]::TreatControlCAsInput = $oldCtrlC } catch {}
  try { [Console]::CursorVisible = $oldVis } catch {}
}
PS_EOF
    ps_rc=0
    MSYS_NO_PATHCONV=1 FA_PS_OUT="$ps_out_win" FA_PS_SCRIPT="$ps_script_win" \
        "$ps_bin" -NoProfile -Command 'Invoke-Expression ([IO.File]::ReadAllText($env:FA_PS_SCRIPT))' || ps_rc=$?
    WIN_PS_VAL=""
    if [ "$ps_rc" -eq 0 ] && [ -f "$ps_out" ]; then
        WIN_PS_VAL=$(tr -d '\r\n' < "$ps_out")
    fi
    rm -f "$ps_out" "$ps_script"
    return "$ps_rc"
}

win_ps_pick_scope() {
    FA_PS_MODE="scope"
    FA_PS_TITLE=$1
    FA_PS_OPT1=$2
    FA_PS_OPT2=$3
    export FA_PS_MODE FA_PS_TITLE FA_PS_OPT1 FA_PS_OPT2
    wp_rc=0
    win_ps_run || wp_rc=$?
    unset FA_PS_MODE FA_PS_TITLE FA_PS_OPT1 FA_PS_OPT2
    if [ "$wp_rc" -eq 0 ]; then
        case "$WIN_PS_VAL" in
            1|2) PICKED_SCOPE=$WIN_PS_VAL; return 0 ;;
            *) return 2 ;;
        esac
    fi
    [ "$wp_rc" -eq 1 ] && return 1
    return 2
}

win_ps_pick_personas() {
    FA_PS_MODE="personas"
    FA_PS_INIT=$1
    export FA_PS_MODE FA_PS_INIT
    wp_rc=0
    win_ps_run || wp_rc=$?
    unset FA_PS_MODE FA_PS_INIT
    if [ "$wp_rc" -eq 0 ] && [ -n "$WIN_PS_VAL" ]; then
        sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0 sel_devin=0
        wp_list="$WIN_PS_VAL,"
        while [ -n "$wp_list" ]; do
            wp_item=${wp_list%%,*}
            wp_list=${wp_list#*,}
            case "$wp_item" in
                claude) sel_claude=1 ;;
                copilot) sel_copilot=1 ;;
                codex) sel_codex=1 ;;
                cursor) sel_cursor=1 ;;
                aider) sel_aider=1 ;;
                devin) sel_devin=1 ;;
            esac
        done
        collect_picked
        [ -n "$PICKED_CSV" ] && return 0
        return 2
    fi
    [ "$wp_rc" -eq 1 ] && return 1
    return 2
}

tui_cleanup() {
    if [ -n "${TUI_OLD_STTY:-}" ]; then
        stty "$TUI_OLD_STTY" <&3 2>/dev/null || true
        TUI_OLD_STTY=""
    fi
    if [ "${TUI_NOWRAP:-0}" -eq 1 ]; then
        printf '\033[?7h'
        TUI_NOWRAP=0
    fi
    if [ "${TUI_CURSOR_HIDDEN:-0}" -eq 1 ]; then
        printf '\033[?25h'
        TUI_CURSOR_HIDDEN=0
    fi
    trap - INT TERM HUP EXIT 2>/dev/null || true
}

tui_enter() {
    TUI_OLD_STTY=$(stty -g <&3)
    trap 'tui_cleanup; printf "\n"; exit 130' INT TERM HUP
    trap 'tui_cleanup' EXIT
    stty -icanon -echo min 1 time 0 <&3
    printf '\033[?25l\033[?7l'
    TUI_CURSOR_HIDDEN=1
    TUI_NOWRAP=1
}

tui_read_key() {
    b=$(dd bs=1 count=1 <&3 2>/dev/null; printf x); b=${b%x}
    if [ -z "$b" ]; then
        TUI_KEY="EOF"
        return 0
    fi
    if [ "$b" = "$TUI_ESC" ]; then
        stty -icanon -echo min 0 time 1 <&3 2>/dev/null || true
        seq=$(dd bs=1 count=2 <&3 2>/dev/null; printf x); seq=${seq%x}
        stty -icanon -echo min 1 time 0 <&3 2>/dev/null || true
        case "$seq" in
            "[A"|"OA") TUI_KEY="UP" ;;
            "[B"|"OB") TUI_KEY="DOWN" ;;
            "") TUI_KEY="ESC" ;;
            *) TUI_KEY="OTHER" ;;
        esac
    elif [ "$b" = "$TUI_NL" ] || [ "$b" = "$TUI_CR" ]; then
        TUI_KEY="ENTER"
    elif [ "$b" = " " ]; then
        TUI_KEY="SPACE"
    elif [ "$b" = "$TUI_CTRL_C" ]; then
        TUI_KEY="CTRL_C"
    else
        TUI_KEY="$b"
    fi
}

mark_for() {
    if [ "$1" -eq 1 ]; then printf 'x'; else printf ' '; fi
}

tui_scope_line() {
    sc_idx=$1
    sc_cur=$2
    sc_label=$3
    if [ "$sc_idx" -eq "$sc_cur" ]; then
        if [ -z "${NO_COLOR:-}" ]; then
            printf '  \033[1;36m>\033[0m %s) \033[1m%s\033[0m\033[K\n' "$sc_idx" "$sc_label"
        else
            printf '  > %s) %s\033[K\n' "$sc_idx" "$sc_label"
        fi
    else
        printf '    %s) %s\033[K\n' "$sc_idx" "$sc_label"
    fi
}

pick_scope() {
    ps_title=$1
    ps_opt1=$2
    ps_opt2=$3

    if can_win_ps_tui; then
        wp_sc=0
        win_ps_pick_scope "$ps_title" "$ps_opt1" "$ps_opt2" || wp_sc=$?
        [ "$wp_sc" -eq 0 ] && return 0
        [ "$wp_sc" -eq 1 ] && return 1
    fi

    if ! can_raw_tui; then
        printf '%s\n  1) %s\n  2) %s\nChoice [1]: ' "$ps_title" "$ps_opt1" "$ps_opt2"
        IFS= read -r sc <&3 || sc=""
        sc=$(trim_ws "$sc")
        case "$sc" in
            ""|1) PICKED_SCOPE=1; return 0 ;;
            2) PICKED_SCOPE=2; return 0 ;;
            q|Q) return 1 ;;
            *) echo "Unknown choice: $sc" >&2; return 2 ;;
        esac
    fi

    tui_enter
    sc_cur=1
    drawn=0
    while :; do
        [ "$drawn" -gt 0 ] && printf '\033[%dA' "$drawn"
        printf '%s\033[K\n' "$ps_title"
        tui_scope_line 1 "$sc_cur" "$ps_opt1"
        tui_scope_line 2 "$sc_cur" "$ps_opt2"
        if [ -z "${NO_COLOR:-}" ]; then
            printf '  \033[2mMove: arrows/j/k | Select: Enter | Cancel: q/Esc\033[0m\033[K\n'
        else
            printf '  Move: arrows/j/k | Select: Enter | Cancel: q/Esc\033[K\n'
        fi
        drawn=4

        tui_read_key
        case "$TUI_KEY" in
            UP|k|K|DOWN|j|J)
                if [ "$sc_cur" -eq 1 ]; then sc_cur=2; else sc_cur=1; fi
                ;;
            1) sc_cur=1 ;;
            2) sc_cur=2 ;;
            ENTER|SPACE)
                PICKED_SCOPE=$sc_cur
                tui_cleanup
                return 0
                ;;
            q|Q|ESC|CTRL_C|EOF)
                tui_cleanup
                return 1
                ;;
        esac
    done
}

toggle_idx() {
    case "$1" in
        1) sel_claude=$((1 - sel_claude)) ;;
        2) sel_copilot=$((1 - sel_copilot)) ;;
        3) sel_codex=$((1 - sel_codex)) ;;
        4) sel_cursor=$((1 - sel_cursor)) ;;
        5) sel_aider=$((1 - sel_aider)) ;;
        6) sel_devin=$((1 - sel_devin)) ;;
    esac
}

collect_picked() {
    PICKED_CSV=""
    PICKED_LIST=""
    for p in $ALL_PERSONAS; do
        eval "flag=\$sel_$p"
        if [ "$flag" -eq 1 ]; then
            PICKED_CSV="${PICKED_CSV:+$PICKED_CSV,}$p"
            PICKED_LIST="${PICKED_LIST:+$PICKED_LIST }$p"
        fi
    done
}

tui_persona_line() {
    pl_idx=$1
    pl_cur=$2
    pl_sel=$3
    pl_text=$4
    if [ "$pl_sel" -eq 1 ]; then
        if [ -z "${NO_COLOR:-}" ]; then
            box="\033[32m[x]\033[0m"
        else
            box="[x]"
        fi
    else
        box="[ ]"
    fi
    if [ "$pl_idx" -eq "$pl_cur" ]; then
        if [ -z "${NO_COLOR:-}" ]; then
            printf '  \033[1;36m>\033[0m %b \033[1m%s) %s\033[0m\033[K\n' "$box" "$pl_idx" "$pl_text"
        else
            printf '  > %s %s) %s\033[K\n' "$box" "$pl_idx" "$pl_text"
        fi
    else
        printf '    %b %s) %s\033[K\n' "$box" "$pl_idx" "$pl_text"
    fi
}

pick_personas() {
    init_csv=${1:-claude}
    sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0 sel_devin=0
    plist="$init_csv,"
    while [ -n "$plist" ]; do
        item=${plist%%,*}
        plist=${plist#*,}
        item=$(trim_ws "$item")
        case "$item" in
            all) sel_claude=1 sel_copilot=1 sel_codex=1 sel_cursor=1 sel_aider=1 ;;
            claude) sel_claude=1 ;;
            copilot) sel_copilot=1 ;;
            codex) sel_codex=1 ;;
            cursor) sel_cursor=1 ;;
            aider) sel_aider=1 ;;
            devin) sel_devin=1 ;;
        esac
    done

    if can_win_ps_tui; then
        wp_pp=0
        win_ps_pick_personas "$init_csv" || wp_pp=$?
        [ "$wp_pp" -eq 0 ] && return 0
        [ "$wp_pp" -eq 1 ] && return 1
    fi

    if can_raw_tui; then
        tui_enter
        cur=1
        err_msg=""
        drawn=0
        while :; do
            [ "$drawn" -gt 0 ] && printf '\033[%dA' "$drawn"
            printf 'Pick co-author(s) (arrows/j/k move, Space toggle, a all, Enter):\033[K\n'
            tui_persona_line 1 "$cur" "$sel_claude"  "Claude   <noreply@anthropic.com>"
            tui_persona_line 2 "$cur" "$sel_copilot" "Copilot  <223556219+Copilot@users.noreply.github.com>"
            tui_persona_line 3 "$cur" "$sel_codex"   "Codex    <noreply@openai.com>"
            tui_persona_line 4 "$cur" "$sel_cursor"  "Cursor   <cursoragent@cursor.com>"
            tui_persona_line 5 "$cur" "$sel_aider"   "aider    <aider@aider.chat>"
            tui_persona_line 6 "$cur" "$sel_devin"   "Devin    (author mode: git devin commit)"
            if [ -n "$err_msg" ]; then
                if [ -z "${NO_COLOR:-}" ]; then
                    printf '  \033[33m%s\033[0m\033[K\n' "$err_msg"
                else
                    printf '  %s\033[K\n' "$err_msg"
                fi
            else
                collect_picked
                if [ -z "${NO_COLOR:-}" ]; then
                    printf '  \033[2mSelected: %s (q/Esc cancel)\033[0m\033[K\n' "${PICKED_CSV:-none}"
                else
                    printf '  Selected: %s (q/Esc cancel)\033[K\n' "${PICKED_CSV:-none}"
                fi
            fi
            drawn=8

            tui_read_key
            case "$TUI_KEY" in
                UP|k|K)
                    cur=$((cur - 1))
                    [ "$cur" -lt 1 ] && cur=6
                    ;;
                DOWN|j|J)
                    cur=$((cur + 1))
                    [ "$cur" -gt 6 ] && cur=1
                    ;;
                SPACE)
                    toggle_idx "$cur"
                    err_msg=""
                    ;;
                1|2|3|4|5|6)
                    cur=$TUI_KEY
                    toggle_idx "$cur"
                    err_msg=""
                    ;;
                a|A)
                    if [ "$sel_claude" -eq 1 ] && [ "$sel_copilot" -eq 1 ] && [ "$sel_codex" -eq 1 ] && [ "$sel_cursor" -eq 1 ] && [ "$sel_aider" -eq 1 ]; then
                        sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0
                    else
                        sel_claude=1 sel_copilot=1 sel_codex=1 sel_cursor=1 sel_aider=1
                    fi
                    err_msg=""
                    ;;
                n|N)
                    sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0 sel_devin=0
                    err_msg=""
                    ;;
                ENTER)
                    collect_picked
                    if [ -n "$PICKED_CSV" ]; then
                        tui_cleanup
                        return 0
                    fi
                    err_msg="Select at least one (Space to toggle, q to cancel)"
                    ;;
                q|Q|ESC|CTRL_C)
                    tui_cleanup
                    return 1
                    ;;
                EOF)
                    collect_picked
                    tui_cleanup
                    [ -n "$PICKED_CSV" ] && return 0
                    return 2
                    ;;
            esac
        done
    fi

    while :; do
        printf '\nPick co-author(s) (numbers to toggle, a=all, n=none, Enter=save, q=cancel):\n'
        printf '  [%s] 1) Claude    Co-Authored-By: Claude <noreply@anthropic.com>\n' "$(mark_for "$sel_claude")"
        printf '  [%s] 2) Copilot   Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>\n' "$(mark_for "$sel_copilot")"
        printf '  [%s] 3) Codex     Co-authored-by: Codex <noreply@openai.com>\n' "$(mark_for "$sel_codex")"
        printf '  [%s] 4) Cursor    Co-authored-by: Cursor <cursoragent@cursor.com>\n' "$(mark_for "$sel_cursor")"
        printf '  [%s] 5) aider     Co-authored-by: aider (sonnet) <aider@aider.chat>\n' "$(mark_for "$sel_aider")"
        printf '  [%s] 6) Devin     (author mode only: git devin commit)\n' "$(mark_for "$sel_devin")"
        printf 'Choice [Enter=save]: '

        if ! IFS= read -r line <&3; then
            collect_picked
            [ -n "$PICKED_CSV" ] && return 0
            return 2
        fi

        line=$(trim_ws "$line")
        case "$line" in
            "")
                collect_picked
                if [ -n "$PICKED_CSV" ]; then
                    return 0
                fi
                echo "Select at least one persona (or q to cancel)."
                ;;
            q|Q)
                return 1
                ;;
            a|A|all)
                sel_claude=1 sel_copilot=1 sel_codex=1 sel_cursor=1 sel_aider=1
                ;;
            n|N|none)
                sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0 sel_devin=0
                ;;
            *)
                tokens=""
                tlist="$line,"
                while [ -n "$tlist" ]; do
                    seg=${tlist%%,*}
                    tlist=${tlist#*,}
                    tokens="${tokens:+$tokens }$seg"
                done
                bad_tok=""
                set -f
                for tok in $tokens; do
                    case "$tok" in
                        1|2|3|4|5|6) toggle_idx "$tok" ;;
                        *) bad_tok=$tok ;;
                    esac
                done
                set +f
                if [ -n "$bad_tok" ]; then
                    echo "Unknown option: $bad_tok"
                fi
                ;;
        esac
    done
}

print_preview() {
    csv=$1
    has_trail=0
    plist="$csv,"
    while [ -n "$plist" ]; do
        item=${plist%%,*}
        plist=${plist#*,}
        [ -z "$item" ] && continue
        get_identity "$item" || continue
        if [ -n "$ID_KEY" ]; then
            if [ "$has_trail" -eq 0 ]; then
                echo "Next commit will include:"
                has_trail=1
            fi
            echo "  $ID_KEY: $ID_NAME <$ID_EMAIL>"
        else
            echo "Author mode alias ready: git $item commit -m \"...\""
        fi
    done
}

emit_hook() {
    cat <<'EOF'
#!/bin/sh
# fakeauthor hook v1

chain() {
    [ "${_FAKEAUTHOR_CHAINED:-0}" = "1" ] && exit 0
    common=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
    hook_name=${0##*/}
    hook_name=${hook_name##*\\}
    h="$common/hooks/$hook_name"
    [ -x "$h" ] || exit 0
    self_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || self_dir=""
    hook_dir=$(cd "$(dirname "$h")" 2>/dev/null && pwd -P) || hook_dir=""
    [ -n "$self_dir" ] && [ "$self_dir" = "$hook_dir" ] && exit 0
    _FAKEAUTHOR_CHAINED=1 exec "$h" "$@"
}

[ -n "${NO_FAKEAUTHOR:-}" ] && [ "$NO_FAKEAUTHOR" != "0" ] && chain "$@"

cfg_out=$(git config --get-regexp '^fakeauthor\.' 2>/dev/null || true)
raw_off=""
rate=""
raw_persona=""
o_name=""
o_email=""
if [ -n "$cfg_out" ]; then
    cfg_nl='
'
    cfg_rest="${cfg_out}${cfg_nl}"
    while [ -n "$cfg_rest" ]; do
        cfg_line=${cfg_rest%%"$cfg_nl"*}
        cfg_rest=${cfg_rest#*"$cfg_nl"}
        [ -z "$cfg_line" ] && continue
        case "$cfg_line" in
            *" "*) cfg_k=${cfg_line%% *}; cfg_v=${cfg_line#* } ;;
            *)     cfg_k=$cfg_line; cfg_v="__BARE__" ;;
        esac
        if [ "$cfg_k" = "fakeauthor.off" ]; then
            raw_off=$cfg_v
        else
            [ "$cfg_v" = "__BARE__" ] && cfg_v=""
            case "$cfg_k" in
                fakeauthor.rate) rate=$cfg_v ;;
                fakeauthor.persona) raw_persona=$cfg_v ;;
                fakeauthor.name) o_name=$cfg_v ;;
                fakeauthor.email) o_email=$cfg_v ;;
            esac
        fi
    done
fi

case "$raw_off" in
    __BARE__|true|yes|on|1) chain "$@" ;;
    ""|false|no|off|0) ;;
    *)
        off=$(git config --bool fakeauthor.off 2>/dev/null || true)
        [ "$off" = "true" ] && chain "$@"
        ;;
esac

[ -z "$rate" ] && rate=1
case "$rate" in
    0|0.0|0.00) chain "$@" ;;
    1|1.0|1.00) ;;
    *)
        command -v awk >/dev/null 2>&1 || chain "$@"
        awk -v p="$$" -v r="$rate" 'BEGIN{
            if (r !~ /^([0-9]+(\.[0-9]*)?|\.[0-9]+)$/) exit 1
            rv = r + 0
            if (rv <= 0) exit 1
            if (rv >= 1) exit 0
            srand(); x = rand(); srand(int(x * 2147483647) + p)
            exit !(rand() < rv)
        }' || chain "$@"
        ;;
esac

[ -f "${1:-}" ] || chain "$@"

gitdir=$(git rev-parse --git-dir 2>/dev/null) || chain "$@"
if [ -f "$gitdir/MERGE_HEAD" ] || [ -f "$gitdir/SQUASH_MSG" ]; then
    chain "$@"
fi

if command -v sed >/dev/null 2>&1 && command -v tr >/dev/null 2>&1; then
    cleaned=$(tr -d '\r' < "$1" 2>/dev/null | sed '/^[^[:space:]]* -\{1,\} >8 -\{1,\}$/,$d' 2>/dev/null | git stripspace --strip-comments 2>/dev/null)
elif command -v sed >/dev/null 2>&1; then
    cleaned=$(sed '/^[^[:space:]]* -\{1,\} >8 -\{1,\}$/,$d' "$1" 2>/dev/null | git stripspace --strip-comments 2>/dev/null)
else
    cleaned=$(git stripspace --strip-comments < "$1" 2>/dev/null)
fi
[ -z "$cleaned" ] && chain "$@"

[ -z "$raw_persona" ] && raw_persona=claude

plist="$raw_persona,"
while [ -n "$plist" ]; do
    p=${plist%%,*}
    plist=${plist#*,}
    while [ "${p# }" != "$p" ] || [ "${p#	}" != "$p" ]; do p=${p#?}; done
    while [ "${p% }" != "$p" ] || [ "${p%	}" != "$p" ]; do p=${p%?}; done
    [ -z "$p" ] && continue

    if [ "$p" = "all" ]; then
        plist="claude,copilot,codex,cursor,aider,$plist"
        continue
    fi

    key=""
    name=""
    email=""
    case "$p" in
        claude)
            key="Co-Authored-By"
            name="Claude"
            email="noreply@anthropic.com"
            ;;
        copilot)
            key="Co-authored-by"
            name="Copilot"
            email="223556219+Copilot@users.noreply.github.com"
            ;;
        codex)
            key="Co-authored-by"
            name="Codex"
            email="noreply@openai.com"
            ;;
        cursor)
            key="Co-authored-by"
            name="Cursor"
            email="cursoragent@cursor.com"
            ;;
        aider)
            key="Co-authored-by"
            name="aider (sonnet)"
            email="aider@aider.chat"
            ;;
        devin)
            key=""
            name="Devin"
            email="158243242+devin-ai-integration[bot]@users.noreply.github.com"
            ;;
        *)
            ;;
    esac

    if [ -n "$key" ]; then
        [ -n "$o_name" ] && name="$o_name"
        [ -n "$o_email" ] && email="$o_email"
    else
        if [ -n "$o_name" ] && [ -n "$o_email" ]; then
            key="Co-authored-by"
            name="$o_name"
            email="$o_email"
        else
            continue
        fi
    fi

    git interpret-trailers --in-place --if-exists addIfDifferent --trailer "$key: $name <$email>" "$1" 2>/dev/null || true
done

chain "$@"
EOF
}

emit_chain_stub() {
    cat <<'EOF'
#!/bin/sh
# fakeauthor chain stub v1
[ "${_FAKEAUTHOR_CHAINED:-0}" = "1" ] && exit 0
common=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
hook_name=${0##*/}
hook_name=${hook_name##*\\}
h="$common/hooks/$hook_name"
[ -x "$h" ] || exit 0
self_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || self_dir=""
hook_dir=$(cd "$(dirname "$h")" 2>/dev/null && pwd -P) || hook_dir=""
[ -n "$self_dir" ] && [ "$self_dir" = "$hook_dir" ] && exit 0
_FAKEAUTHOR_CHAINED=1 exec "$h" "$@"
EOF
}

emit_ctl() {
    cat <<'EOF'
#!/bin/sh
# fakeauthor offline control CLI (interactive / on / off / status / uninstall / show)
set -eu

ALL_PERSONAS="claude copilot codex cursor aider devin"
IS_WINDOWS=0
case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
esac
CR_CH=$(printf '\r')

norm_slashes() {
    case "$1" in
        *\\*) printf '%s\n' "$1" | tr '\\' '/' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

script_dir=""
case "$0" in
    */*|*\\*)
        ctl_self=$(norm_slashes "$0")
        script_dir=$(cd "$(dirname "$ctl_self")" 2>/dev/null && pwd -P) || script_dir=""
        ;;
esac

if [ -z "${FAKEAUTHOR_DIR:-}" ]; then
    if [ -n "$script_dir" ] && [ -f "$script_dir/manifest" ]; then
        FAKEAUTHOR_DIR=$script_dir
    else
        FAKEAUTHOR_DIR="$HOME/.local/share/fakeauthor"
    fi
fi
FAKEAUTHOR_DIR=$(norm_slashes "$FAKEAUTHOR_DIR")

ctl_usage() {
    cat >&2 <<'USAGE'
usage: git fakeauthor [--local|--global] [on|off|status|uninstall|show <persona>|persona[,persona...]|all]
USAGE
}

canon_path() {
    p=${1:-}
    [ -z "$p" ] && return 0
    p=$(norm_slashes "$p")
    orig_p=$p
    suffix=""
    while [ ! -d "$p" ] && [ "$p" != "/" ] && [ "$p" != "." ]; do
        case "$p" in [A-Za-z]:|[A-Za-z]:/) break ;; esac
        parent=$(dirname "$p")
        case "$parent" in [A-Za-z]:) parent="$parent/" ;; esac
        [ "$parent" = "$p" ] && break
        b=$(basename "$p")
        suffix="/$b$suffix"
        p=$parent
    done
    if [ -d "$p" ]; then
        cp=$(cd "$p" 2>/dev/null && pwd -P) || cp=$p
        printf '%s%s\n' "${cp%/}" "$suffix"
    else
        printf '%s\n' "${orig_p%/}"
    fi
}

same_path() {
    sp_a=$(canon_path "$1")
    sp_b=$(canon_path "$2")
    [ "$sp_a" = "$sp_b" ] && return 0
    if [ "$IS_WINDOWS" -eq 1 ]; then
        sp_a=$(printf '%s' "$sp_a" | tr '[:upper:]' '[:lower:]')
        sp_b=$(printf '%s' "$sp_b" | tr '[:upper:]' '[:lower:]')
        [ "$sp_a" = "$sp_b" ] && return 0
    fi
    return 1
}

trim_ws() {
    t=$1
    while [ "${t# }" != "$t" ] || [ "${t#	}" != "$t" ] || [ "${t#"$CR_CH"}" != "$t" ]; do t=${t#?}; done
    while [ "${t% }" != "$t" ] || [ "${t%	}" != "$t" ] || [ "${t%"$CR_CH"}" != "$t" ]; do t=${t%?}; done
    printf '%s' "$t"
}

check_no_cr() {
    [ "$(LC_ALL=C tr -cd '\r' < "$1" | wc -c)" -eq 0 ] && return 0
    echo "fakeauthor: error: CR bytes found in $1; LF-only output required" >&2
    exit 1
}

get_identity() {
    case "$1" in
        claude)  ID_KEY="Co-Authored-By"; ID_NAME="Claude";         ID_EMAIL="noreply@anthropic.com" ;;
        copilot) ID_KEY="Co-authored-by"; ID_NAME="Copilot";        ID_EMAIL="223556219+Copilot@users.noreply.github.com" ;;
        codex)   ID_KEY="Co-authored-by"; ID_NAME="Codex";          ID_EMAIL="noreply@openai.com" ;;
        cursor)  ID_KEY="Co-authored-by"; ID_NAME="Cursor";         ID_EMAIL="cursoragent@cursor.com" ;;
        aider)   ID_KEY="Co-authored-by"; ID_NAME="aider (sonnet)"; ID_EMAIL="aider@aider.chat" ;;
        devin)   ID_KEY="";               ID_NAME="Devin";          ID_EMAIL="158243242+devin-ai-integration[bot]@users.noreply.github.com" ;;
        *) return 1 ;;
    esac
}

normalize_personas() {
    raw=$1
    [ -z "$raw" ] && return 1
    sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0 sel_devin=0
    plist="$raw,"
    while [ -n "$plist" ]; do
        item=${plist%%,*}
        plist=${plist#*,}
        item=$(trim_ws "$item")
        [ -n "$item" ] || return 1
        case "$item" in
            all) sel_claude=1 sel_copilot=1 sel_codex=1 sel_cursor=1 sel_aider=1 ;;
            claude) sel_claude=1 ;;
            copilot) sel_copilot=1 ;;
            codex) sel_codex=1 ;;
            cursor) sel_cursor=1 ;;
            aider) sel_aider=1 ;;
            devin) sel_devin=1 ;;
            *) BAD_PERSONA=$item; return 1 ;;
        esac
    done
    NORM_CSV=""
    NORM_LIST=""
    for p in $ALL_PERSONAS; do
        eval "flag=\$sel_$p"
        if [ "$flag" -eq 1 ]; then
            NORM_CSV="${NORM_CSV:+$NORM_CSV,}$p"
            NORM_LIST="${NORM_LIST:+$NORM_LIST }$p"
        fi
    done
    [ -n "$NORM_CSV" ]
}

sq_escape() {
    s=$1
    out=""
    while [ -n "$s" ]; do
        case "$s" in
            *"'"*)
                prefix=${s%%\'*}
                out="$out$prefix'\\''"
                s=${s#*\'}
                ;;
            *)
                out="$out$s"
                s=""
                ;;
        esac
    done
    printf '%s' "$out"
}

build_alias_val() {
    n_esc=$(sq_escape "$1")
    e_esc=$(sq_escape "$2")
    printf "!f(){ [ -n \"\$GIT_PREFIX\" ] && cd \"\$GIT_PREFIX\"; GIT_AUTHOR_NAME='%s' GIT_AUTHOR_EMAIL='%s' NO_FAKEAUTHOR=1 git \"\$@\"; };f" "$n_esc" "$e_esc"
}

TUI_ESC=$(printf '\033')
TUI_CR=$(printf '\r')
TUI_NL=$(printf '\nx'); TUI_NL=${TUI_NL%x}
TUI_CTRL_C=$(printf '\003')
TUI_OLD_STTY=""
TUI_CURSOR_HIDDEN=0
TUI_NOWRAP=0

has_tty() {
    [ -n "${FAKEAUTHOR_TTY:-}" ] && [ -r "$FAKEAUTHOR_TTY" ] && return 0
    [ -t 1 ] && { [ -r /dev/tty ] || { [ "$IS_WINDOWS" -eq 1 ] && [ -t 0 ]; }; }
}

can_raw_tui() {
    [ -t 3 ] && [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] || return 1
    if [ "$IS_WINDOWS" -eq 1 ]; then
        case "$(tty <&3 2>/dev/null || true)" in
            /dev/cons*) return 1 ;;
        esac
    fi
    command -v stty >/dev/null 2>&1 && command -v dd >/dev/null 2>&1 || return 1
    stty -g <&3 >/dev/null 2>&1
}

find_win_ps() {
    if command -v pwsh.exe >/dev/null 2>&1; then
        command -v pwsh.exe
    elif command -v powershell.exe >/dev/null 2>&1; then
        command -v powershell.exe
    elif [ -x "/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
        printf '%s\n' "/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    else
        return 1
    fi
}

can_win_ps_tui() {
    [ "$IS_WINDOWS" -eq 1 ] && [ -z "${FAKEAUTHOR_TTY:-}" ] && [ -t 0 ] && [ -t 1 ] || return 1
    case "$(tty <&3 2>/dev/null || true)" in
        /dev/cons*) ;;
        *)
            [ -z "${MSYSTEM:-}" ] || [ "${TERM:-dumb}" = "dumb" ] || return 1
            ;;
    esac
    command -v cygpath >/dev/null 2>&1 || return 1
    find_win_ps >/dev/null 2>&1
}

win_ps_run() {
    ps_bin=$(find_win_ps) || return 2
    ps_out=$(mktemp 2>/dev/null) || return 2
    ps_out_win=$(cygpath -w "$ps_out" 2>/dev/null) || { rm -f "$ps_out"; return 2; }
    ps_script=$(mktemp 2>/dev/null) || { rm -f "$ps_out"; return 2; }
    ps_script_win=$(cygpath -w "$ps_script" 2>/dev/null) || { rm -f "$ps_out" "$ps_script"; return 2; }
    cat > "$ps_script" <<'PS_EOF'
$ErrorActionPreference = 'Stop'
if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { exit 2 }
$mode = $env:FA_PS_MODE
$outPath = $env:FA_PS_OUT
$noColor = -not [string]::IsNullOrEmpty($env:NO_COLOR)
$oldVis = $true
$oldCtrlC = $false
try { $oldVis = [Console]::CursorVisible } catch {}
try { $oldCtrlC = [Console]::TreatControlCAsInput } catch {}

function Write-Seg($txt, $fg) {
  if ($noColor -or $null -eq $fg) {
    [Console]::Write($txt)
  } else {
    $prev = [Console]::ForegroundColor
    [Console]::ForegroundColor = $fg
    [Console]::Write($txt)
    [Console]::ForegroundColor = $prev
  }
}

function Pad-End($used, $bw) {
  $rem = $bw - $used
  if ($rem -gt 0) { [Console]::Write((' ' * $rem)) }
  [Console]::Write("`n")
}

try {
  try { [Console]::CursorVisible = $false } catch {}
  try { [Console]::TreatControlCAsInput = $true } catch {}
  if ([Console]::CursorLeft -gt 0) { [Console]::Write("`n") }

  if ($mode -eq 'scope') {
    $title = $env:FA_PS_TITLE
    $opts = @($env:FA_PS_OPT1, $env:FA_PS_OPT2)
    $cur = 0
    $n = 4
    for ($i = 0; $i -lt $n; $i++) { [Console]::Write("`n") }
    $baseTop = [Math]::Max(0, [Console]::CursorTop - $n)
    while ($true) {
      $bw = 80
      try { $bw = [Math]::Max(20, [Console]::BufferWidth - 1) } catch {}
      [Console]::SetCursorPosition(0, $baseTop)
      $t = if ($title.Length -gt $bw) { $title.Substring(0, $bw) } else { $title }
      Write-Seg $t $null
      Pad-End $t.Length $bw
      for ($i = 0; $i -lt 2; $i++) {
        $num = [string]($i + 1)
        $lbl = $opts[$i]
        if ($i -eq $cur) {
          $pre = '  > '
          $rest = "$num) $lbl"
          $maxRest = [Math]::Max(0, $bw - $pre.Length)
          if ($rest.Length -gt $maxRest) { $rest = $rest.Substring(0, $maxRest) }
          Write-Seg '  ' $null
          Write-Seg '>' ([ConsoleColor]::Cyan)
          Write-Seg ' ' $null
          Write-Seg $rest $null
          Pad-End ($pre.Length + $rest.Length) $bw
        } else {
          $line = "    $num) $lbl"
          if ($line.Length -gt $bw) { $line = $line.Substring(0, $bw) }
          Write-Seg $line $null
          Pad-End $line.Length $bw
        }
      }
      $hint = '  Move: arrows/j/k | Select: Enter | Cancel: q/Esc'
      if ($hint.Length -gt $bw) { $hint = $hint.Substring(0, $bw) }
      Write-Seg $hint ([ConsoleColor]::DarkGray)
      Pad-End $hint.Length $bw

      $k = [Console]::ReadKey($true)
      $ch = [string]$k.KeyChar
      $isCtrlC = ([int]$k.KeyChar -eq 3) -or (($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq [ConsoleKey]::C))
      if ($isCtrlC -or $k.Key -eq [ConsoleKey]::Escape -or $ch -ieq 'q') {
        [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
        exit 1
      } elseif ($k.Key -eq [ConsoleKey]::UpArrow -or $k.Key -eq [ConsoleKey]::DownArrow -or $ch -ieq 'j' -or $ch -ieq 'k') {
        $cur = 1 - $cur
      } elseif ($ch -eq '1') {
        $cur = 0
      } elseif ($ch -eq '2') {
        $cur = 1
      } elseif ($k.Key -eq [ConsoleKey]::Enter -or $k.Key -eq [ConsoleKey]::Spacebar -or $ch -eq ' ') {
        [IO.File]::WriteAllText($outPath, [string]($cur + 1), (New-Object System.Text.UTF8Encoding($false)))
        [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
        exit 0
      }
    }
  } else {
    $names = @('claude','copilot','codex','cursor','aider','devin')
    $labels = @(
      'Claude   <noreply@anthropic.com>',
      'Copilot  <223556219+Copilot@users.noreply.github.com>',
      'Codex    <noreply@openai.com>',
      'Cursor   <cursoragent@cursor.com>',
      'aider    <aider@aider.chat>',
      'Devin    (author mode: git devin commit)'
    )
    $sel = [bool[]]@($false,$false,$false,$false,$false,$false)
    foreach ($item in ($env:FA_PS_INIT -split ',')) {
      $t = $item.Trim()
      if ($t -eq 'all') {
        for ($i = 0; $i -lt 5; $i++) { $sel[$i] = $true }
      } else {
        $idx = [Array]::IndexOf($names, $t)
        if ($idx -ge 0) { $sel[$idx] = $true }
      }
    }
    $cur = 0
    $errMsg = ''
    $n = 8
    for ($i = 0; $i -lt $n; $i++) { [Console]::Write("`n") }
    $baseTop = [Math]::Max(0, [Console]::CursorTop - $n)
    while ($true) {
      $bw = 80
      try { $bw = [Math]::Max(20, [Console]::BufferWidth - 1) } catch {}
      [Console]::SetCursorPosition(0, $baseTop)
      $hdr = 'Pick co-author(s) (arrows/j/k move, Space toggle, a all, Enter):'
      if ($hdr.Length -gt $bw) { $hdr = $hdr.Substring(0, $bw) }
      Write-Seg $hdr $null
      Pad-End $hdr.Length $bw
      for ($i = 0; $i -lt 6; $i++) {
        $num = [string]($i + 1)
        $box = if ($sel[$i]) { '[x]' } else { '[ ]' }
        $lbl = $labels[$i]
        $prefixLen = 8
        $rest = "$num) $lbl"
        $maxRest = [Math]::Max(0, $bw - $prefixLen)
        if ($rest.Length -gt $maxRest) { $rest = $rest.Substring(0, $maxRest) }
        Write-Seg '  ' $null
        if ($i -eq $cur) { Write-Seg '>' ([ConsoleColor]::Cyan) } else { Write-Seg ' ' $null }
        Write-Seg ' ' $null
        if ($sel[$i]) { Write-Seg $box ([ConsoleColor]::Green) } else { Write-Seg $box $null }
        Write-Seg ' ' $null
        Write-Seg $rest $null
        Pad-End ($prefixLen + $rest.Length) $bw
      }
      if (-not [string]::IsNullOrEmpty($errMsg)) {
        $foot = "  $errMsg"
        if ($foot.Length -gt $bw) { $foot = $foot.Substring(0, $bw) }
        Write-Seg $foot ([ConsoleColor]::Yellow)
        Pad-End $foot.Length $bw
      } else {
        $picked = @()
        for ($i = 0; $i -lt 6; $i++) { if ($sel[$i]) { $picked += $names[$i] } }
        $csv = if ($picked.Count -gt 0) { $picked -join ',' } else { 'none' }
        $foot = "  Selected: $csv (q/Esc cancel)"
        if ($foot.Length -gt $bw) { $foot = $foot.Substring(0, $bw) }
        Write-Seg $foot ([ConsoleColor]::DarkGray)
        Pad-End $foot.Length $bw
      }

      $k = [Console]::ReadKey($true)
      $ch = [string]$k.KeyChar
      $isCtrlC = ([int]$k.KeyChar -eq 3) -or (($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq [ConsoleKey]::C))
      if ($isCtrlC -or $k.Key -eq [ConsoleKey]::Escape -or $ch -ieq 'q') {
        [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
        exit 1
      } elseif ($k.Key -eq [ConsoleKey]::UpArrow -or $ch -ieq 'k') {
        $cur = ($cur + 5) % 6
      } elseif ($k.Key -eq [ConsoleKey]::DownArrow -or $ch -ieq 'j') {
        $cur = ($cur + 1) % 6
      } elseif ($k.Key -eq [ConsoleKey]::Spacebar -or $ch -eq ' ') {
        $sel[$cur] = -not $sel[$cur]
        $errMsg = ''
      } elseif ($ch -ge '1' -and $ch -le '6') {
        $cur = [int]::Parse($ch) - 1
        $sel[$cur] = -not $sel[$cur]
        $errMsg = ''
      } elseif ($ch -ieq 'a') {
        $allOn = $sel[0] -and $sel[1] -and $sel[2] -and $sel[3] -and $sel[4]
        for ($i = 0; $i -lt 5; $i++) { $sel[$i] = -not $allOn }
        $errMsg = ''
      } elseif ($ch -ieq 'n') {
        for ($i = 0; $i -lt 6; $i++) { $sel[$i] = $false }
        $errMsg = ''
      } elseif ($k.Key -eq [ConsoleKey]::Enter) {
        $picked = @()
        for ($i = 0; $i -lt 6; $i++) { if ($sel[$i]) { $picked += $names[$i] } }
        if ($picked.Count -gt 0) {
          [IO.File]::WriteAllText($outPath, ($picked -join ','), (New-Object System.Text.UTF8Encoding($false)))
          [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 1, $baseTop + $n))
          exit 0
        }
        $errMsg = 'Select at least one (Space to toggle, q to cancel)'
      }
    }
  }
} finally {
  try { [Console]::TreatControlCAsInput = $oldCtrlC } catch {}
  try { [Console]::CursorVisible = $oldVis } catch {}
}
PS_EOF
    ps_rc=0
    MSYS_NO_PATHCONV=1 FA_PS_OUT="$ps_out_win" FA_PS_SCRIPT="$ps_script_win" \
        "$ps_bin" -NoProfile -Command 'Invoke-Expression ([IO.File]::ReadAllText($env:FA_PS_SCRIPT))' || ps_rc=$?
    WIN_PS_VAL=""
    if [ "$ps_rc" -eq 0 ] && [ -f "$ps_out" ]; then
        WIN_PS_VAL=$(tr -d '\r\n' < "$ps_out")
    fi
    rm -f "$ps_out" "$ps_script"
    return "$ps_rc"
}

win_ps_pick_scope() {
    FA_PS_MODE="scope"
    FA_PS_TITLE=$1
    FA_PS_OPT1=$2
    FA_PS_OPT2=$3
    export FA_PS_MODE FA_PS_TITLE FA_PS_OPT1 FA_PS_OPT2
    wp_rc=0
    win_ps_run || wp_rc=$?
    unset FA_PS_MODE FA_PS_TITLE FA_PS_OPT1 FA_PS_OPT2
    if [ "$wp_rc" -eq 0 ]; then
        case "$WIN_PS_VAL" in
            1|2) PICKED_SCOPE=$WIN_PS_VAL; return 0 ;;
            *) return 2 ;;
        esac
    fi
    [ "$wp_rc" -eq 1 ] && return 1
    return 2
}

win_ps_pick_personas() {
    FA_PS_MODE="personas"
    FA_PS_INIT=$1
    export FA_PS_MODE FA_PS_INIT
    wp_rc=0
    win_ps_run || wp_rc=$?
    unset FA_PS_MODE FA_PS_INIT
    if [ "$wp_rc" -eq 0 ] && [ -n "$WIN_PS_VAL" ]; then
        sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0 sel_devin=0
        wp_list="$WIN_PS_VAL,"
        while [ -n "$wp_list" ]; do
            wp_item=${wp_list%%,*}
            wp_list=${wp_list#*,}
            case "$wp_item" in
                claude) sel_claude=1 ;;
                copilot) sel_copilot=1 ;;
                codex) sel_codex=1 ;;
                cursor) sel_cursor=1 ;;
                aider) sel_aider=1 ;;
                devin) sel_devin=1 ;;
            esac
        done
        collect_picked
        [ -n "$PICKED_CSV" ] && return 0
        return 2
    fi
    [ "$wp_rc" -eq 1 ] && return 1
    return 2
}

tui_cleanup() {
    if [ -n "${TUI_OLD_STTY:-}" ]; then
        stty "$TUI_OLD_STTY" <&3 2>/dev/null || true
        TUI_OLD_STTY=""
    fi
    if [ "${TUI_NOWRAP:-0}" -eq 1 ]; then
        printf '\033[?7h'
        TUI_NOWRAP=0
    fi
    if [ "${TUI_CURSOR_HIDDEN:-0}" -eq 1 ]; then
        printf '\033[?25h'
        TUI_CURSOR_HIDDEN=0
    fi
    trap - INT TERM HUP EXIT 2>/dev/null || true
}

tui_enter() {
    TUI_OLD_STTY=$(stty -g <&3)
    trap 'tui_cleanup; printf "\n"; exit 130' INT TERM HUP
    trap 'tui_cleanup' EXIT
    stty -icanon -echo min 1 time 0 <&3
    printf '\033[?25l\033[?7l'
    TUI_CURSOR_HIDDEN=1
    TUI_NOWRAP=1
}

tui_read_key() {
    b=$(dd bs=1 count=1 <&3 2>/dev/null; printf x); b=${b%x}
    if [ -z "$b" ]; then
        TUI_KEY="EOF"
        return 0
    fi
    if [ "$b" = "$TUI_ESC" ]; then
        stty -icanon -echo min 0 time 1 <&3 2>/dev/null || true
        seq=$(dd bs=1 count=2 <&3 2>/dev/null; printf x); seq=${seq%x}
        stty -icanon -echo min 1 time 0 <&3 2>/dev/null || true
        case "$seq" in
            "[A"|"OA") TUI_KEY="UP" ;;
            "[B"|"OB") TUI_KEY="DOWN" ;;
            "") TUI_KEY="ESC" ;;
            *) TUI_KEY="OTHER" ;;
        esac
    elif [ "$b" = "$TUI_NL" ] || [ "$b" = "$TUI_CR" ]; then
        TUI_KEY="ENTER"
    elif [ "$b" = " " ]; then
        TUI_KEY="SPACE"
    elif [ "$b" = "$TUI_CTRL_C" ]; then
        TUI_KEY="CTRL_C"
    else
        TUI_KEY="$b"
    fi
}

mark_for() {
    if [ "$1" -eq 1 ]; then printf 'x'; else printf ' '; fi
}

tui_scope_line() {
    sc_idx=$1
    sc_cur=$2
    sc_label=$3
    if [ "$sc_idx" -eq "$sc_cur" ]; then
        if [ -z "${NO_COLOR:-}" ]; then
            printf '  \033[1;36m>\033[0m %s) \033[1m%s\033[0m\033[K\n' "$sc_idx" "$sc_label"
        else
            printf '  > %s) %s\033[K\n' "$sc_idx" "$sc_label"
        fi
    else
        printf '    %s) %s\033[K\n' "$sc_idx" "$sc_label"
    fi
}

pick_scope() {
    ps_title=$1
    ps_opt1=$2
    ps_opt2=$3

    if can_win_ps_tui; then
        wp_sc=0
        win_ps_pick_scope "$ps_title" "$ps_opt1" "$ps_opt2" || wp_sc=$?
        [ "$wp_sc" -eq 0 ] && return 0
        [ "$wp_sc" -eq 1 ] && return 1
    fi

    if ! can_raw_tui; then
        printf '%s\n  1) %s\n  2) %s\nChoice [1]: ' "$ps_title" "$ps_opt1" "$ps_opt2"
        IFS= read -r sc <&3 || sc=""
        sc=$(trim_ws "$sc")
        case "$sc" in
            ""|1) PICKED_SCOPE=1; return 0 ;;
            2) PICKED_SCOPE=2; return 0 ;;
            q|Q) return 1 ;;
            *) echo "Unknown choice: $sc" >&2; return 2 ;;
        esac
    fi

    tui_enter
    sc_cur=1
    drawn=0
    while :; do
        [ "$drawn" -gt 0 ] && printf '\033[%dA' "$drawn"
        printf '%s\033[K\n' "$ps_title"
        tui_scope_line 1 "$sc_cur" "$ps_opt1"
        tui_scope_line 2 "$sc_cur" "$ps_opt2"
        if [ -z "${NO_COLOR:-}" ]; then
            printf '  \033[2mMove: arrows/j/k | Select: Enter | Cancel: q/Esc\033[0m\033[K\n'
        else
            printf '  Move: arrows/j/k | Select: Enter | Cancel: q/Esc\033[K\n'
        fi
        drawn=4

        tui_read_key
        case "$TUI_KEY" in
            UP|k|K|DOWN|j|J)
                if [ "$sc_cur" -eq 1 ]; then sc_cur=2; else sc_cur=1; fi
                ;;
            1) sc_cur=1 ;;
            2) sc_cur=2 ;;
            ENTER|SPACE)
                PICKED_SCOPE=$sc_cur
                tui_cleanup
                return 0
                ;;
            q|Q|ESC|CTRL_C|EOF)
                tui_cleanup
                return 1
                ;;
        esac
    done
}

toggle_idx() {
    case "$1" in
        1) sel_claude=$((1 - sel_claude)) ;;
        2) sel_copilot=$((1 - sel_copilot)) ;;
        3) sel_codex=$((1 - sel_codex)) ;;
        4) sel_cursor=$((1 - sel_cursor)) ;;
        5) sel_aider=$((1 - sel_aider)) ;;
        6) sel_devin=$((1 - sel_devin)) ;;
    esac
}

collect_picked() {
    PICKED_CSV=""
    PICKED_LIST=""
    for p in $ALL_PERSONAS; do
        eval "flag=\$sel_$p"
        if [ "$flag" -eq 1 ]; then
            PICKED_CSV="${PICKED_CSV:+$PICKED_CSV,}$p"
            PICKED_LIST="${PICKED_LIST:+$PICKED_LIST }$p"
        fi
    done
}

tui_persona_line() {
    pl_idx=$1
    pl_cur=$2
    pl_sel=$3
    pl_text=$4
    if [ "$pl_sel" -eq 1 ]; then
        if [ -z "${NO_COLOR:-}" ]; then
            box="\033[32m[x]\033[0m"
        else
            box="[x]"
        fi
    else
        box="[ ]"
    fi
    if [ "$pl_idx" -eq "$pl_cur" ]; then
        if [ -z "${NO_COLOR:-}" ]; then
            printf '  \033[1;36m>\033[0m %b \033[1m%s) %s\033[0m\033[K\n' "$box" "$pl_idx" "$pl_text"
        else
            printf '  > %s %s) %s\033[K\n' "$box" "$pl_idx" "$pl_text"
        fi
    else
        printf '    %b %s) %s\033[K\n' "$box" "$pl_idx" "$pl_text"
    fi
}

pick_personas() {
    init_csv=${1:-claude}
    sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0 sel_devin=0
    plist="$init_csv,"
    while [ -n "$plist" ]; do
        item=${plist%%,*}
        plist=${plist#*,}
        item=$(trim_ws "$item")
        case "$item" in
            all) sel_claude=1 sel_copilot=1 sel_codex=1 sel_cursor=1 sel_aider=1 ;;
            claude) sel_claude=1 ;;
            copilot) sel_copilot=1 ;;
            codex) sel_codex=1 ;;
            cursor) sel_cursor=1 ;;
            aider) sel_aider=1 ;;
            devin) sel_devin=1 ;;
        esac
    done

    if can_win_ps_tui; then
        wp_pp=0
        win_ps_pick_personas "$init_csv" || wp_pp=$?
        [ "$wp_pp" -eq 0 ] && return 0
        [ "$wp_pp" -eq 1 ] && return 1
    fi

    if can_raw_tui; then
        tui_enter
        cur=1
        err_msg=""
        drawn=0
        while :; do
            [ "$drawn" -gt 0 ] && printf '\033[%dA' "$drawn"
            printf 'Pick co-author(s) (arrows/j/k move, Space toggle, a all, Enter):\033[K\n'
            tui_persona_line 1 "$cur" "$sel_claude"  "Claude   <noreply@anthropic.com>"
            tui_persona_line 2 "$cur" "$sel_copilot" "Copilot  <223556219+Copilot@users.noreply.github.com>"
            tui_persona_line 3 "$cur" "$sel_codex"   "Codex    <noreply@openai.com>"
            tui_persona_line 4 "$cur" "$sel_cursor"  "Cursor   <cursoragent@cursor.com>"
            tui_persona_line 5 "$cur" "$sel_aider"   "aider    <aider@aider.chat>"
            tui_persona_line 6 "$cur" "$sel_devin"   "Devin    (author mode: git devin commit)"
            if [ -n "$err_msg" ]; then
                if [ -z "${NO_COLOR:-}" ]; then
                    printf '  \033[33m%s\033[0m\033[K\n' "$err_msg"
                else
                    printf '  %s\033[K\n' "$err_msg"
                fi
            else
                collect_picked
                if [ -z "${NO_COLOR:-}" ]; then
                    printf '  \033[2mSelected: %s (q/Esc cancel)\033[0m\033[K\n' "${PICKED_CSV:-none}"
                else
                    printf '  Selected: %s (q/Esc cancel)\033[K\n' "${PICKED_CSV:-none}"
                fi
            fi
            drawn=8

            tui_read_key
            case "$TUI_KEY" in
                UP|k|K)
                    cur=$((cur - 1))
                    [ "$cur" -lt 1 ] && cur=6
                    ;;
                DOWN|j|J)
                    cur=$((cur + 1))
                    [ "$cur" -gt 6 ] && cur=1
                    ;;
                SPACE)
                    toggle_idx "$cur"
                    err_msg=""
                    ;;
                1|2|3|4|5|6)
                    cur=$TUI_KEY
                    toggle_idx "$cur"
                    err_msg=""
                    ;;
                a|A)
                    if [ "$sel_claude" -eq 1 ] && [ "$sel_copilot" -eq 1 ] && [ "$sel_codex" -eq 1 ] && [ "$sel_cursor" -eq 1 ] && [ "$sel_aider" -eq 1 ]; then
                        sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0
                    else
                        sel_claude=1 sel_copilot=1 sel_codex=1 sel_cursor=1 sel_aider=1
                    fi
                    err_msg=""
                    ;;
                n|N)
                    sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0 sel_devin=0
                    err_msg=""
                    ;;
                ENTER)
                    collect_picked
                    if [ -n "$PICKED_CSV" ]; then
                        tui_cleanup
                        return 0
                    fi
                    err_msg="Select at least one (Space to toggle, q to cancel)"
                    ;;
                q|Q|ESC|CTRL_C)
                    tui_cleanup
                    return 1
                    ;;
                EOF)
                    collect_picked
                    tui_cleanup
                    [ -n "$PICKED_CSV" ] && return 0
                    return 2
                    ;;
            esac
        done
    fi

    while :; do
        printf '\nPick co-author(s) (numbers to toggle, a=all, n=none, Enter=save, q=cancel):\n'
        printf '  [%s] 1) Claude    Co-Authored-By: Claude <noreply@anthropic.com>\n' "$(mark_for "$sel_claude")"
        printf '  [%s] 2) Copilot   Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>\n' "$(mark_for "$sel_copilot")"
        printf '  [%s] 3) Codex     Co-authored-by: Codex <noreply@openai.com>\n' "$(mark_for "$sel_codex")"
        printf '  [%s] 4) Cursor    Co-authored-by: Cursor <cursoragent@cursor.com>\n' "$(mark_for "$sel_cursor")"
        printf '  [%s] 5) aider     Co-authored-by: aider (sonnet) <aider@aider.chat>\n' "$(mark_for "$sel_aider")"
        printf '  [%s] 6) Devin     (author mode only: git devin commit)\n' "$(mark_for "$sel_devin")"
        printf 'Choice [Enter=save]: '

        if ! IFS= read -r line <&3; then
            collect_picked
            [ -n "$PICKED_CSV" ] && return 0
            return 2
        fi

        line=$(trim_ws "$line")
        case "$line" in
            "")
                collect_picked
                [ -n "$PICKED_CSV" ] && return 0
                echo "Select at least one persona (or q to cancel)."
                ;;
            q|Q) return 1 ;;
            a|A|all) sel_claude=1 sel_copilot=1 sel_codex=1 sel_cursor=1 sel_aider=1 ;;
            n|N|none) sel_claude=0 sel_copilot=0 sel_codex=0 sel_cursor=0 sel_aider=0 sel_devin=0 ;;
            *)
                tokens=""
                tlist="$line,"
                while [ -n "$tlist" ]; do
                    seg=${tlist%%,*}
                    tlist=${tlist#*,}
                    tokens="${tokens:+$tokens }$seg"
                done
                bad_tok=""
                set -f
                for tok in $tokens; do
                    case "$tok" in
                        1|2|3|4|5|6) toggle_idx "$tok" ;;
                        *) bad_tok=$tok ;;
                    esac
                done
                set +f
                [ -n "$bad_tok" ] && echo "Unknown option: $bad_tok"
                ;;
        esac
    done
}

print_preview() {
    csv=$1
    has_trail=0
    plist="$csv,"
    while [ -n "$plist" ]; do
        item=${plist%%,*}
        plist=${plist#*,}
        [ -z "$item" ] && continue
        get_identity "$item" || continue
        if [ -n "$ID_KEY" ]; then
            if [ "$has_trail" -eq 0 ]; then
                echo "Next commit will include:"
                has_trail=1
            fi
            echo "  $ID_KEY: $ID_NAME <$ID_EMAIL>"
        else
            echo "Author mode alias ready: git $item commit -m \"...\""
        fi
    done
}

read_manifest() {
    M_VERSION="" M_MODE="" M_HOOKS_DIR="" M_HOOKSPATH_PREV="UNSET" M_PERSONA=""
    M_KEYS="" M_ALIASES="NONE" M_CTL_ALIAS="NONE" M_CTL_ALIAS_VAL=""
    M_HOOK_HASH="NONE" M_STUB_HASH="NONE" M_CTL_HASH="NONE" M_STUBS="NONE"
    while IFS= read -r line || [ -n "$line" ]; do
        k=${line%%=*}
        v=${line#*=}
        case "$k" in
            version) M_VERSION=$v ;;
            mode) M_MODE=$v ;;
            hooks_dir) M_HOOKS_DIR=$v ;;
            hooksPath_prev) M_HOOKSPATH_PREV=$v ;;
            persona) M_PERSONA=$v ;;
            keys) M_KEYS=$v ;;
            aliases) M_ALIASES=$v ;;
            ctl_alias) M_CTL_ALIAS=$v ;;
            ctl_alias_val) M_CTL_ALIAS_VAL=$v ;;
            hook_hash) M_HOOK_HASH=$v ;;
            stub_hash) M_STUB_HASH=$v ;;
            ctl_hash) M_CTL_HASH=$v ;;
            stubs) M_STUBS=$v ;;
        esac
    done < "$1"
}

write_manifest() {
    cat > "$1" <<MAN
version=1
mode=$W_MODE
hooks_dir=$W_HOOKS_DIR
hooksPath_prev=$W_HOOKSPATH_PREV
persona=$W_PERSONA
keys=fakeauthor.persona fakeauthor.rate
aliases=$W_ALIASES
ctl_alias=$W_CTL_ALIAS
ctl_alias_val=$W_CTL_ALIAS_VAL
hook_hash=$W_HOOK_HASH
stub_hash=$W_STUB_HASH
ctl_hash=$W_CTL_HASH
stubs=$W_STUBS
MAN
    check_no_cr "$1"
}

sync_persona_aliases() {
    sp_scope=$1
    sp_old_list=$2
    sp_new_list=$3

    if [ -n "$sp_old_list" ] && [ "$sp_old_list" != "NONE" ]; then
        for old_p in $sp_old_list; do
            keep=0
            for np in $sp_new_list; do
                if [ "$old_p" = "$np" ]; then
                    keep=1
                    break
                fi
            done
            if [ "$keep" -eq 0 ]; then
                if get_identity "$old_p"; then
                    exp_old=$(build_alias_val "$ID_NAME" "$ID_EMAIL")
                    cur_old=$(git config "$sp_scope" --get "alias.$old_p" 2>/dev/null || true)
                    if [ "$cur_old" = "$exp_old" ]; then
                        git config "$sp_scope" --unset "alias.$old_p" || true
                    elif [ -n "$cur_old" ]; then
                        echo "fakeauthor: warning: previous alias.$old_p was modified; leaving untouched" >&2
                    fi
                fi
            fi
        done
    fi

    W_ALIASES=""
    for np in $sp_new_list; do
        get_identity "$np"
        exp_new=$(build_alias_val "$ID_NAME" "$ID_EMAIL")
        cur_new=$(git config "$sp_scope" --get "alias.$np" 2>/dev/null || true)
        if [ -z "$cur_new" ] || [ "$cur_new" = "$exp_new" ]; then
            git config "$sp_scope" "alias.$np" "$exp_new"
            W_ALIASES="${W_ALIASES:+$W_ALIASES }$np"
        else
            echo "fakeauthor: note: alias.$np already exists; leaving untouched" >&2
        fi
    done
    if [ -z "$W_ALIASES" ]; then
        W_ALIASES="NONE"
    fi
}

remove_verified_file() {
    rv_path=$1
    rv_exp=$2
    rv_label=$3
    [ -e "$rv_path" ] || return 0
    if [ -n "$rv_exp" ] && [ "$rv_exp" != "NONE" ]; then
        rv_cur=$(git hash-object "$rv_path" 2>/dev/null || true)
        if [ "$rv_cur" != "$rv_exp" ]; then
            echo "fakeauthor: warning: keeping modified $rv_label ($rv_path)" >&2
            partial=1
            return 0
        fi
    fi
    rm -f "$rv_path"
}

cmd_show() {
    persona=${1:-}
    [ -n "$persona" ] || { echo "fakeauthor: show requires a persona" >&2; return 1; }
    get_identity "$persona" || { echo "fakeauthor: unknown persona: $persona" >&2; return 1; }
    [ -n "$ID_KEY" ] || { echo "fakeauthor: $persona is author-mode only (git $persona commit), no trailer" >&2; return 1; }
    echo "$ID_KEY: $ID_NAME <$ID_EMAIL>"
}

cmd_on_off() {
    action=$1
    scope_override=$2
    manifest=$3

    if [ -f "$manifest" ]; then
        read_manifest "$manifest"
        m_mode=$M_MODE
    else
        m_mode=""
    fi

    if [ "$m_mode" = "local" ] || [ "$scope_override" = "local" ]; then
        target_scope="--local"
        where="in this repo"
    elif [ "$scope_override" = "global" ]; then
        target_scope="--global"
        where="globally"
    elif git rev-parse --git-common-dir >/dev/null 2>&1; then
        target_scope="--local"
        where="in this repo"
    else
        target_scope="--global"
        where="globally"
    fi

    if [ "$action" = "off" ]; then
        git config "$target_scope" fakeauthor.off true
        echo "fakeauthor: paused $where (run 'git fakeauthor on' to resume, or 'git fakeauthor uninstall' to remove)"
    else
        git config "$target_scope" fakeauthor.off false
        echo "fakeauthor: active $where"
    fi
}

cmd_status() {
    manifest=$1
    scope_flag=$2
    if [ ! -f "$manifest" ]; then
        hp=$(git config "$scope_flag" --get core.hooksPath 2>/dev/null || echo unset)
        printf 'state: not installed\nhooksPath: %s\n' "$hp"
        return 0
    fi
    read_manifest "$manifest"

    if [ "$M_MODE" = "global" ] && git rev-parse --git-common-dir >/dev/null 2>&1; then
        eff_off=$(git config --bool fakeauthor.off 2>/dev/null || true)
        eff_persona=$(git config fakeauthor.persona 2>/dev/null || echo unset)
        eff_rate=$(git config fakeauthor.rate 2>/dev/null || echo unset)
    else
        eff_off=$(git config "$scope_flag" --bool fakeauthor.off 2>/dev/null || true)
        eff_persona=$(git config "$scope_flag" --get fakeauthor.persona 2>/dev/null || echo unset)
        eff_rate=$(git config "$scope_flag" --get fakeauthor.rate 2>/dev/null || echo unset)
    fi

    state="active"
    [ "$eff_off" = "true" ] && state="paused"
    [ -x "$M_HOOKS_DIR/commit-msg" ] || state="partially uninstalled"
    if [ "$M_MODE" = "global" ]; then
        cur_exp=$(git config --global --path --get core.hooksPath 2>/dev/null || true)
        same_path "$cur_exp" "$M_HOOKS_DIR" || state="partially uninstalled"
    fi

    hp=$(git config "$scope_flag" --get core.hooksPath 2>/dev/null || echo unset)
    alias_disp=$M_ALIASES
    [ "$alias_disp" = "NONE" ] && alias_disp=none
    printf 'state: %s (%s)\npersona: %s\nrate: %s\nhooksPath: %s\naliases: %s\n' \
        "$state" "$M_MODE" "$eff_persona" "$eff_rate" "$hp" "$alias_disp"
}

cmd_uninstall() {
    manifest=$1
    scope_flag=$2
    if [ ! -f "$manifest" ]; then
        echo "fakeauthor: not installed; nothing to do"
        return 0
    fi
    read_manifest "$manifest"
    partial=0

    remove_verified_file "$M_HOOKS_DIR/commit-msg" "$M_HOOK_HASH" "commit-msg"
    if [ -n "$M_STUBS" ] && [ "$M_STUBS" != "NONE" ]; then
        for stub in $M_STUBS; do
            remove_verified_file "$M_HOOKS_DIR/$stub" "$M_STUB_HASH" "$stub"
        done
    fi

    if [ "$M_MODE" = "global" ]; then
        cur_raw=$(git config --global --get core.hooksPath 2>/dev/null || true)
        cur_exp=$(git config --global --path --get core.hooksPath 2>/dev/null || true)
        if [ -n "$cur_raw" ]; then
            if same_path "$cur_exp" "$M_HOOKS_DIR"; then
                if [ "$M_HOOKSPATH_PREV" = "UNSET" ] || [ -z "$M_HOOKSPATH_PREV" ]; then
                    git config --global --unset core.hooksPath || true
                else
                    MSYS_NO_PATHCONV=1 git config --global core.hooksPath "$M_HOOKSPATH_PREV"
                fi
            elif [ "$cur_raw" = "$M_HOOKSPATH_PREV" ]; then
                :
            else
                echo "fakeauthor: warning: core.hooksPath changed to '$cur_raw'; leaving untouched" >&2
                partial=1
            fi
        fi
    fi

    if [ -n "$M_ALIASES" ] && [ "$M_ALIASES" != "NONE" ]; then
        for ap in $M_ALIASES; do
            if get_identity "$ap"; then
                exp_val=$(build_alias_val "$ID_NAME" "$ID_EMAIL")
                cur_alias=$(git config "$scope_flag" --get "alias.$ap" 2>/dev/null || true)
                if [ -n "$cur_alias" ]; then
                    if [ "$cur_alias" = "$exp_val" ]; then
                        git config "$scope_flag" --unset "alias.$ap" || true
                    else
                        echo "fakeauthor: warning: alias.$ap was modified; leaving untouched" >&2
                        partial=1
                    fi
                fi
            fi
        done
    fi

    if [ "$M_CTL_ALIAS" = "YES" ]; then
        cur_ctl_alias=$(git config "$scope_flag" --get alias.fakeauthor 2>/dev/null || true)
        if [ -n "$cur_ctl_alias" ]; then
            if [ "$cur_ctl_alias" = "$M_CTL_ALIAS_VAL" ]; then
                git config "$scope_flag" --unset alias.fakeauthor || true
            else
                echo "fakeauthor: warning: alias.fakeauthor was modified; leaving untouched" >&2
                partial=1
            fi
        fi
    fi

    for k in $M_KEYS; do
        git config "$scope_flag" --unset-all "$k" 2>/dev/null || true
    done

    kept_user=""
    for uk in fakeauthor.name fakeauthor.email fakeauthor.off; do
        if git config "$scope_flag" --get "$uk" >/dev/null 2>&1; then
            kept_user="${kept_user:+$kept_user }$uk"
        fi
    done
    [ -n "$kept_user" ] && echo "fakeauthor: note: kept user config ($kept_user)"

    ctl_dir=$(cd "$(dirname "$manifest")" 2>/dev/null && pwd -P)
    remove_verified_file "$ctl_dir/fakeauthor.sh" "$M_CTL_HASH" "fakeauthor.sh"

    if [ "$M_MODE" = "global" ]; then
        if [ -d "$M_HOOKS_DIR" ]; then
            if ! rmdir "$M_HOOKS_DIR" 2>/dev/null; then
                echo "fakeauthor: warning: $M_HOOKS_DIR not empty; leaving directory" >&2
                partial=1
            fi
        fi
        if [ "$partial" -eq 0 ]; then
            rm -f "$manifest"
            rmdir "$ctl_dir" 2>/dev/null || true
            echo "fakeauthor: uninstalled (global)"
        else
            echo "fakeauthor: partially uninstalled; manifest kept at $manifest" >&2
        fi
    else
        if [ "$partial" -eq 0 ]; then
            rm -f "$manifest"
            echo "fakeauthor: uninstalled (local)"
        else
            echo "fakeauthor: partially uninstalled; manifest kept at $manifest" >&2
        fi
    fi
}

cmd_set_personas() {
    manifest=$1
    scope_flag=$2
    new_csv=$3
    new_list=$4

    read_manifest "$manifest"
    git config "$scope_flag" fakeauthor.persona "$new_csv"
    sync_persona_aliases "$scope_flag" "$M_ALIASES" "$new_list"

    W_MODE=$M_MODE
    W_HOOKS_DIR=$M_HOOKS_DIR
    W_HOOKSPATH_PREV=$M_HOOKSPATH_PREV
    W_PERSONA=$new_csv
    W_CTL_ALIAS=$M_CTL_ALIAS
    W_CTL_ALIAS_VAL=$M_CTL_ALIAS_VAL
    W_HOOK_HASH=$M_HOOK_HASH
    W_STUB_HASH=$M_STUB_HASH
    W_CTL_HASH=$M_CTL_HASH
    W_STUBS=$M_STUBS
    write_manifest "$manifest"
}

cmd_interactive() {
    manifest=$1
    scope_flag=$2
    scope_override=$3

    if [ ! -f "$manifest" ]; then
        echo "fakeauthor: not installed; run install.sh first" >&2
        return 1
    fi
    read_manifest "$manifest"

    if [ -n "${FAKEAUTHOR_TTY:-}" ]; then
        exec 3<"$FAKEAUTHOR_TTY"
    elif [ -r /dev/tty ]; then
        exec 3</dev/tty
    else
        exec 3<&0
    fi
    target="manifest"
    if [ "$M_MODE" = "global" ] && [ -z "$scope_override" ] && git rev-parse --git-common-dir >/dev/null 2>&1; then
        sc_rc=0
        pick_scope "Apply changes to:" "This repo only (repo config)" "All repos (global)" || sc_rc=$?
        if [ "$sc_rc" -eq 1 ]; then
            exec 3<&-
            echo "Cancelled."
            return 0
        elif [ "$sc_rc" -ne 0 ]; then
            exec 3<&-
            return 1
        fi
        if [ "$PICKED_SCOPE" -eq 1 ]; then
            target="repo_cfg"
        else
            target="manifest"
        fi
    fi

    if [ "$target" = "repo_cfg" ]; then
        cur_csv=$(git config fakeauthor.persona 2>/dev/null || true)
    else
        cur_csv=$(git config "$scope_flag" --get fakeauthor.persona 2>/dev/null || true)
    fi
    [ -z "$cur_csv" ] && cur_csv="claude"

    rc=0
    pick_personas "$cur_csv" || rc=$?
    exec 3<&-
    if [ "$rc" -eq 1 ]; then
        echo "Cancelled."
        return 0
    elif [ "$rc" -ne 0 ]; then
        return 1
    fi

    if [ "$target" = "repo_cfg" ]; then
        git config --local fakeauthor.persona "$PICKED_CSV"
        g_off=$(git config --global --bool fakeauthor.off 2>/dev/null || true)
        l_off=$(git config --local --bool fakeauthor.off 2>/dev/null || true)
        if [ "$g_off" = "true" ]; then
            git config --local fakeauthor.off false
        elif [ "$l_off" = "true" ]; then
            git config --local --unset fakeauthor.off || true
        fi
        echo "Saved: $PICKED_CSV (this repo)"
    else
        cmd_set_personas "$manifest" "$scope_flag" "$PICKED_CSV" "$PICKED_LIST"
        echo "Saved: $PICKED_CSV ($M_MODE)"
    fi
    print_preview "$PICKED_CSV"
}

main() {
    scope_override=""
    pos1=""
    pos2=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --local) scope_override="local" ;;
            --global) scope_override="global" ;;
            -h|--help) ctl_usage; return 0 ;;
            -*) ctl_usage; return 2 ;;
            *)
                if [ -z "$pos1" ]; then
                    pos1=$1
                elif [ -z "$pos2" ]; then
                    pos2=$1
                else
                    ctl_usage
                    return 2
                fi
                ;;
        esac
        shift
    done

    if [ "$scope_override" = "local" ]; then
        common=$(git rev-parse --git-common-dir 2>/dev/null) || {
            echo "fakeauthor: --local requires running inside a git repository" >&2
            return 1
        }
        manifest="$(canon_path "$common")/fakeauthor-manifest"
        scope_flag="--local"
    elif [ "$scope_override" = "global" ]; then
        manifest="$FAKEAUTHOR_DIR/manifest"
        scope_flag="--global"
    elif [ -n "$script_dir" ] && [ -f "$script_dir/fakeauthor-manifest" ]; then
        manifest="$script_dir/fakeauthor-manifest"
        scope_flag="--local"
    else
        manifest="$FAKEAUTHOR_DIR/manifest"
        scope_flag="--global"
    fi

    case "$pos1" in
        show)
            cmd_show "$pos2"
            ;;
        "")
            [ -n "$pos2" ] && { ctl_usage; return 2; }
            if has_tty; then
                cmd_interactive "$manifest" "$scope_flag" "$scope_override"
            else
                cmd_status "$manifest" "$scope_flag"
            fi
            ;;
        status)
            [ -n "$pos2" ] && { ctl_usage; return 2; }
            cmd_status "$manifest" "$scope_flag"
            ;;
        on|off)
            [ -n "$pos2" ] && { ctl_usage; return 2; }
            cmd_on_off "$pos1" "$scope_override" "$manifest"
            ;;
        uninstall)
            [ -n "$pos2" ] && { ctl_usage; return 2; }
            cmd_uninstall "$manifest" "$scope_flag"
            ;;
        all|claude|copilot|codex|cursor|aider|devin|*,*)
            [ -n "$pos2" ] && { ctl_usage; return 2; }
            [ -f "$manifest" ] || { echo "fakeauthor: not installed; run install.sh first" >&2; return 1; }
            normalize_personas "$pos1" || { echo "fakeauthor: unknown persona: ${BAD_PERSONA:-$pos1}" >&2; return 1; }
            cmd_set_personas "$manifest" "$scope_flag" "$NORM_CSV" "$NORM_LIST"
            echo "Saved: $NORM_CSV ($W_MODE)"
            print_preview "$NORM_CSV"
            ;;
        *)
            ctl_usage
            return 2
            ;;
    esac
}

main "$@"
EOF
}

read_manifest() {
    M_VERSION="" M_MODE="" M_HOOKS_DIR="" M_HOOKSPATH_PREV="UNSET" M_PERSONA=""
    M_KEYS="" M_ALIASES="NONE" M_CTL_ALIAS="NONE" M_CTL_ALIAS_VAL=""
    M_HOOK_HASH="NONE" M_STUB_HASH="NONE" M_CTL_HASH="NONE" M_STUBS="NONE"
    while IFS= read -r line || [ -n "$line" ]; do
        k=${line%%=*}
        v=${line#*=}
        case "$k" in
            version) M_VERSION=$v ;;
            mode) M_MODE=$v ;;
            hooks_dir) M_HOOKS_DIR=$v ;;
            hooksPath_prev) M_HOOKSPATH_PREV=$v ;;
            persona) M_PERSONA=$v ;;
            keys) M_KEYS=$v ;;
            aliases) M_ALIASES=$v ;;
            ctl_alias) M_CTL_ALIAS=$v ;;
            ctl_alias_val) M_CTL_ALIAS_VAL=$v ;;
            hook_hash) M_HOOK_HASH=$v ;;
            stub_hash) M_STUB_HASH=$v ;;
            ctl_hash) M_CTL_HASH=$v ;;
            stubs) M_STUBS=$v ;;
        esac
    done < "$1"
}

write_manifest() {
    cat > "$1" <<EOF
version=1
mode=$W_MODE
hooks_dir=$W_HOOKS_DIR
hooksPath_prev=$W_HOOKSPATH_PREV
persona=$W_PERSONA
keys=fakeauthor.persona fakeauthor.rate
aliases=$W_ALIASES
ctl_alias=$W_CTL_ALIAS
ctl_alias_val=$W_CTL_ALIAS_VAL
hook_hash=$W_HOOK_HASH
stub_hash=$W_STUB_HASH
ctl_hash=$W_CTL_HASH
stubs=$W_STUBS
EOF
    check_no_cr "$1"
}

# write_managed <target_path> <emitter_fn> <prev_hash> <force_flag> <mode_chmod>
write_managed() {
    wm_target=$1
    wm_emit=$2
    wm_prev=$3
    wm_force=$4
    wm_exec=$5

    WRITTEN_KEPT=0
    if [ -f "$wm_target" ] && [ -n "$wm_prev" ] && [ "$wm_prev" != "NONE" ]; then
        wm_cur=$(git hash-object "$wm_target" 2>/dev/null || true)
        if [ "$wm_cur" != "$wm_prev" ]; then
            if [ "$wm_force" -eq 0 ]; then
                echo "fakeauthor: warning: $(basename "$wm_target") was hand-modified; keeping existing file (use --force to overwrite)" >&2
                WRITTEN_HASH=$wm_prev
                WRITTEN_KEPT=1
                return 0
            fi
            echo "fakeauthor: warning: overwriting modified $(basename "$wm_target") (--force)" >&2
        fi
    fi

    "$wm_emit" > "$wm_target"
    check_no_cr "$wm_target"
    [ "$wm_exec" -eq 1 ] && chmod +x "$wm_target"
    WRITTEN_HASH=$(git hash-object "$wm_target")
}

sync_persona_aliases() {
    sp_scope=$1
    sp_old_list=$2
    sp_new_list=$3

    if [ -n "$sp_old_list" ] && [ "$sp_old_list" != "NONE" ]; then
        for old_p in $sp_old_list; do
            keep=0
            for np in $sp_new_list; do
                if [ "$old_p" = "$np" ]; then
                    keep=1
                    break
                fi
            done
            if [ "$keep" -eq 0 ]; then
                if get_identity "$old_p"; then
                    exp_old=$(build_alias_val "$ID_NAME" "$ID_EMAIL")
                    cur_old=$(git config "$sp_scope" --get "alias.$old_p" 2>/dev/null || true)
                    if [ "$cur_old" = "$exp_old" ]; then
                        git config "$sp_scope" --unset "alias.$old_p" || true
                    elif [ -n "$cur_old" ]; then
                        echo "fakeauthor: warning: previous alias.$old_p was modified; leaving untouched" >&2
                    fi
                fi
            fi
        done
    fi

    W_ALIASES=""
    for np in $sp_new_list; do
        get_identity "$np"
        exp_new=$(build_alias_val "$ID_NAME" "$ID_EMAIL")
        cur_new=$(git config "$sp_scope" --get "alias.$np" 2>/dev/null || true)
        if [ -z "$cur_new" ] || [ "$cur_new" = "$exp_new" ]; then
            git config "$sp_scope" "alias.$np" "$exp_new"
            W_ALIASES="${W_ALIASES:+$W_ALIASES }$np"
        else
            echo "fakeauthor: note: alias.$np already exists; leaving untouched" >&2
        fi
    done
    if [ -z "$W_ALIASES" ]; then
        W_ALIASES="NONE"
    fi
}

sync_ctl_alias() {
    sc_scope=$1
    sc_val=$2
    sc_prev_val=$3

    cur_ctl=$(git config "$sc_scope" --get alias.fakeauthor 2>/dev/null || true)
    if [ -z "$cur_ctl" ] || [ "$cur_ctl" = "$sc_val" ] || { [ -n "$sc_prev_val" ] && [ "$cur_ctl" = "$sc_prev_val" ]; }; then
        git config "$sc_scope" alias.fakeauthor "$sc_val"
        W_CTL_ALIAS="YES"
        W_CTL_ALIAS_VAL=$sc_val
    else
        echo "fakeauthor: note: alias.fakeauthor already exists; leaving untouched" >&2
        W_CTL_ALIAS="NONE"
        W_CTL_ALIAS_VAL=""
    fi
}

cmd_install_global() {
    persona_csv=$1
    persona_list=$2
    force=$3
    show_preview=${4:-0}

    hook_dir="$FAKEAUTHOR_DIR/hooks"
    manifest="$FAKEAUTHOR_DIR/manifest"
    ctl="$FAKEAUTHOR_DIR/fakeauthor.sh"

    cur_raw=$(git config --global --get core.hooksPath 2>/dev/null || true)
    cur_exp=$(git config --global --path --get core.hooksPath 2>/dev/null || true)

    if [ -n "$cur_raw" ]; then
        if ! same_path "$cur_exp" "$hook_dir"; then
            echo "fakeauthor: global core.hooksPath is already set to '$cur_raw'; refusing to clobber (try --local)" >&2
            exit 1
        fi
        if [ ! -f "$manifest" ]; then
            echo "fakeauthor: $hook_dir already in core.hooksPath without fakeauthor manifest; refusing to clobber (try --local)" >&2
            exit 1
        fi
    elif [ ! -f "$manifest" ] && [ -e "$hook_dir/commit-msg" ] && [ "$force" -eq 0 ]; then
        echo "fakeauthor: $hook_dir/commit-msg exists without fakeauthor manifest; refusing to clobber (try --local)" >&2
        exit 1
    fi

    if [ -f "$manifest" ]; then
        read_manifest "$manifest"
        W_HOOKSPATH_PREV=$M_HOOKSPATH_PREV
        prev_hook_hash=$M_HOOK_HASH
        prev_stub_hash=$M_STUB_HASH
        prev_ctl_hash=$M_CTL_HASH
    else
        for stub in $STUB_HOOKS; do
            if [ -e "$hook_dir/$stub" ] && [ "$force" -eq 0 ]; then
                echo "fakeauthor: $hook_dir/$stub exists without fakeauthor manifest; refusing to clobber (try --local)" >&2
                exit 1
            fi
        done
        M_ALIASES="NONE"
        M_CTL_ALIAS_VAL=""
        W_HOOKSPATH_PREV=UNSET
        prev_hook_hash=NONE
        prev_stub_hash=NONE
        prev_ctl_hash=NONE
    fi

    mkdir -p "$hook_dir"
    write_managed "$hook_dir/commit-msg" emit_hook "$prev_hook_hash" "$force" 1
    W_HOOK_HASH=$WRITTEN_HASH

    W_STUB_HASH=""
    stub_kept=0
    for stub in $STUB_HOOKS; do
        write_managed "$hook_dir/$stub" emit_chain_stub "$prev_stub_hash" "$force" 1
        if [ "$WRITTEN_KEPT" -eq 1 ]; then
            stub_kept=1
        elif [ -z "$W_STUB_HASH" ]; then
            W_STUB_HASH=$WRITTEN_HASH
        fi
    done
    [ "$stub_kept" -eq 1 ] && [ "$prev_stub_hash" != "NONE" ] && W_STUB_HASH=$prev_stub_hash
    W_STUBS=$STUB_HOOKS

    write_managed "$ctl" emit_ctl "$prev_ctl_hash" "$force" 1
    W_CTL_HASH=$WRITTEN_HASH

    git config --global core.hooksPath "$(to_git_path "$hook_dir")"
    git config --global fakeauthor.persona "$persona_csv"
    if ! git config --global --get fakeauthor.rate >/dev/null 2>&1; then
        git config --global fakeauthor.rate 1
    fi

    sync_persona_aliases --global "$M_ALIASES" "$persona_list"

    if [ "$FAKEAUTHOR_DIR" = "$DEFAULT_FAKEAUTHOR_DIR" ]; then
        ctl_alias_target='!sh "$HOME/.local/share/fakeauthor/fakeauthor.sh"'
        ctl_fallback="sh ~/.local/share/fakeauthor/fakeauthor.sh status"
    else
        ctl_dir_git=$(to_git_path "$FAKEAUTHOR_DIR")
        ctl_alias_target="!sh '$(sq_escape "$ctl_dir_git")/fakeauthor.sh'"
        ctl_fallback="sh $ctl_dir_git/fakeauthor.sh status"
    fi
    sync_ctl_alias --global "$ctl_alias_target" "$M_CTL_ALIAS_VAL"

    W_MODE=global
    W_HOOKS_DIR=$(canon_path "$hook_dir")
    W_PERSONA=$persona_csv
    write_manifest "$manifest"

    if [ "$show_preview" -eq 1 ]; then
        echo "Saved: $persona_csv (global)"
        print_preview "$persona_csv"
        echo "Manage anytime: git fakeauthor [on|off|status|uninstall]"
    else
        if [ "$W_CTL_ALIAS" = "YES" ]; then
            verify_cmd="git fakeauthor status"
        else
            verify_cmd="$ctl_fallback"
        fi
        printf 'fakeauthor: installed %s (global)\nverify: %s\n' "$persona_csv" "$verify_cmd"
    fi
}

cmd_install_local() {
    persona_csv=$1
    persona_list=$2
    force=$3
    show_preview=${4:-0}

    common=$(git rev-parse --git-common-dir 2>/dev/null) || {
        echo "fakeauthor: --local requires running inside a git repository" >&2
        exit 1
    }
    common_abs=$(canon_path "$common")

    g_hp=$(git config --global --get core.hooksPath 2>/dev/null || true)
    l_hp=$(git config --local --get core.hooksPath 2>/dev/null || true)
    if [ -n "$g_hp" ] || [ -n "$l_hp" ]; then
        echo "fakeauthor: core.hooksPath is already set; --local hooks would be bypassed" >&2
        exit 1
    fi

    hook_dir="$common_abs/hooks"
    manifest="$common_abs/fakeauthor-manifest"
    ctl="$common_abs/fakeauthor.sh"

    if [ ! -f "$manifest" ] && [ -e "$hook_dir/commit-msg" ] && [ "$force" -eq 0 ]; then
        echo "fakeauthor: foreign $hook_dir/commit-msg exists; pass --force to overwrite" >&2
        exit 1
    fi

    if [ -f "$manifest" ]; then
        read_manifest "$manifest"
        prev_hook_hash=$M_HOOK_HASH
        prev_ctl_hash=$M_CTL_HASH
    else
        M_ALIASES="NONE"
        M_CTL_ALIAS_VAL=""
        prev_hook_hash=NONE
        prev_ctl_hash=NONE
    fi

    mkdir -p "$hook_dir"
    write_managed "$hook_dir/commit-msg" emit_hook "$prev_hook_hash" "$force" 1
    W_HOOK_HASH=$WRITTEN_HASH

    write_managed "$ctl" emit_ctl "$prev_ctl_hash" "$force" 1
    W_CTL_HASH=$WRITTEN_HASH

    git config --local fakeauthor.persona "$persona_csv"
    if ! git config --local --get fakeauthor.rate >/dev/null 2>&1; then
        git config --local fakeauthor.rate 1
    fi

    sync_persona_aliases --local "$M_ALIASES" "$persona_list"
    ctl_alias_target='!f(){ sh "$(git rev-parse --git-common-dir)/fakeauthor.sh" "$@"; };f'
    sync_ctl_alias --local "$ctl_alias_target" "$M_CTL_ALIAS_VAL"

    W_MODE=local
    W_HOOKS_DIR=$(canon_path "$hook_dir")
    W_HOOKSPATH_PREV=UNSET
    W_PERSONA=$persona_csv
    W_STUB_HASH=NONE
    W_STUBS=NONE
    write_manifest "$manifest"

    if [ "$show_preview" -eq 1 ]; then
        echo "Saved: $persona_csv (local)"
        print_preview "$persona_csv"
        echo "Manage anytime: git fakeauthor [on|off|status|uninstall]"
    else
        if [ "$W_CTL_ALIAS" = "YES" ]; then
            verify_cmd="git fakeauthor status"
        else
            verify_cmd="sh .git/fakeauthor.sh status"
        fi
        printf 'fakeauthor: installed %s (local)\nverify: %s\n' "$persona_csv" "$verify_cmd"
    fi
}

cmd_wizard() {
    scope_flag=$1
    force=$2

    if [ -n "${FAKEAUTHOR_TTY:-}" ]; then
        exec 3<"$FAKEAUTHOR_TTY"
    elif [ -r /dev/tty ]; then
        exec 3</dev/tty
    else
        exec 3<&0
    fi
    if [ -z "$scope_flag" ]; then
        if git rev-parse --git-common-dir >/dev/null 2>&1; then
            repo_top=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
            repo_name=$(basename "$repo_top")
            printf 'fakeauthor — fake AI co-authors for git commits (parody)\n\n'
            sc_rc=0
            pick_scope "1) Scope (repo: $repo_name):" "All repos (global)" "This repo only (local .git/hooks)" || sc_rc=$?
            if [ "$sc_rc" -eq 1 ]; then
                exec 3<&-
                echo "Cancelled."
                exit 0
            elif [ "$sc_rc" -ne 0 ]; then
                exec 3<&-
                exit 1
            fi
            if [ "$PICKED_SCOPE" -eq 1 ]; then
                scope_flag="global"
            else
                scope_flag="local"
            fi
        else
            printf 'fakeauthor — fake AI co-authors for git commits (parody)\n'
            scope_flag="global"
        fi
    fi

    init_csv="claude"
    if [ "$scope_flag" = "local" ]; then
        existing=$(git config --local --get fakeauthor.persona 2>/dev/null || true)
        [ -n "$existing" ] && init_csv=$existing
    else
        existing=$(git config --global --get fakeauthor.persona 2>/dev/null || true)
        [ -n "$existing" ] && init_csv=$existing
    fi

    rc=0
    pick_personas "$init_csv" || rc=$?
    exec 3<&-
    if [ "$rc" -eq 1 ]; then
        echo "Cancelled."
        exit 0
    elif [ "$rc" -ne 0 ]; then
        exit 1
    fi

    if [ "$scope_flag" = "local" ]; then
        cmd_install_local "$PICKED_CSV" "$PICKED_LIST" "$force" 1
    else
        cmd_install_global "$PICKED_CSV" "$PICKED_LIST" "$force" 1
    fi
}

SCOPE_FLAG=""
FORCE=0
POS1=""
POS2=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --local) SCOPE_FLAG="local" ;;
        --global) SCOPE_FLAG="global" ;;
        --force) FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) usage; exit 2 ;;
        *)
            if [ -z "$POS1" ]; then
                POS1=$1
            elif [ -z "$POS2" ]; then
                POS2=$1
            else
                usage
                exit 2
            fi
            ;;
    esac
    shift
done

case "$POS1" in
    show)
        [ -z "$SCOPE_FLAG" ] && [ "$FORCE" -eq 0 ] || { usage; exit 2; }
        cmd_show "$POS2"
        ;;
    "")
        [ -n "$POS2" ] && { usage; exit 2; }
        if has_tty; then
            cmd_wizard "$SCOPE_FLAG" "$FORCE"
        else
            if [ "$SCOPE_FLAG" = "local" ]; then
                cmd_install_local "claude" "claude" "$FORCE" 0
            else
                cmd_install_global "claude" "claude" "$FORCE" 0
            fi
        fi
        ;;
    all|claude|copilot|codex|cursor|aider|devin|*,*)
        [ -n "$POS2" ] && { usage; exit 2; }
        normalize_personas "$POS1" || {
            echo "fakeauthor: unknown persona: ${BAD_PERSONA:-$POS1}" >&2
            exit 1
        }
        if [ "$SCOPE_FLAG" = "local" ]; then
            cmd_install_local "$NORM_CSV" "$NORM_LIST" "$FORCE" 0
        else
            cmd_install_global "$NORM_CSV" "$NORM_LIST" "$FORCE" 0
        fi
        ;;
    on|off|status|uninstall)
        [ -n "$POS2" ] && { usage; exit 2; }
        if [ "$SCOPE_FLAG" = "local" ]; then
            emit_ctl | FAKEAUTHOR_DIR="$FAKEAUTHOR_DIR" sh -s -- --local "$POS1"
        elif [ "$SCOPE_FLAG" = "global" ]; then
            emit_ctl | FAKEAUTHOR_DIR="$FAKEAUTHOR_DIR" sh -s -- --global "$POS1"
        else
            emit_ctl | FAKEAUTHOR_DIR="$FAKEAUTHOR_DIR" sh -s -- "$POS1"
        fi
        ;;
    *)
        usage
        exit 2
        ;;
esac
