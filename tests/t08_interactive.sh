#!/bin/sh
# Task 8b: Interactive toggle picker via FAKEAUTHOR_TTY (install.sh and git fakeauthor).

set -eu
. "$(dirname "$0")/lib.sh"

# 1. Fresh install outside a repo with Enter (\n) installs default claude globally
new_sandbox
printf '\n' > "$SANDBOX/in1"
out1=$(cd "$SANDBOX" && FAKEAUTHOR_TTY="$SANDBOX/in1" sh "$INSTALL_SH")
assert_contains "Saved: claude (global)" "$out1" "outside repo Enter installs claude globally"
assert_eq claude "$(git config --global fakeauthor.persona)" "global persona saved as claude"

# 2. Fresh install inside a repo choosing local (2), toggling all (a), and saving (Enter)
new_sandbox
printf '2\na\n\n' > "$SANDBOX/in2"
out2=$(cd "$REPO" && FAKEAUTHOR_TTY="$SANDBOX/in2" sh "$INSTALL_SH")
assert_contains "Saved: claude,copilot,codex,cursor,aider (local)" "$out2" "local interactive 'a' saves all 5 co-authors"
assert_eq yes "$([ -f "$REPO/.git/fakeauthor-manifest" ] && echo yes)" "local manifest created interactively"
assert_eq unset "$(git config --global --get core.hooksPath 2>/dev/null || echo unset)" "local interactive leaves global untouched"

echo "x" > "$REPO/x.txt"
git -C "$REPO" add x.txt
git -C "$REPO" commit -m "all coauthors" >/dev/null
all_tr=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
assert_eq 5 "$(printf '%s\n' "$all_tr" | wc -l)" "local interactive commit gets all 5 trailers"

# 3. Re-running git fakeauthor inside a globally installed repo: repo-only (1) toggles claude off and codex on
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
new_repo "$SANDBOX/repo2"
printf '1\n1,3\n\n' > "$SANDBOX/in3"
out3=$(cd "$REPO" && FAKEAUTHOR_TTY="$SANDBOX/in3" git fakeauthor)
assert_contains "Saved: codex (this repo)" "$out3" "git fakeauthor saves repo-only override"
assert_eq codex "$(git -C "$REPO" config --local --get fakeauthor.persona)" "repo1 local persona is codex"
assert_eq claude "$(git config --global --get fakeauthor.persona)" "global persona stays claude"

echo "r1" > "$REPO/r1.txt"
git -C "$REPO" add r1.txt
git -C "$REPO" commit -m "repo1 codex" >/dev/null
assert_eq "Co-authored-by: Codex <noreply@openai.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "repo1 commit uses Codex"

echo "r2" > "$SANDBOX/repo2/r2.txt"
git -C "$SANDBOX/repo2" add r2.txt
git -C "$SANDBOX/repo2" commit -m "repo2 claude" >/dev/null
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$SANDBOX/repo2" log -1 --pretty=%\(trailers\))" "sibling repo2 keeps global Claude"

# 4. Re-running git fakeauthor choosing global (2) and toggling 6 (devin) creates alias.devin
printf '2\n6\n\n' > "$SANDBOX/in4"
out4=$(cd "$REPO" && FAKEAUTHOR_TTY="$SANDBOX/in4" git fakeauthor)
assert_contains "Saved: claude,devin (global)" "$out4" "global picker saves claude,devin"
assert_eq yes "$(git config --global --get alias.devin >/dev/null 2>&1 && echo yes || echo no)" "interactive picker creates alias.devin"

# 5. Pressing q cancels cleanly with zero writes
new_sandbox
printf 'q\n' > "$SANDBOX/in5"
out5=$(cd "$SANDBOX" && FAKEAUTHOR_TTY="$SANDBOX/in5" sh "$INSTALL_SH")
assert_contains "Cancelled" "$out5" "q prints Cancelled"
assert_eq no "$([ -e "$HOME/.local/share/fakeauthor" ] && echo yes || echo no)" "q performs zero writes"

# 6. Clearing all (n) then Enter warns on empty selection, then 1,3 + Enter saves claude,codex
new_sandbox
printf 'n\n\n1,3\n\n' > "$SANDBOX/in6"
out6=$(cd "$SANDBOX" && FAKEAUTHOR_TTY="$SANDBOX/in6" sh "$INSTALL_SH")
assert_contains "Select at least one persona" "$out6" "empty selection prompts user again"
assert_contains "Saved: claude,codex (global)" "$out6" "subsequent 1,3 saves claude,codex"
assert_eq "claude,codex" "$(git config --global fakeauthor.persona)" "global persona equals claude,codex"
