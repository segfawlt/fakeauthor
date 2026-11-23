#!/bin/sh
# Task 5: Manifest state, never-clobber, ~/.local/share/fakeauthor, multi-persona, --local, UX.

set -eu
. "$(dirname "$0")/lib.sh"

# 1. Foreign global core.hooksPath aborts nonzero with zero writes
new_sandbox
foreign="$SANDBOX/foreign-hooks"
mkdir -p "$foreign"
git config --global core.hooksPath "$foreign"
err=$SANDBOX/err1
rc=0
sh "$INSTALL_SH" claude >/dev/null 2>"$err" || rc=$?
assert_eq 1 "$rc" "foreign core.hooksPath aborts with exit 1"
assert_contains "core.hooksPath" "$(cat "$err")" "foreign error mentions core.hooksPath"
assert_eq no "$([ -e "$HOME/.local/share/fakeauthor" ] && echo yes || echo no)" "zero writes on foreign abort"

# 2. Pre-existing $HOME/.local/share/fakeauthor/hooks set as core.hooksPath without manifest aborts
new_sandbox
mkdir -p "$HOME/.local/share/fakeauthor/hooks"
git config --global core.hooksPath "$HOME/.local/share/fakeauthor/hooks"
rc=0
sh "$INSTALL_SH" claude >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc" "existing hooks dir without manifest aborts"
assert_eq no "$([ -f "$HOME/.local/share/fakeauthor/manifest" ] && echo yes || echo no)" "manifest absent after unowned dir abort"

# 3. Non-interactive no-arg defaults to claude, writes manifest + fakeauthor.sh + alias.fakeauthor, <=5 lines
new_sandbox
out=$(sh "$INSTALL_SH")
lines=$(printf '%s\n' "$out" | wc -l)
assert_eq yes "$([ "$lines" -le 5 ] && echo yes)" "install output is <= 5 lines ($lines)"
last_line=$(printf '%s\n' "$out" | tail -n 1)
assert_eq "verify: git fakeauthor status" "$last_line" "output ends with verify: git fakeauthor status"

manifest="$HOME/.local/share/fakeauthor/manifest"
ctl="$HOME/.local/share/fakeauthor/fakeauthor.sh"
hook="$HOME/.local/share/fakeauthor/hooks/commit-msg"
assert_eq yes "$([ -f "$manifest" ] && echo yes)" "manifest created"
assert_eq yes "$([ -x "$ctl" ] && echo yes)" "offline fakeauthor.sh created and executable"
assert_eq claude "$(git config --global fakeauthor.persona)" "no-arg defaults to claude"
assert_eq 1 "$(git config --global fakeauthor.rate)" "initial install sets fakeauthor.rate=1"
assert_contains "hooksPath_prev=UNSET" "$(cat "$manifest")" "manifest records hooksPath_prev=UNSET"
assert_contains "persona=claude" "$(cat "$manifest")" "manifest records persona=claude"

# 4. Multi-persona CLI install ('all' and comma list) + reinstall preserves hooksPath_prev & custom rate
git config --global fakeauthor.rate 0.25
sh "$INSTALL_SH" all >/dev/null
assert_eq "claude,copilot,codex,cursor,aider" "$(git config --global fakeauthor.persona)" "all expands canonically"
assert_eq 0.25 "$(git config --global fakeauthor.rate)" "reinstall preserves custom fakeauthor.rate=0.25"
assert_contains "hooksPath_prev=UNSET" "$(cat "$manifest")" "reinstall preserves original hooksPath_prev"

sh "$INSTALL_SH" "codex,claude" >/dev/null
assert_eq "claude,codex" "$(git config --global fakeauthor.persona)" "comma list installs normalized multi-persona"

# 5. Hand-modified hook is warned and preserved without --force, overwritten with --force
printf '# custom edit\n' >> "$hook"
warn_out=$(sh "$INSTALL_SH" aider 2>&1)
assert_contains "modified" "$warn_out" "hand-modified hook warns on reinstall"
assert_contains "# custom edit" "$(cat "$hook")" "hand-modified hook preserved without --force"
assert_eq aider "$(git config --global fakeauthor.persona)" "persona still updates on reinstall"

sh "$INSTALL_SH" --force claude >/dev/null 2>&1
assert_not_contains "# custom edit" "$(cat "$hook")" "--force overwrites hand-modified hook"

# 6. --local mode installs per-repo (including .git/fakeauthor.sh + local alias.fakeauthor) without touching global config
new_sandbox
local_out=$(cd "$REPO" && sh "$INSTALL_SH" --local cursor)
local_lines=$(printf '%s\n' "$local_out" | wc -l)
assert_eq yes "$([ "$local_lines" -le 5 ] && echo yes)" "--local output is <= 5 lines"
assert_eq "verify: git fakeauthor status" "$(printf '%s\n' "$local_out" | tail -n 1)" "--local verify line"
assert_eq yes "$([ -x "$REPO/.git/hooks/commit-msg" ] && echo yes)" "--local writes repo commit-msg hook"
assert_eq yes "$([ -x "$REPO/.git/fakeauthor.sh" ] && echo yes)" "--local writes repo fakeauthor.sh"
assert_eq yes "$([ -f "$REPO/.git/fakeauthor-manifest" ] && echo yes)" "--local writes repo fakeauthor-manifest"
assert_eq cursor "$(git -C "$REPO" config --local fakeauthor.persona)" "--local sets repo fakeauthor.persona"
assert_eq unset "$(git config --global --get core.hooksPath 2>/dev/null || echo unset)" "--local leaves global hooksPath unset"
assert_eq unset "$(git config --global --get fakeauthor.persona 2>/dev/null || echo unset)" "--local leaves global persona unset"

# Commit using --local hook works
echo "loc" > "$REPO/loc.txt"
git -C "$REPO" add loc.txt
git -C "$REPO" commit -m "local commit" >/dev/null
assert_eq "Co-authored-by: Cursor <cursoragent@cursor.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "--local hook appends cursor trailer"

# --local aborts when foreign repo hook exists without manifest
new_sandbox
printf '#!/bin/sh\nexit 0\n' > "$REPO/.git/hooks/commit-msg"
chmod +x "$REPO/.git/hooks/commit-msg"
rc=0
(cd "$REPO" && sh "$INSTALL_SH" --local claude) >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc" "--local aborts on pre-existing foreign repo hook"

# --local aborts when global core.hooksPath is set
new_sandbox
git config --global core.hooksPath "$SANDBOX/some-global-hooks"
rc=0
(cd "$REPO" && sh "$INSTALL_SH" --local claude) >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc" "--local aborts when global core.hooksPath is set"
