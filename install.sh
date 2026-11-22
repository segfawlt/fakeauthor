#!/bin/sh
# fakeai — fake AI co-author trailers for git. Parody; not affiliated with any vendor.

set -eu

FAKEAI_DIR="${FAKEAI_DIR:-$HOME/.config/fakeai}"

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
    exit 0
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

emit_ctl() {
    cat <<'EOF'
#!/bin/sh
# fakeai offline control CLI (status / off)
set -eu
echo "fakeai: control CLI stub"
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

    if [ -f "$wm_target" ] && [ -n "$wm_prev" ] && [ "$wm_prev" != "NONE" ]; then
        wm_cur=$(git hash-object "$wm_target" 2>/dev/null || true)
        if [ "$wm_cur" != "$wm_prev" ]; then
            if [ "$wm_force" -eq 0 ]; then
                echo "fakeai: warning: $(basename "$wm_target") was hand-modified; keeping existing file (use --force to overwrite)" >&2
                WRITTEN_HASH=$wm_prev
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
        W_STUB_HASH=$M_STUB_HASH
        W_STUBS=$M_STUBS
        prev_hook_hash=$M_HOOK_HASH
        prev_ctl_hash=$M_CTL_HASH
    else
        W_HOOKSPATH_PREV=UNSET
        W_ALIAS_NAME=NONE
        W_ALIAS_VAL=""
        W_STUB_HASH=NONE
        W_STUBS=NONE
        prev_hook_hash=NONE
        prev_ctl_hash=NONE
    fi

    mkdir -p "$hook_dir"
    write_managed "$hook_dir/commit-msg" emit_hook "$prev_hook_hash" "$force" 1
    W_HOOK_HASH=$WRITTEN_HASH
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
