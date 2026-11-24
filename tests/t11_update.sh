#!/bin/sh
# Task 11: Version tracking, reinstall/repair/up-to-date detection, and git fakeauthor update.

set -eu
. "$(dirname "$0")/lib.sh"

# 1. Status displays version and stays <= 5 lines
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
st=$(git fakeauthor status)
st_lines=$(printf '%s\n' "$st" | wc -l)
assert_eq yes "$([ "$st_lines" -le 5 ] && echo yes)" "status with version stays <= 5 lines ($st_lines)"
assert_contains "active (global) v0.2.0" "$st" "status shows active (global) v0.2.0"

# 2. Re-running installer with same persona reports already up to date
re_out=$(sh "$INSTALL_SH" claude)
assert_contains "already up to date" "$re_out" "reinstall same persona reports already up to date"

# 3. Missing hook/binary triggers repair on re-install
rm -f "$HOME/.local/share/fakeauthor/hooks/commit-msg"
rep_out=$(sh "$INSTALL_SH" claude)
assert_contains "repaired claude" "$rep_out" "missing commit-msg triggers repaired message"
assert_eq yes "$([ -x "$HOME/.local/share/fakeauthor/hooks/commit-msg" ] && echo yes)" "repair restores executable commit-msg"

# 4. update --check against same version reports up to date
same_remote="$SANDBOX/remote_same.sh"
cp "$INSTALL_SH" "$same_remote"
chk_same=$(FAKEAUTHOR_UPDATE_URL="file://$same_remote" git fakeauthor update --check)
assert_contains "up to date (v0.2.0)" "$chk_same" "update --check reports up to date on matching version"

# 5. update --check against newer remote reports update available without mutating files
new_remote="$SANDBOX/remote_new.sh"
sed 's/^FAKEAUTHOR_VERSION="0.2.0"/FAKEAUTHOR_VERSION="0.9.9"/' "$INSTALL_SH" > "$new_remote"
chk_new=$(FAKEAUTHOR_UPDATE_URL="file://$new_remote" git fakeauthor update --check)
assert_contains "update available (v0.2.0 -> v0.9.9)" "$chk_new" "update --check detects newer remote version"
assert_contains "v0.2.0" "$(git fakeauthor status)" "update --check leaves installed version unchanged"

# 6. git fakeauthor update upgrades to 0.9.9 while preserving persona, rate, and hooksPath_prev
git fakeauthor codex >/dev/null
git config --global fakeauthor.rate 0.25
manifest="$HOME/.local/share/fakeauthor/manifest"
sed 's|^hooksPath_prev=.*|hooksPath_prev=/tmp/prev hooks|' "$manifest" > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"

up_out=$(FAKEAUTHOR_UPDATE_URL="file://$new_remote" git fakeauthor update)
assert_contains "updated v0.2.0 -> v0.9.9" "$up_out" "update reports version upgrade"
assert_contains "v0.9.9" "$(git fakeauthor status)" "status reflects upgraded v0.9.9"
assert_eq codex "$(git config --global fakeauthor.persona)" "update preserves persona"
assert_eq 0.25 "$(git config --global fakeauthor.rate)" "update preserves custom rate"
assert_contains "hooksPath_prev=/tmp/prev hooks" "$(cat "$manifest")" "update preserves hooksPath_prev"

# 7. Missing files detected by update --check and repaired by git fakeauthor update
rm -f "$HOME/.local/share/fakeauthor/hooks/commit-msg"
chk_miss=$(FAKEAUTHOR_UPDATE_URL="file://$new_remote" git fakeauthor update --check)
assert_contains "missing files detected" "$chk_miss" "update --check flags missing commit-msg"
rep_up=$(FAKEAUTHOR_UPDATE_URL="file://$new_remote" git fakeauthor update)
assert_contains "repaired codex (v0.9.9, global)" "$rep_up" "git fakeauthor update repairs missing hook"
assert_eq yes "$([ -x "$HOME/.local/share/fakeauthor/hooks/commit-msg" ] && echo yes)" "update restores missing commit-msg"

# 8. Corrupt remote payload aborts cleanly without touching existing install
bad_remote="$SANDBOX/bad.sh"
printf '<html>404 Not Found</html>\n' > "$bad_remote"
assert_fails "corrupt remote update aborts non-zero" env FAKEAUTHOR_UPDATE_URL="file://$bad_remote" git fakeauthor update
assert_contains "v0.9.9" "$(git fakeauthor status)" "failed update preserves working install"

# 9. Running install.sh update when not installed installs cleanly from remote
new_sandbox
fresh_up=$(FAKEAUTHOR_UPDATE_URL="file://$same_remote" sh "$INSTALL_SH" update)
assert_contains "installed claude (global)" "$fresh_up" "update when not installed performs clean install"
assert_contains "active (global) v0.2.0" "$(git fakeauthor status)" "fresh install via update is active"
