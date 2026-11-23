#!/bin/sh
# Task 3: commit-msg hook appends single and multi-co-author persona trailers.

set -eu
. "$(dirname "$0")/lib.sh"

new_sandbox

sh "$INSTALL_SH" claude >/dev/null
hook="$HOME/.local/share/fakeauthor/hooks/commit-msg"

assert_eq yes "$([ -f "$hook" ] && echo yes)" "hook file exists under ~/.local/share/fakeauthor"
assert_eq yes "$([ -x "$hook" ] && echo yes)" "hook file is executable"
assert_contains "# fakeauthor hook v1" "$(cat "$hook")" "hook carries version marker"
assert_zero_cr "$hook" "hook contains zero CR bytes"

echo "a" > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -m "x" >/dev/null
msg=$(git -C "$REPO" log -1 --pretty=%B)
assert_eq "x

Co-Authored-By: Claude <noreply@anthropic.com>" "$msg" "basic -m commit appends claude trailer"

# Runtime single persona switching without reinstalling
i=0
for p in claude copilot codex cursor aider; do
    i=$((i + 1))
    git config --global fakeauthor.persona "$p"
    echo "$i" > "$REPO/p_$p.txt"
    git -C "$REPO" add "p_$p.txt"
    git -C "$REPO" commit -m "persona $p" >/dev/null
    expected=$(sh "$INSTALL_SH" show "$p")
    trailers=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
    assert_eq "$expected" "$trailers" "runtime switch to $p matches show $p"
done

# Multi-co-author comma list and 'all' keyword
git config --global fakeauthor.persona "claude,copilot,codex"
echo "m1" > "$REPO/m1.txt"
git -C "$REPO" add m1.txt
git -C "$REPO" commit -m "committee" >/dev/null
trailers=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
assert_contains "Co-Authored-By: Claude <noreply@anthropic.com>" "$trailers" "multi includes claude"
assert_contains "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" "$trailers" "multi includes copilot"
assert_contains "Co-authored-by: Codex <noreply@openai.com>" "$trailers" "multi includes codex"
assert_eq 3 "$(printf '%s\n' "$trailers" | wc -l)" "multi adds exact 3 trailers"

# Amend of multi-co-author commit must not duplicate any trailer
echo "m1b" >> "$REPO/m1.txt"
git -C "$REPO" add m1.txt
git -C "$REPO" commit --amend --no-edit >/dev/null
trailers_am=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
assert_eq "$trailers" "$trailers_am" "amend preserves exact multi-co-author trailers without duplicates"

# 'all' expands to all 5 co-author personas and counts in git shortlog
git config --global fakeauthor.persona all
echo "all" > "$REPO/all.txt"
git -C "$REPO" add all.txt
git -C "$REPO" commit -m "everyone helped" >/dev/null
all_trailers=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
assert_eq 5 "$(printf '%s\n' "$all_trailers" | wc -l)" "all expands to 5 co-author trailers"
sl=$(git -C "$REPO" shortlog -s --group=trailer:co-authored-by HEAD~1..HEAD)
assert_contains "Claude" "$sl" "shortlog counts Claude"
assert_contains "Copilot" "$sl" "shortlog counts Copilot"
assert_contains "Codex" "$sl" "shortlog counts Codex"
assert_contains "Cursor" "$sl" "shortlog counts Cursor"
assert_contains "aider (sonnet)" "$sl" "shortlog counts aider"

# Reset to claude for remaining checks
git config --global fakeauthor.persona claude

# Human Co-authored-by coexists with fakeauthor trailer
echo "pair" > "$REPO/pair.txt"
git -C "$REPO" add pair.txt
git -C "$REPO" commit -m "pair work" -m "Co-authored-by: Alice <alice@example.com>" >/dev/null
pair_trailers=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
assert_contains "Co-authored-by: Alice <alice@example.com>" "$pair_trailers" "keeps human co-author"
assert_contains "Co-Authored-By: Claude <noreply@anthropic.com>" "$pair_trailers" "adds Claude alongside human co-author"

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

# Partial fakeauthor.name and fakeauthor.email overrides preserve preset trailer key
git -C "$REPO" config fakeauthor.name "Fake Bot"
echo "ov1" > "$REPO/ov1.txt"
git -C "$REPO" add ov1.txt
git -C "$REPO" commit -m "override name" >/dev/null
assert_eq "Co-Authored-By: Fake Bot <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "partial fakeauthor.name override"
git -C "$REPO" config --unset fakeauthor.name

git -C "$REPO" config fakeauthor.email "bot@example.com"
echo "ov2" > "$REPO/ov2.txt"
git -C "$REPO" add ov2.txt
git -C "$REPO" commit -m "override email" >/dev/null
assert_eq "Co-Authored-By: Claude <bot@example.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "partial fakeauthor.email override"
git -C "$REPO" config --unset fakeauthor.email

# claude,devin emits only claude trailer (devin skips trailer)
git config --global fakeauthor.persona "claude,devin"
echo "cd1" > "$REPO/cd1.txt"
git -C "$REPO" add cd1.txt
git -C "$REPO" commit -m "claude plus devin" >/dev/null
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "claude,devin emits only claude trailer"

# Devin and unknown persona skip by default, emit Co-authored-by only when both overrides are set
for p in devin unknown-ai; do
    git config --global fakeauthor.persona "$p"
    echo "no_${p}" > "$REPO/no_${p}.txt"
    git -C "$REPO" add "no_${p}.txt"
    git -C "$REPO" commit -m "skip $p" >/dev/null
    assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "$p without full override skips trailer"

    git -C "$REPO" config fakeauthor.name "Solo"
    echo "half_${p}" > "$REPO/half_${p}.txt"
    git -C "$REPO" add "half_${p}.txt"
    git -C "$REPO" commit -m "half $p" >/dev/null
    assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "$p with partial override skips trailer"

    git -C "$REPO" config fakeauthor.email "solo@example.com"
    echo "full_${p}" > "$REPO/full_${p}.txt"
    git -C "$REPO" add "full_${p}.txt"
    git -C "$REPO" commit -m "full $p" >/dev/null
    assert_eq "Co-authored-by: Solo <solo@example.com>" \
        "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "$p with both overrides emits Co-authored-by"

    git -C "$REPO" config --unset fakeauthor.name
    git -C "$REPO" config --unset fakeauthor.email
done
