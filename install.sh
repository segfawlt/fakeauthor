#!/bin/sh
# fakeai — fake AI co-author trailers for git. Parody; not affiliated with any vendor.

set -eu

FAKEAI_DIR="${FAKEAI_DIR:-$HOME/.config/fakeai}"

usage() {
    cat >&2 <<'EOF'
usage: sh install.sh [--local] [--force] [persona|off|status|show <persona>]
EOF
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

cmd_install() {
    persona=$1
    hook_dir="$FAKEAI_DIR/hooks"
    mkdir -p "$hook_dir"
    emit_hook > "$hook_dir/commit-msg"
    chmod +x "$hook_dir/commit-msg"
    git config --global core.hooksPath "$hook_dir"
    git config --global fakeai.persona "$persona"
    printf 'fakeai: installed %s\nverify: sh %s/fakeai.sh status\n' "$persona" "$FAKEAI_DIR"
}

case "${1:-}" in
    show)
        shift
        cmd_show "$@"
        ;;
    claude|copilot|codex|cursor|aider|devin)
        cmd_install "$1"
        ;;
    *)
        usage
        exit 2
        ;;
esac
