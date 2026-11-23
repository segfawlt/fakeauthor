#!/bin/sh
# Task 4: Hook guards and knobs (rate, fakeauthor.off, NO_FAKEAUTHOR, CRLF, amend, -v, merge/squash).

set -eu
. "$(dirname "$0")/lib.sh"

new_sandbox
sh "$INSTALL_SH" claude >/dev/null

echo "init" > "$REPO/init.txt"
git -C "$REPO" add init.txt
git -C "$REPO" commit -m "init" >/dev/null

# 1. fakeauthor.rate = 0, 1, and invalid "foo"
git -C "$REPO" config fakeauthor.rate 0
echo "r0" > "$REPO/r0.txt"
git -C "$REPO" add r0.txt
git -C "$REPO" commit -m "rate 0" >/dev/null
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "rate=0 skips trailer"

git -C "$REPO" config fakeauthor.rate 1
echo "r1" > "$REPO/r1.txt"
git -C "$REPO" add r1.txt
git -C "$REPO" commit -m "rate 1" >/dev/null
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "rate=1 adds trailer"

git -C "$REPO" config fakeauthor.rate foo
echo "rfoo" > "$REPO/rfoo.txt"
git -C "$REPO" add rfoo.txt
git -C "$REPO" commit -m "rate foo" >/dev/null
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "invalid rate=foo skips cleanly"
git -C "$REPO" config --unset fakeauthor.rate

# 2. Repo-local fakeauthor.off true skips only in that repo; global true + repo false opt-in; invalid boolean commits cleanly
new_repo "$SANDBOX/repo2"
git -C "$REPO" config fakeauthor.off true
echo "off1" > "$REPO/off1.txt"
git -C "$REPO" add off1.txt
git -C "$REPO" commit -m "repo1 off" >/dev/null
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "repo-local fakeauthor.off=true skips"

echo "sib" > "$SANDBOX/repo2/sib.txt"
git -C "$SANDBOX/repo2" add sib.txt
git -C "$SANDBOX/repo2" commit -m "sibling on" >/dev/null
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$SANDBOX/repo2" log -1 --pretty=%\(trailers\))" "sibling repo unaffected by repo-local off"

git config --global fakeauthor.off true
git -C "$REPO" config fakeauthor.off false
echo "optin" > "$REPO/optin.txt"
git -C "$REPO" add optin.txt
git -C "$REPO" commit -m "repo opt-in" >/dev/null
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "repo-local false overrides global true"
git config --global --unset fakeauthor.off

git -C "$REPO" config fakeauthor.off maybe
echo "maybe" > "$REPO/maybe.txt"
git -C "$REPO" add maybe.txt
git -C "$REPO" commit -m "invalid off maybe" >/dev/null
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "invalid fakeauthor.off=maybe commits cleanly with trailer"
git -C "$REPO" config --unset fakeauthor.off

# 3. NO_FAKEAUTHOR env var (1 and true skip; 0 does not)
echo "e1" > "$REPO/e1.txt"
git -C "$REPO" add e1.txt
NO_FAKEAUTHOR=1 git -C "$REPO" commit -m "env 1" >/dev/null
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "NO_FAKEAUTHOR=1 skips"

echo "et" > "$REPO/et.txt"
git -C "$REPO" add et.txt
NO_FAKEAUTHOR=true git -C "$REPO" commit -m "env true" >/dev/null
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "NO_FAKEAUTHOR=true skips"

echo "e0" > "$REPO/e0.txt"
git -C "$REPO" add e0.txt
NO_FAKEAUTHOR=0 git -C "$REPO" commit -m "env 0" >/dev/null
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "NO_FAKEAUTHOR=0 does not skip"

# 4. CRLF -F message files (plain and with existing Signed-off-by)
printf 'crlf subject\r\n\r\nbody line\r\n' > "$SANDBOX/crlf1.txt"
echo "c1" > "$REPO/c1.txt"
git -C "$REPO" add c1.txt
git -C "$REPO" commit -F "$SANDBOX/crlf1.txt" >/dev/null
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "CRLF -F plain message produces valid trailer"

printf 'crlf signed\r\n\r\nSigned-off-by: Alice <a@example.com>\r\n' > "$SANDBOX/crlf2.txt"
echo "c2" > "$REPO/c2.txt"
git -C "$REPO" add c2.txt
git -C "$REPO" commit -F "$SANDBOX/crlf2.txt" >/dev/null
trailers=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
assert_contains "Signed-off-by: Alice <a@example.com>" "$trailers" "CRLF -F preserves Signed-off-by"
assert_contains "Co-Authored-By: Claude <noreply@anthropic.com>" "$trailers" "CRLF -F appends Co-Authored-By"

# 5. git commit --amend --no-edit dupe guard
echo "am" > "$REPO/am.txt"
git -C "$REPO" add am.txt
git -C "$REPO" commit --amend --no-edit >/dev/null
count=$(git -C "$REPO" log -1 --pretty=%B | grep -c "Co-Authored-By: Claude <noreply@anthropic.com>")
assert_eq 1 "$count" "amend --no-edit does not duplicate trailer"

# 6. git commit -v with GIT_EDITOR=true and core.commentChar=; still aborts
git -C "$REPO" config core.commentChar ';'
echo "cv" > "$REPO/cv.txt"
git -C "$REPO" add cv.txt
assert_fails "commit -v empty editor with commentChar=; aborts" \
    env GIT_EDITOR=true git -C "$REPO" commit -v
git -C "$REPO" reset -q HEAD cv.txt
git -C "$REPO" config --unset core.commentChar

# 7. merge --no-commit --no-ff and merge --squash skip trailer
git -C "$REPO" checkout -q -b br1
echo "br1" > "$REPO/br1.txt"
git -C "$REPO" add br1.txt
git -C "$REPO" commit -m "br1 commit" >/dev/null
git -C "$REPO" checkout -q main
echo "main1" > "$REPO/main1.txt"
git -C "$REPO" add main1.txt
git -C "$REPO" commit -m "main1 commit" >/dev/null
git -C "$REPO" merge --no-commit --no-ff br1 >/dev/null
git -C "$REPO" commit -m "merge br1" >/dev/null
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "merge commit skips trailer"

git -C "$REPO" checkout -q -b br2
echo "br2" > "$REPO/br2.txt"
git -C "$REPO" add br2.txt
git -C "$REPO" commit -m "br2 commit" >/dev/null
git -C "$REPO" checkout -q main
git -C "$REPO" merge --squash br2 >/dev/null 2>&1
git -C "$REPO" commit -m "squash br2" >/dev/null
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "squash commit skips trailer"
