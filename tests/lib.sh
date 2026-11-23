# tests/lib.sh — sandbox and assertion helpers for the fakeauthor suite.
# Sourced by tests/t*.sh; POSIX sh, safe under set -eu.

HOST_HOME=$HOME
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALL_SH="$ROOT_DIR/install.sh"
export INSTALL_SH

SANDBOX=
REPO=
_SANDBOXES=

_cleanup_sandboxes() {
    cd "$ROOT_DIR" 2>/dev/null || cd /
    for sb in $_SANDBOXES; do
        rm -rf "$sb"
    done
}
trap _cleanup_sandboxes EXIT

new_repo() {
    mkdir -p "$1"
    git -C "$1" init -b main >/dev/null 2>&1
    git -C "$1" config user.name user
    git -C "$1" config user.email user@example.com
}

new_sandbox() {
    SANDBOX=$(mktemp -d)
    _SANDBOXES="$_SANDBOXES $SANDBOX"
    mkdir -p "$SANDBOX/home" "$SANDBOX/xdg" "$SANDBOX/repo"
    HOME=$SANDBOX/home
    XDG_CONFIG_HOME=$SANDBOX/xdg
    GIT_CONFIG_NOSYSTEM=1
    export HOME XDG_CONFIG_HOME GIT_CONFIG_NOSYSTEM
    unset GIT_CONFIG_GLOBAL FAKEAUTHOR_DIR NO_FAKEAUTHOR _FAKEAUTHOR_CHAINED FAKEAUTHOR_TTY
    new_repo "$SANDBOX/repo"
    REPO=$SANDBOX/repo
    cd "$SANDBOX"
}

assert_eq() {
    if [ "$1" != "$2" ]; then
        echo "FAIL: $3" >&2
        echo "  expected: $1" >&2
        echo "  actual:   $2" >&2
        exit 1
    fi
}

assert_contains() {
    case $2 in
        *"$1"*) ;;
        *)
            echo "FAIL: $3: expected to contain: $1" >&2
            echo "  got: $2" >&2
            exit 1
            ;;
    esac
}

assert_not_contains() {
    case $2 in
        *"$1"*)
            echo "FAIL: $3: expected NOT to contain: $1" >&2
            exit 1
            ;;
    esac
}

assert_fails() {
    label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        echo "FAIL: $label: command unexpectedly succeeded: $*" >&2
        exit 1
    fi
}

assert_zero_cr() {
    if [ "$(LC_ALL=C tr -cd '\r' < "$1" | wc -c)" -ne 0 ]; then
        echo "FAIL: $2: CR bytes found in $1" >&2
        exit 1
    fi
}
