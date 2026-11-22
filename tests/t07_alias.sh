#!/bin/sh
# Task 8: Author mode (git <persona> alias) and Devin persona.

set -eu
. "$(dirname "$0")/lib.sh"

# 1. claude install creates git claude alias (author mode, NO_FAKEAI=1 -> no trailer)
new_sandbox
sh "$INSTALL_SH" claude >/dev/null

echo "a" > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" claude commit -m "authored by claude" >/dev/null
assert_eq "Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --format='%an <%ae>')" "git claude sets author identity"
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "git claude skips trailer via NO_FAKEAI=1"

# 2. Subdirectory pathspec works via GIT_PREFIX preservation
mkdir -p "$REPO/sub/dir"
echo "sub" > "$REPO/sub/dir/subfile.txt"
git -C "$REPO" add sub/dir/subfile.txt
(cd "$REPO/sub/dir" && git claude commit subfile.txt -m "from subdir" >/dev/null)
assert_eq "Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --format='%an <%ae>')" "git claude works from nested subdir"

# 3. Switching claude -> codex -> off removes old alias and cleans up both
sh "$INSTALL_SH" codex >/dev/null
assert_eq unset "$(git config --global --get alias.claude 2>/dev/null || echo unset)" "switch to codex removes alias.claude"
assert_eq yes "$(git config --global --get alias.codex >/dev/null 2>&1 && echo yes || echo no)" "switch to codex creates alias.codex"

sh "$INSTALL_SH" off >/dev/null
assert_eq unset "$(git config --global --get alias.claude 2>/dev/null || echo unset)" "off leaves no alias.claude"
assert_eq unset "$(git config --global --get alias.codex 2>/dev/null || echo unset)" "off removes alias.codex"

# 4. Devin install: normal commit adds no trailer; git devin sets Devin bot author
new_sandbox
sh "$INSTALL_SH" devin >/dev/null
echo "d1" > "$REPO/d1.txt"
git -C "$REPO" add d1.txt
git -C "$REPO" commit -m "normal commit under devin" >/dev/null
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "devin normal commit has no trailer"
assert_eq "user <user@example.com>" \
    "$(git -C "$REPO" log -1 --format='%an <%ae>')" "devin normal commit keeps human author"

echo "d2" > "$REPO/d2.txt"
git -C "$REPO" add d2.txt
git -C "$REPO" devin commit -m "authored by devin" >/dev/null
assert_eq "Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>" \
    "$(git -C "$REPO" log -1 --format='%an <%ae>')" "git devin sets Devin bot author"

# 5. Colliding foreign alias.claude is untouched on install and off
new_sandbox
git config --global alias.claude "status --short"
col_out=$(sh "$INSTALL_SH" claude 2>&1)
assert_contains "alias.claude" "$col_out" "collision warns about alias.claude"
assert_eq "status --short" "$(git config --global --get alias.claude)" "colliding alias untouched on install"

sh "$INSTALL_SH" off >/dev/null
assert_eq "status --short" "$(git config --global --get alias.claude)" "colliding alias untouched on off"
