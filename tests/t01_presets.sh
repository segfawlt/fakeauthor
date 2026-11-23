#!/bin/sh
# Task 2: Persona preset table (sh install.sh show <persona>).

set -eu
. "$(dirname "$0")/lib.sh"

new_sandbox

assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(sh "$INSTALL_SH" show claude)" "show claude"
assert_eq "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" \
    "$(sh "$INSTALL_SH" show copilot)" "show copilot"
assert_eq "Co-authored-by: Codex <noreply@openai.com>" \
    "$(sh "$INSTALL_SH" show codex)" "show codex"
assert_eq "Co-authored-by: Cursor <cursoragent@cursor.com>" \
    "$(sh "$INSTALL_SH" show cursor)" "show cursor"
assert_eq "Co-authored-by: aider (sonnet) <aider@aider.chat>" \
    "$(sh "$INSTALL_SH" show aider)" "show aider"

err=$SANDBOX/devin.err
rc=0
sh "$INSTALL_SH" show devin >/dev/null 2>"$err" || rc=$?
assert_eq 1 "$rc" "show devin exits 1"
assert_contains "author-mode" "$(cat "$err")" "devin note mentions author-mode"

rc=0
sh "$INSTALL_SH" show nope >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc" "unknown persona exits 1"

rc=0
sh "$INSTALL_SH" show >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc" "missing persona exits 1"

rc=0
sh "$INSTALL_SH" frobnicate >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc" "unknown subcommand exits 2"
