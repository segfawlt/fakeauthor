#!/bin/sh
# Task 8: Author mode (git <persona> alias), multi-persona switching, collisions, and Devin.

set -eu
. "$(dirname "$0")/lib.sh"

# 1. claude install creates git claude alias (author mode, NO_FAKEAUTHOR=1 -> no trailer)
new_sandbox
sh "$INSTALL_SH" claude >/dev/null

echo "a" > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" claude commit -m "authored by claude" >/dev/null
assert_eq "Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --format='%an <%ae>')" "git claude sets author identity"
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "git claude skips trailer via NO_FAKEAUTHOR=1"

# 2. Subdirectory pathspec works via GIT_PREFIX preservation
mkdir -p "$REPO/sub/dir"
echo "sub" > "$REPO/sub/dir/subfile.txt"
git -C "$REPO" add sub/dir/subfile.txt
(cd "$REPO/sub/dir" && git claude commit subfile.txt -m "from subdir" >/dev/null)
assert_eq "Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --format='%an <%ae>')" "git claude works from nested subdir"

# 3. Multi-persona 'claude,codex' creates both aliases; switching to 'cursor' removes both; uninstall removes cursor
sh "$INSTALL_SH" "claude,codex" >/dev/null
assert_eq yes "$(git config --global --get alias.claude >/dev/null 2>&1 && echo yes || echo no)" "multi creates alias.claude"
assert_eq yes "$(git config --global --get alias.codex >/dev/null 2>&1 && echo yes || echo no)" "multi creates alias.codex"

sh "$INSTALL_SH" cursor >/dev/null
assert_eq unset "$(git config --global --get alias.claude 2>/dev/null || echo unset)" "switch removes old alias.claude"
assert_eq unset "$(git config --global --get alias.codex 2>/dev/null || echo unset)" "switch removes old alias.codex"
assert_eq yes "$(git config --global --get alias.cursor >/dev/null 2>&1 && echo yes || echo no)" "switch creates alias.cursor"

git fakeauthor uninstall >/dev/null
assert_eq unset "$(git config --global --get alias.cursor 2>/dev/null || echo unset)" "uninstall removes alias.cursor"

# 4. Devin install (global and --local): normal commit adds no trailer; git devin sets Devin bot author
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

# Local devin alias works too
new_sandbox
(cd "$REPO" && sh "$INSTALL_SH" --local devin >/dev/null)
echo "dl" > "$REPO/dl.txt"
git -C "$REPO" add dl.txt
git -C "$REPO" devin commit -m "local devin" >/dev/null
assert_eq "Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>" \
    "$(git -C "$REPO" log -1 --format='%an <%ae>')" "--local git devin works"
(cd "$REPO" && git fakeauthor uninstall >/dev/null)
assert_eq unset "$(git -C "$REPO" config --local --get alias.devin 2>/dev/null || echo unset)" "--local uninstall cleans alias.devin"

# 5. Colliding foreign alias.claude and alias.fakeauthor are untouched on install and uninstall
new_sandbox
git config --global alias.claude "status --short"
git config --global alias.fakeauthor "log --oneline"
col_out=$(sh "$INSTALL_SH" claude 2>&1)
assert_contains "alias.claude" "$col_out" "collision warns about alias.claude"
assert_contains "alias.fakeauthor" "$col_out" "collision warns about alias.fakeauthor"
assert_contains "fakeauthor.sh status" "$col_out" "fallback verify line shown when alias.fakeauthor collides"
assert_eq "status --short" "$(git config --global --get alias.claude)" "colliding alias.claude untouched on install"
assert_eq "log --oneline" "$(git config --global --get alias.fakeauthor)" "colliding alias.fakeauthor untouched on install"

sh "$INSTALL_SH" uninstall >/dev/null
assert_eq "status --short" "$(git config --global --get alias.claude)" "colliding alias.claude untouched on uninstall"
assert_eq "log --oneline" "$(git config --global --get alias.fakeauthor)" "colliding alias.fakeauthor untouched on uninstall"
