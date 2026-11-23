#!/bin/sh
# Task 9: LF-only repo scripts and generated files, no bashisms, no legacy brand refs, CR guard.

set -eu
. "$(dirname "$0")/lib.sh"

# .gitattributes exists and pins LF for shell scripts
assert_eq yes "$([ -f "$ROOT_DIR/.gitattributes" ] && echo yes)" ".gitattributes exists"
assert_contains "*.sh text eol=lf" "$(cat "$ROOT_DIR/.gitattributes")" ".gitattributes pins LF for .sh files"

# Repo shell scripts contain zero CR bytes
for f in "$INSTALL_SH" "$ROOT_DIR"/tests/*.sh; do
    assert_zero_cr "$f" "repo script has no CR bytes: $f"
done

# Global install generates only LF files under ~/.local/share/fakeauthor
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
fd="$HOME/.local/share/fakeauthor"
assert_zero_cr "$fd/hooks/commit-msg" "generated commit-msg has no CR bytes"
for stub in applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit \
    prepare-commit-msg post-commit pre-rebase post-checkout post-merge pre-push \
    post-rewrite sendemail-validate; do
    assert_zero_cr "$fd/hooks/$stub" "generated stub has no CR bytes: $stub"
done
assert_zero_cr "$fd/fakeauthor.sh" "generated fakeauthor.sh has no CR bytes"
assert_zero_cr "$fd/manifest" "generated manifest has no CR bytes"

# --local install generates only LF files
new_sandbox
(cd "$REPO" && sh "$INSTALL_SH" --local copilot) >/dev/null
assert_zero_cr "$REPO/.git/hooks/commit-msg" "local commit-msg has no CR bytes"
assert_zero_cr "$REPO/.git/fakeauthor.sh" "local fakeauthor.sh has no CR bytes"
assert_zero_cr "$REPO/.git/fakeauthor-manifest" "local fakeauthor-manifest has no CR bytes"

# No bashisms or leftover old brand names in shipped or test shell code
cr_pat=$(printf '$%s' "'\\\\r'")
old_name=$(printf 'fake%s' 'ai')
for f in "$INSTALL_SH" "$ROOT_DIR"/tests/*.sh; do
    if grep -q "$cr_pat" "$f"; then
        echo "FAIL: ANSI-C quoting bashism found in $f" >&2
        exit 1
    fi
    if grep -q '\[\[' "$f"; then
        echo "FAIL: double bracket bashism found in $f" >&2
        exit 1
    fi
    if grep -qi "$old_name" "$f"; then
        echo "FAIL: leftover $old_name reference found in $f" >&2
        exit 1
    fi
done

# Byte guard aborts when the installer itself carries CR bytes (CRLF checkout)
new_sandbox
poison="$SANDBOX/poison.sh"
awk '
    /<<.EOF./ || /<<.MAN./ { inh = 1; print; next }
    inh && (/^EOF$/ || /^MAN$/) { inh = 0; print; next }
    inh { print $0 "\r"; next }
    { print }
' "$INSTALL_SH" > "$poison"
assert_fails "CR-poisoned installer aborts" sh "$poison" claude

# shellcheck with the sh dialect when installed
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -s sh "$INSTALL_SH" "$ROOT_DIR"/tests/*.sh
fi
