#!/bin/sh
# fakeai — fake AI co-author trailers for git. Parody; not affiliated with any vendor.

set -eu

FAKEAI_DIR="${FAKEAI_DIR:-$HOME/.config/fakeai}"
STUB_HOOKS="applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit prepare-commit-msg post-commit pre-rebase post-checkout post-merge pre-push post-rewrite sendemail-validate"

usage() {
    cat >&2 <<'EOF'
usage: sh install.sh [--local] [--force] [persona|off|status|show <persona>]
EOF
}

canon_path() {
    p=${1:-}
    [ -z "$p" ] && return 0
    suffix=""
    while [ ! -d "$p" ] && [ "$p" != "/" ] && [ "$p" != "." ]; do
        b=$(basename "$p")
        suffix="/$b$suffix"
        p=$(dirname "$p")
    done
    if [ -d "$p" ]; then
        cp=$(cd "$p" 2>/dev/null && pwd -P) || cp=$p
        printf '%s%s\n' "${cp%/}" "$suffix"
    else
        printf '%s\n' "${1%/}"
    fi
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

cmd_show() {
    persona=${1:-}
    if [ -z "$persona" ]; then
        echo "fakeai: show requires a persona" >&2
        exit 1
    fi
    if ! get_identity "$persona"; then
        echo "fakeai: unknown persona: $persona" >&2
        exit 1
    fi
    if [ -z "$ID_KEY" ]; then
        echo "fakeai: $persona is author-mode only (git $persona commit), no trailer" >&2
        exit 1
    fi
    echo "$ID_KEY: $ID_NAME <$ID_EMAIL>"
}

emit_hook() {
    cat <<'EOF'
#!/bin/sh
# fakeai hook v1

chain() {
    [ "${_FAKEAI_CHAINED:-0}" = "1" ] && exit 0
    common=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
    h="$common/hooks/${0##*/}"
    [ -x "$h" ] || exit 0
    self_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || self_dir=""
    hook_dir=$(cd "$(dirname "$h")" 2>/dev/null && pwd -P) || hook_dir=""
    [ -n "$self_dir" ] && [ "$self_dir" = "$hook_dir" ] && exit 0
    _FAKEAI_CHAINED=1 exec "$h" "$@"
}

[ -n "${NO_FAKEAI:-}" ] && [ "$NO_FAKEAI" != "0" ] && chain "$@"

off=$(git config --bool fakeai.off 2>/dev/null || true)
[ "$off" = "true" ] && chain "$@"

rate=$(git config fakeai.rate 2>/dev/null || true)
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

if command -v sed >/dev/null 2>&1; then
    cleaned=$(sed '/^[^[:space:]]* -\{1,\} >8 -\{1,\}$/,$d' "$1" 2>/dev/null | git stripspace --strip-comments 2>/dev/null)
else
    cleaned=$(git stripspace --strip-comments < "$1" 2>/dev/null)
fi
[ -z "$cleaned" ] && chain "$@"

persona=$(git config fakeai.persona 2>/dev/null || true)
[ -z "$persona" ] && persona=claude

key=""
name=""
email=""
case "$persona" in
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

o_name=$(git config fakeai.name 2>/dev/null || true)
o_email=$(git config fakeai.email 2>/dev/null || true)
if [ -n "$key" ]; then
    [ -n "$o_name" ] && name="$o_name"
    [ -n "$o_email" ] && email="$o_email"
else
    if [ -n "$o_name" ] && [ -n "$o_email" ]; then
        key="Co-authored-by"
        name="$o_name"
        email="$o_email"
    else
        chain "$@"
    fi
fi

git interpret-trailers --in-place --if-exists doNothing --trailer "$key: $name <$email>" "$1" 2>/dev/null || true
chain "$@"
EOF
}

emit_chain_stub() {
    cat <<'EOF'
#!/bin/sh
# fakeai chain stub v1
[ "${_FAKEAI_CHAINED:-0}" = "1" ] && exit 0
common=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
h="$common/hooks/${0##*/}"
[ -x "$h" ] || exit 0
self_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || self_dir=""
hook_dir=$(cd "$(dirname "$h")" 2>/dev/null && pwd -P) || hook_dir=""
[ -n "$self_dir" ] && [ "$self_dir" = "$hook_dir" ] && exit 0
_FAKEAI_CHAINED=1 exec "$h" "$@"
EOF
}

emit_ctl() {
    cat <<'EOF'
#!/bin/sh
# fakeai offline control CLI (status / off)
set -eu

if [ -z "${FAKEAI_DIR:-}" ]; then
    script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || script_dir=""
    if [ -n "$script_dir" ] && [ -f "$script_dir/manifest" ]; then
        FAKEAI_DIR=$script_dir
    else
        FAKEAI_DIR="$HOME/.config/fakeai"
    fi
fi

ctl_usage() {
    cat >&2 <<'USAGE'
usage: sh fakeai.sh [--local] <status|off>
USAGE
}

canon_path() {
    p=${1:-}
    [ -z "$p" ] && return 0
    suffix=""
    while [ ! -d "$p" ] && [ "$p" != "/" ] && [ "$p" != "." ]; do
        b=$(basename "$p")
        suffix="/$b$suffix"
        p=$(dirname "$p")
    done
    if [ -d "$p" ]; then
        cp=$(cd "$p" 2>/dev/null && pwd -P) || cp=$p
        printf '%s%s\n' "${cp%/}" "$suffix"
    else
        printf '%s\n' "${1%/}"
    fi
}

read_manifest() {
    M_VERSION="" M_MODE="" M_HOOKS_DIR="" M_HOOKSPATH_PREV="UNSET" M_PERSONA=""
    M_KEYS="" M_ALIAS_NAME="NONE" M_ALIAS_VAL="" M_HOOK_HASH="NONE"
    M_STUB_HASH="NONE" M_CTL_HASH="NONE" M_STUBS="NONE"
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
            alias_name) M_ALIAS_NAME=$v ;;
            alias_val) M_ALIAS_VAL=$v ;;
            hook_hash) M_HOOK_HASH=$v ;;
            stub_hash) M_STUB_HASH=$v ;;
            ctl_hash) M_CTL_HASH=$v ;;
            stubs) M_STUBS=$v ;;
        esac
    done < "$1"
}

remove_verified_file() {
    rv_path=$1
    rv_exp=$2
    rv_label=$3
    [ -e "$rv_path" ] || return 0
    if [ -n "$rv_exp" ] && [ "$rv_exp" != "NONE" ]; then
        rv_cur=$(git hash-object "$rv_path" 2>/dev/null || true)
        if [ "$rv_cur" != "$rv_exp" ]; then
            echo "fakeai: warning: keeping modified $rv_label ($rv_path)" >&2
            partial=1
            return 0
        fi
    fi
    rm -f "$rv_path"
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
    state="installed"
    [ -x "$M_HOOKS_DIR/commit-msg" ] || state="partially uninstalled"
    if [ "$M_MODE" = "global" ]; then
        cur_exp=$(git config --global --path --get core.hooksPath 2>/dev/null || true)
        [ "$(canon_path "$cur_exp")" = "$M_HOOKS_DIR" ] || state="partially uninstalled"
    fi
    persona=$(git config "$scope_flag" --get fakeai.persona 2>/dev/null || echo unset)
    rate=$(git config "$scope_flag" --get fakeai.rate 2>/dev/null || echo unset)
    hp=$(git config "$scope_flag" --get core.hooksPath 2>/dev/null || echo unset)
    alias_disp=$M_ALIAS_NAME
    [ "$alias_disp" = "NONE" ] && alias_disp=none
    printf 'state: %s (%s)\npersona: %s\nrate: %s\nhooksPath: %s\nalias: %s\n' \
        "$state" "$M_MODE" "$persona" "$rate" "$hp" "$alias_disp"
}

cmd_off() {
    manifest=$1
    scope_flag=$2
    if [ ! -f "$manifest" ]; then
        echo "fakeai: not installed; nothing to do"
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
            cur_canon=$(canon_path "$cur_exp")
            if [ "$cur_canon" = "$M_HOOKS_DIR" ]; then
                if [ "$M_HOOKSPATH_PREV" = "UNSET" ] || [ -z "$M_HOOKSPATH_PREV" ]; then
                    git config --global --unset core.hooksPath || true
                else
                    git config --global core.hooksPath "$M_HOOKSPATH_PREV"
                fi
            elif [ "$cur_raw" = "$M_HOOKSPATH_PREV" ]; then
                :
            else
                echo "fakeai: warning: core.hooksPath changed to '$cur_raw'; leaving untouched" >&2
                partial=1
            fi
        fi

        if [ -n "$M_ALIAS_NAME" ] && [ "$M_ALIAS_NAME" != "NONE" ]; then
            cur_alias=$(git config --global --get "alias.$M_ALIAS_NAME" 2>/dev/null || true)
            if [ -n "$cur_alias" ]; then
                if [ "$cur_alias" = "$M_ALIAS_VAL" ]; then
                    git config --global --unset "alias.$M_ALIAS_NAME" || true
                else
                    echo "fakeai: warning: alias.$M_ALIAS_NAME was modified; leaving untouched" >&2
                    partial=1
                fi
            fi
        fi
    fi

    for k in $M_KEYS; do
        git config "$scope_flag" --unset-all "$k" 2>/dev/null || true
    done

    kept_user=""
    for uk in fakeai.name fakeai.email fakeai.off; do
        if git config "$scope_flag" --get "$uk" >/dev/null 2>&1; then
            kept_user="${kept_user:+$kept_user }$uk"
        fi
    done
    [ -n "$kept_user" ] && echo "fakeai: note: kept user config ($kept_user)"

    if [ "$M_MODE" = "global" ]; then
        remove_verified_file "$FAKEAI_DIR/fakeai.sh" "$M_CTL_HASH" "fakeai.sh"
        if [ -d "$M_HOOKS_DIR" ]; then
            if ! rmdir "$M_HOOKS_DIR" 2>/dev/null; then
                echo "fakeai: warning: $M_HOOKS_DIR not empty; leaving directory" >&2
                partial=1
            fi
        fi
        if [ "$partial" -eq 0 ]; then
            rm -f "$manifest"
            rmdir "$FAKEAI_DIR" 2>/dev/null || true
            echo "fakeai: uninstalled (global)"
        else
            echo "fakeai: partially uninstalled; manifest kept at $manifest" >&2
        fi
    else
        if [ "$partial" -eq 0 ]; then
            rm -f "$manifest"
            echo "fakeai: uninstalled (local)"
        else
            echo "fakeai: partially uninstalled; manifest kept at $manifest" >&2
        fi
    fi
}

main() {
    local_mode=0
    subcmd=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --local) local_mode=1 ;;
            -h|--help) ctl_usage; return 0 ;;
            -*) ctl_usage; return 2 ;;
            *)
                if [ -z "$subcmd" ]; then
                    subcmd=$1
                else
                    ctl_usage
                    return 2
                fi
                ;;
        esac
        shift
    done

    if [ "$local_mode" -eq 1 ]; then
        common=$(git rev-parse --git-common-dir 2>/dev/null) || {
            echo "fakeai: --local requires running inside a git repository" >&2
            return 1
        }
        manifest="$(canon_path "$common")/fakeai-manifest"
        scope_flag="--local"
    else
        manifest="$FAKEAI_DIR/manifest"
        scope_flag="--global"
    fi

    case "$subcmd" in
        status) cmd_status "$manifest" "$scope_flag" ;;
        off) cmd_off "$manifest" "$scope_flag" ;;
        *) ctl_usage; return 2 ;;
    esac
}

main "$@"
EOF
}

read_manifest() {
    M_VERSION="" M_MODE="" M_HOOKS_DIR="" M_HOOKSPATH_PREV="UNSET" M_PERSONA=""
    M_KEYS="" M_ALIAS_NAME="NONE" M_ALIAS_VAL="" M_HOOK_HASH="NONE"
    M_STUB_HASH="NONE" M_CTL_HASH="NONE" M_STUBS="NONE"
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
            alias_name) M_ALIAS_NAME=$v ;;
            alias_val) M_ALIAS_VAL=$v ;;
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
keys=fakeai.persona fakeai.rate
alias_name=$W_ALIAS_NAME
alias_val=$W_ALIAS_VAL
hook_hash=$W_HOOK_HASH
stub_hash=$W_STUB_HASH
ctl_hash=$W_CTL_HASH
stubs=$W_STUBS
EOF
}

# write_managed <target_path> <emitter_fn> <prev_hash> <force_flag> <mode_chmod>
# Sets WRITTEN_HASH to the hash tracked in manifest.
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
                echo "fakeai: warning: $(basename "$wm_target") was hand-modified; keeping existing file (use --force to overwrite)" >&2
                WRITTEN_HASH=$wm_prev
                WRITTEN_KEPT=1
                return 0
            fi
            echo "fakeai: warning: overwriting modified $(basename "$wm_target") (--force)" >&2
        fi
    fi

    "$wm_emit" > "$wm_target"
    [ "$wm_exec" -eq 1 ] && chmod +x "$wm_target"
    WRITTEN_HASH=$(git hash-object "$wm_target")
}

cmd_install_global() {
    persona=$1
    force=$2
    hook_dir="$FAKEAI_DIR/hooks"
    manifest="$FAKEAI_DIR/manifest"
    ctl="$FAKEAI_DIR/fakeai.sh"
    target_canon=$(canon_path "$hook_dir")

    cur_raw=$(git config --global --get core.hooksPath 2>/dev/null || true)
    cur_exp=$(git config --global --path --get core.hooksPath 2>/dev/null || true)

    if [ -n "$cur_raw" ]; then
        cur_canon=$(canon_path "$cur_exp")
        if [ "$cur_canon" != "$target_canon" ]; then
            echo "fakeai: global core.hooksPath is already set to '$cur_raw'; refusing to clobber (try --local)" >&2
            exit 1
        fi
        if [ ! -f "$manifest" ]; then
            echo "fakeai: $hook_dir already in core.hooksPath without fakeai manifest; refusing to clobber (try --local)" >&2
            exit 1
        fi
    elif [ ! -f "$manifest" ] && [ -e "$hook_dir/commit-msg" ] && [ "$force" -eq 0 ]; then
        echo "fakeai: $hook_dir/commit-msg exists without fakeai manifest; refusing to clobber (try --local)" >&2
        exit 1
    fi

    if [ -f "$manifest" ]; then
        read_manifest "$manifest"
        W_HOOKSPATH_PREV=$M_HOOKSPATH_PREV
        W_ALIAS_NAME=$M_ALIAS_NAME
        W_ALIAS_VAL=$M_ALIAS_VAL
        prev_hook_hash=$M_HOOK_HASH
        prev_stub_hash=$M_STUB_HASH
        prev_ctl_hash=$M_CTL_HASH
    else
        for stub in $STUB_HOOKS; do
            if [ -e "$hook_dir/$stub" ] && [ "$force" -eq 0 ]; then
                echo "fakeai: $hook_dir/$stub exists without fakeai manifest; refusing to clobber (try --local)" >&2
                exit 1
            fi
        done
        W_HOOKSPATH_PREV=UNSET
        W_ALIAS_NAME=NONE
        W_ALIAS_VAL=""
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

    git config --global core.hooksPath "$hook_dir"
    git config --global fakeai.persona "$persona"
    if ! git config --global --get fakeai.rate >/dev/null 2>&1; then
        git config --global fakeai.rate 1
    fi

    W_MODE=global
    W_HOOKS_DIR=$(canon_path "$hook_dir")
    W_PERSONA=$persona
    write_manifest "$manifest"

    if [ "$FAKEAI_DIR" = "$HOME/.config/fakeai" ]; then
        verify_cmd="sh ~/.config/fakeai/fakeai.sh status"
    else
        verify_cmd="sh $FAKEAI_DIR/fakeai.sh status"
    fi
    printf 'fakeai: installed %s (global)\nverify: %s\n' "$persona" "$verify_cmd"
}

cmd_install_local() {
    persona=$1
    force=$2
    common=$(git rev-parse --git-common-dir 2>/dev/null) || {
        echo "fakeai: --local requires running inside a git repository" >&2
        exit 1
    }
    common_abs=$(canon_path "$common")

    g_hp=$(git config --global --get core.hooksPath 2>/dev/null || true)
    l_hp=$(git config --local --get core.hooksPath 2>/dev/null || true)
    if [ -n "$g_hp" ] || [ -n "$l_hp" ]; then
        echo "fakeai: core.hooksPath is already set; --local hooks would be bypassed" >&2
        exit 1
    fi

    hook_dir="$common_abs/hooks"
    manifest="$common_abs/fakeai-manifest"
    if [ ! -f "$manifest" ] && [ -e "$hook_dir/commit-msg" ] && [ "$force" -eq 0 ]; then
        echo "fakeai: foreign $hook_dir/commit-msg exists; pass --force to overwrite" >&2
        exit 1
    fi

    if [ -f "$manifest" ]; then
        read_manifest "$manifest"
        prev_hook_hash=$M_HOOK_HASH
    else
        prev_hook_hash=NONE
    fi

    mkdir -p "$hook_dir"
    write_managed "$hook_dir/commit-msg" emit_hook "$prev_hook_hash" "$force" 1
    W_HOOK_HASH=$WRITTEN_HASH

    git config --local fakeai.persona "$persona"
    if ! git config --local --get fakeai.rate >/dev/null 2>&1; then
        git config --local fakeai.rate 1
    fi

    W_MODE=local
    W_HOOKS_DIR=$(canon_path "$hook_dir")
    W_HOOKSPATH_PREV=UNSET
    W_PERSONA=$persona
    W_ALIAS_NAME=NONE
    W_ALIAS_VAL=""
    W_STUB_HASH=NONE
    W_CTL_HASH=NONE
    W_STUBS=NONE
    write_manifest "$manifest"

    printf 'fakeai: installed %s (local)\nverify: git config --local fakeai.persona\n' "$persona"
}

LOCAL=0
FORCE=0
POS1=""
POS2=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --local) LOCAL=1 ;;
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
        [ "$LOCAL" -eq 0 ] && [ "$FORCE" -eq 0 ] || { usage; exit 2; }
        cmd_show "$POS2"
        ;;
    "")
        [ -n "$POS2" ] && { usage; exit 2; }
        if [ "$LOCAL" -eq 1 ]; then
            cmd_install_local claude "$FORCE"
        else
            cmd_install_global claude "$FORCE"
        fi
        ;;
    claude|copilot|codex|cursor|aider|devin)
        [ -n "$POS2" ] && { usage; exit 2; }
        if [ "$LOCAL" -eq 1 ]; then
            cmd_install_local "$POS1" "$FORCE"
        else
            cmd_install_global "$POS1" "$FORCE"
        fi
        ;;
    status|off)
        [ -n "$POS2" ] && { usage; exit 2; }
        if [ "$LOCAL" -eq 1 ]; then
            emit_ctl | FAKEAI_DIR="$FAKEAI_DIR" sh -s -- --local "$POS1"
        else
            emit_ctl | FAKEAI_DIR="$FAKEAI_DIR" sh -s -- "$POS1"
        fi
        ;;
    *)
        usage
        exit 2
        ;;
esac
