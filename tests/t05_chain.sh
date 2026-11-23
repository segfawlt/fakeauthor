#!/bin/sh
# Task 6: Chaining all standard client hooks without shadowing.

set -eu
. "$(dirname "$0")/lib.sh"

new_sandbox
sh "$INSTALL_SH" claude >/dev/null

# Verify all 13 stubs were created and are executable
for stub in applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit \
    prepare-commit-msg post-commit pre-rebase post-checkout post-merge pre-push \
    post-rewrite sendemail-validate; do
    assert_eq yes "$([ -x "$HOME/.local/share/fakeauthor/hooks/$stub" ] && echo yes)" "stub $stub executable"
done

echo "init" > "$REPO/init.txt"
git -C "$REPO" add init.txt
git -C "$REPO" commit -m "init" >/dev/null

# (a) Repo commit-msg appending Signed-off-by merges into one trailer block
cat > "$REPO/.git/hooks/commit-msg" <<'EOF'
#!/bin/sh
git interpret-trailers --in-place --trailer "Signed-off-by: Repo Bot <bot@example.com>" "$1"
EOF
chmod +x "$REPO/.git/hooks/commit-msg"

echo "a" > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -m "chain trailers" >/dev/null
trailers=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
assert_contains "Co-Authored-By: Claude <noreply@anthropic.com>" "$trailers" "chained commit keeps fakeauthor trailer"
assert_contains "Signed-off-by: Repo Bot <bot@example.com>" "$trailers" "chained commit runs repo commit-msg trailer"

# (b) Repo commit-msg exiting 1 aborts commit; fixing restores commits
cat > "$REPO/.git/hooks/commit-msg" <<'EOF'
#!/bin/sh
echo "BLOCKED_BY_REPO_COMMIT_MSG" >&2
exit 1
EOF
chmod +x "$REPO/.git/hooks/commit-msg"

echo "b" > "$REPO/b.txt"
git -C "$REPO" add b.txt
assert_fails "failing repo commit-msg aborts commit" git -C "$REPO" commit -m "should fail"

# (c) Every skip path STILL chains to repo commit-msg
git -C "$REPO" config fakeauthor.off true
assert_fails "fakeauthor.off=true still chains to failing repo commit-msg" git -C "$REPO" commit -m "skip off"
git -C "$REPO" config --unset fakeauthor.off

assert_fails "NO_FAKEAUTHOR=1 still chains to failing repo commit-msg" env NO_FAKEAUTHOR=1 git -C "$REPO" commit -m "skip env"

git -C "$REPO" config fakeauthor.rate 0
assert_fails "fakeauthor.rate=0 still chains to failing repo commit-msg" git -C "$REPO" commit -m "skip rate"
git -C "$REPO" config --unset fakeauthor.rate

git config --global fakeauthor.persona devin
assert_fails "devin still chains to failing repo commit-msg" git -C "$REPO" commit -m "skip devin"
git config --global fakeauthor.persona claude

# Fix commit-msg -> commit succeeds again
rm "$REPO/.git/hooks/commit-msg"
git -C "$REPO" commit -m "restored" >/dev/null

# Merge commit with MERGE_HEAD also still chains to repo commit-msg
git -C "$REPO" checkout -q -b br-merge
echo "m1" > "$REPO/m1.txt"
git -C "$REPO" add m1.txt
git -C "$REPO" commit -m "branch commit" >/dev/null
git -C "$REPO" checkout -q main
echo "m2" > "$REPO/m2.txt"
git -C "$REPO" add m2.txt
git -C "$REPO" commit -m "main commit" >/dev/null

printf '#!/bin/sh\necho "MERGE_CHAINED" >&2\nexit 1\n' > "$REPO/.git/hooks/commit-msg"
chmod +x "$REPO/.git/hooks/commit-msg"
git -C "$REPO" merge --no-commit --no-ff br-merge >/dev/null
assert_fails "merge skip still chains to failing repo commit-msg" git -C "$REPO" commit -m "merge br-merge"
git -C "$REPO" merge --abort
rm "$REPO/.git/hooks/commit-msg"

# (d) Repo pre-commit exiting 1 aborts commit after global install
cat > "$REPO/.git/hooks/pre-commit" <<'EOF'
#!/bin/sh
echo "PRE_COMMIT_RAN" >&2
exit 1
EOF
chmod +x "$REPO/.git/hooks/pre-commit"
echo "pc" > "$REPO/pc.txt"
git -C "$REPO" add pc.txt
pc_err=$SANDBOX/pc.err
rc=0
git -C "$REPO" commit -m "blocked by pre-commit" >/dev/null 2>"$pc_err" || rc=$?
assert_eq 1 "$rc" "chained repo pre-commit aborts commit"
assert_contains "PRE_COMMIT_RAN" "$(cat "$pc_err")" "repo pre-commit ran"
rm "$REPO/.git/hooks/pre-commit"
git -C "$REPO" commit -m "after pre-commit removed" >/dev/null

# (e) Repo pre-push reads stdin ref lines and aborts push cleanly
bare="$SANDBOX/remote.git"
git init --bare -b main "$bare" >/dev/null 2>&1
git -C "$REPO" remote add origin "$bare"
cat > "$REPO/.git/hooks/pre-push" <<'EOF'
#!/bin/sh
stdin_data=$(cat)
echo "PRE_PUSH_STDIN:$stdin_data" >&2
exit 1
EOF
chmod +x "$REPO/.git/hooks/pre-push"
pp_err=$SANDBOX/pp.err
rc=0
git -C "$REPO" push origin main >/dev/null 2>"$pp_err" || rc=$?
assert_eq 1 "$rc" "chained repo pre-push aborts push"
assert_contains "PRE_PUSH_STDIN:refs/heads/main" "$(cat "$pp_err")" "pre-push received intact stdin refs"
rm "$REPO/.git/hooks/pre-push"

# (f) Linked git worktree chains to shared common-dir hooks and detects per-worktree MERGE_HEAD
wt="$SANDBOX/wt"
git -C "$REPO" worktree add -q -b wt-br "$wt"
printf '#!/bin/sh\ntouch "%s/wt_hook_ran"\n' "$SANDBOX" > "$REPO/.git/hooks/post-commit"
chmod +x "$REPO/.git/hooks/post-commit"
echo "w1" > "$wt/w1.txt"
git -C "$wt" add w1.txt
git -C "$wt" commit -m "worktree commit" >/dev/null
assert_eq yes "$([ -f "$SANDBOX/wt_hook_ran" ] && echo yes)" "worktree chains to common-dir post-commit hook"
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$wt" log -1 --pretty=%\(trailers\))" "worktree commit adds trailer"

git -C "$wt" merge --no-commit --no-ff br-merge >/dev/null
git -C "$wt" commit -m "worktree merge" >/dev/null
assert_eq "" "$(git -C "$wt" log -1 --pretty=%\(trailers\))" "worktree merge skips trailer via --git-dir"
