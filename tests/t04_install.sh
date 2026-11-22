#!/bin/sh
# Task 5: Manifest state, never-clobber, offline fakeai.sh, --local mode, and output UX.

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
assert_eq no "$([ -e "$HOME/.config/fakeai" ] && echo yes || echo no)" "zero writes on foreign abort"

# 2. Pre-existing $HOME/.config/fakeai/hooks set as core.hooksPath without manifest aborts
new_sandbox
mkdir -p "$HOME/.config/fakeai/hooks"
git config --global core.hooksPath "$HOME/.config/fakeai/hooks"
rc=0
sh "$INSTALL_SH" claude >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc" "existing hooks dir without manifest aborts"
assert_eq no "$([ -f "$HOME/.config/fakeai/manifest" ] && echo yes || echo no)" "manifest absent after unowned dir abort"

# 3. No-arg defaults to claude, writes manifest + offline fakeai.sh, <=5 lines ending with verify
new_sandbox
out=$(sh "$INSTALL_SH")
lines=$(printf '%s\n' "$out" | wc -l)
assert_eq yes "$([ "$lines" -le 5 ] && echo yes)" "install output is <= 5 lines ($lines)"
last_line=$(printf '%s\n' "$out" | tail -n 1)
assert_eq "verify: sh ~/.config/fakeai/fakeai.sh status" "$last_line" "output ends with verify line"

manifest="$HOME/.config/fakeai/manifest"
ctl="$HOME/.config/fakeai/fakeai.sh"
hook="$HOME/.config/fakeai/hooks/commit-msg"
assert_eq yes "$([ -f "$manifest" ] && echo yes)" "manifest created"
assert_eq yes "$([ -x "$ctl" ] && echo yes)" "offline fakeai.sh created and executable"
assert_eq claude "$(git config --global fakeai.persona)" "no-arg defaults to claude"
assert_eq 1 "$(git config --global fakeai.rate)" "initial install sets fakeai.rate=1"
assert_contains "hooksPath_prev=UNSET" "$(cat "$manifest")" "manifest records hooksPath_prev=UNSET"
assert_contains "persona=claude" "$(cat "$manifest")" "manifest records persona=claude"

# 4. Reinstall with codex preserves hooksPath_prev and custom fakeai.rate=0.25
git config --global fakeai.rate 0.25
sh "$INSTALL_SH" codex >/dev/null
assert_eq codex "$(git config --global fakeai.persona)" "reinstall switches persona to codex"
assert_eq 0.25 "$(git config --global fakeai.rate)" "reinstall preserves custom fakeai.rate=0.25"
assert_contains "hooksPath_prev=UNSET" "$(cat "$manifest")" "reinstall preserves original hooksPath_prev"
assert_contains "persona=codex" "$(cat "$manifest")" "manifest updates persona=codex"

# 5. Hand-modified hook is warned and preserved without --force, overwritten with --force
printf '# custom edit\n' >> "$hook"
warn_out=$(sh "$INSTALL_SH" aider 2>&1)
assert_contains "modified" "$warn_out" "hand-modified hook warns on reinstall"
assert_contains "# custom edit" "$(cat "$hook")" "hand-modified hook preserved without --force"
assert_eq aider "$(git config --global fakeai.persona)" "persona still updates on reinstall"

sh "$INSTALL_SH" --force claude >/dev/null 2>&1
assert_not_contains "# custom edit" "$(cat "$hook")" "--force overwrites hand-modified hook"

# 6. --local mode installs per-repo without touching global config, aborts on conflicts
new_sandbox
local_out=$(cd "$REPO" && sh "$INSTALL_SH" --local cursor)
local_lines=$(printf '%s\n' "$local_out" | wc -l)
assert_eq yes "$([ "$local_lines" -le 5 ] && echo yes)" "--local output is <= 5 lines"
assert_eq "verify: git config --local fakeai.persona" "$(printf '%s\n' "$local_out" | tail -n 1)" "--local verify line"
assert_eq yes "$([ -x "$REPO/.git/hooks/commit-msg" ] && echo yes)" "--local writes repo commit-msg hook"
assert_eq yes "$([ -f "$REPO/.git/fakeai-manifest" ] && echo yes)" "--local writes repo fakeai-manifest"
assert_eq cursor "$(git -C "$REPO" config --local fakeai.persona)" "--local sets repo fakeai.persona"
assert_eq unset "$(git config --global --get core.hooksPath 2>/dev/null || echo unset)" "--local leaves global hooksPath unset"
assert_eq unset "$(git config --global --get fakeai.persona 2>/dev/null || echo unset)" "--local leaves global persona unset"

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
