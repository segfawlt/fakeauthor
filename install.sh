#!/bin/sh
# fakeai — fake AI co-author trailers for git. Parody; not affiliated with any vendor.

set -eu

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

case "${1:-}" in
    show)
        shift
        cmd_show "$@"
        ;;
    *)
        usage
        exit 2
        ;;
esac
