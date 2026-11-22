#!/bin/sh
# Task 3: commit-msg hook appends persona trailers via git interpret-trailers.

set -eu
. "$(dirname "$0")/lib.sh"

new_sandbox

out=$(sh "$INSTALL_SH" claude)
hook="$HOME/.config/fakeai/hooks/commit-msg"

assert_eq yes "$([ -f "$hook" ] && echo yes)" "hook file exists"
assert_eq yes "$([ -x "$hook" ] && echo yes)" "hook file is executable"
assert_contains "# fakeai hook v1" "$(cat "$hook")" "hook carries version marker"
assert_zero_cr "$hook" "hook contains zero CR bytes"

echo "a" > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -m "x" >/dev/null
msg=$(git -C "$REPO" log -1 --pretty=%B)
assert_eq "x

Co-Authored-By: Claude <noreply@anthropic.com>" "$msg" "basic -m commit appends claude trailer"

# Runtime persona switching without reinstalling
i=0
for p in claude copilot codex cursor aider; do
    i=$((i + 1))
    git config --global fakeai.persona "$p"
    echo "$i" > "$REPO/p_$p.txt"
    git -C "$REPO" add "p_$p.txt"
    git -C "$REPO" commit -m "persona $p" >/dev/null
    expected=$(sh "$INSTALL_SH" show "$p")
    trailers=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
    assert_eq "$expected" "$trailers" "runtime switch to $p matches show $p"
done

# Reset to claude for remaining checks
git config --global fakeai.persona claude

# Interactive bare git commit where user types subject on line 1
ed="$SANDBOX/ed.sh"
cat > "$ed" <<'EOF'
#!/bin/sh
sed '1s/^/editor subject/' "$1" > "$1.ed" && mv "$1.ed" "$1"
EOF
chmod +x "$ed"
echo "ed1" > "$REPO/ed1.txt"
git -C "$REPO" add ed1.txt
GIT_EDITOR="$ed" git -C "$REPO" commit >/dev/null
assert_eq "editor subject

Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%B)" "editor commit separates trailer with blank line"
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "editor commit trailer parses cleanly"

# Untouched empty editor must still abort
echo "ed2" > "$REPO/ed2.txt"
git -C "$REPO" add ed2.txt
assert_fails "empty editor still aborts commit" env GIT_EDITOR=true git -C "$REPO" commit
git -C "$REPO" reset -q HEAD ed2.txt

# git commit -s merges into one valid trailer block
echo "s" > "$REPO/s.txt"
git -C "$REPO" add s.txt
git -C "$REPO" commit -s -m "signed commit" >/dev/null
trailers=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
assert_contains "Signed-off-by: user <user@example.com>" "$trailers" "-s preserves Signed-off-by"
assert_contains "Co-Authored-By: Claude <noreply@anthropic.com>" "$trailers" "-s appends Co-Authored-By in same block"

# Prose mentioning Co-authored-by still receives trailer
echo "prose" > "$REPO/prose.txt"
git -C "$REPO" add prose.txt
git -C "$REPO" commit -m "fix: stop stripping Co-authored-by in parser" >/dev/null
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "prose mention does not suppress trailer"

# Partial fakeai.name and fakeai.email overrides preserve preset trailer key
git -C "$REPO" config fakeai.name "Fake Bot"
echo "ov1" > "$REPO/ov1.txt"
git -C "$REPO" add ov1.txt
git -C "$REPO" commit -m "override name" >/dev/null
assert_eq "Co-Authored-By: Fake Bot <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "partial fakeai.name override"
git -C "$REPO" config --unset fakeai.name

git -C "$REPO" config fakeai.email "bot@example.com"
echo "ov2" > "$REPO/ov2.txt"
git -C "$REPO" add ov2.txt
git -C "$REPO" commit -m "override email" >/dev/null
assert_eq "Co-Authored-By: Claude <bot@example.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "partial fakeai.email override"
git -C "$REPO" config --unset fakeai.email

# Devin and unknown persona skip by default, emit Co-authored-by only when both overrides are set
for p in devin unknown-ai; do
    git config --global fakeai.persona "$p"
    echo "no_${p}" > "$REPO/no_${p}.txt"
    git -C "$REPO" add "no_${p}.txt"
    git -C "$REPO" commit -m "skip $p" >/dev/null
    assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "$p without full override skips trailer"

    git -C "$REPO" config fakeai.name "Solo"
    echo "half_${p}" > "$REPO/half_${p}.txt"
    git -C "$REPO" add "half_${p}.txt"
    git -C "$REPO" commit -m "half $p" >/dev/null
    assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "$p with partial override skips trailer"

    git -C "$REPO" config fakeai.email "solo@example.com"
    echo "full_${p}" > "$REPO/full_${p}.txt"
    git -C "$REPO" add "full_${p}.txt"
    git -C "$REPO" commit -m "full $p" >/dev/null
    assert_eq "Co-authored-by: Solo <solo@example.com>" \
        "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "$p with both overrides emits Co-authored-by"

    git -C "$REPO" config --unset fakeai.name
    git -C "$REPO" config --unset fakeai.email
done
