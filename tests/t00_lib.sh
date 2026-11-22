#!/bin/sh
# Self-test for tests/lib.sh: assertions and sandbox isolation.

set -eu
. "$(dirname "$0")/lib.sh"

assert_eq 1 1 "assert_eq accepts equal values"
assert_contains "abc" "xabcx" "assert_contains finds needle"
assert_not_contains "zz" "xabcx" "assert_not_contains rejects absent needle"
assert_fails "assert_fails accepts failing command" false

new_sandbox

assert_eq yes "$([ -d "$REPO/.git" ] && echo yes)" "sandbox repo has .git"
assert_eq "$SANDBOX/home" "$HOME" "HOME points into sandbox home"
assert_eq yes "$([ "$HOME" != "$HOST_HOME" ] && echo yes)" "HOME differs from host home"

git config --global test.k v
assert_eq yes "$([ -f "$SANDBOX/home/.gitconfig" ] && echo yes)" "git config --global writes into sandbox home"
assert_eq v "$(git config --global test.k)" "global config value round-trips"
