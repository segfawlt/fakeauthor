#!/bin/sh
# Task 7: git fakeauthor on/off/status/uninstall (offline, global and --local).

set -eu
. "$(dirname "$0")/lib.sh"

# 1. Offline git fakeauthor on/off/status/uninstall after deleting source install.sh copy
new_sandbox
cp "$INSTALL_SH" "$SANDBOX/tmp-install.sh"
sh "$SANDBOX/tmp-install.sh" claude >/dev/null
rm -f "$SANDBOX/tmp-install.sh"

ctl="$HOME/.local/share/fakeauthor/fakeauthor.sh"
assert_eq yes "$([ -x "$ctl" ] && echo yes)" "offline fakeauthor.sh exists after source removed"

st=$(git fakeauthor status)
st_lines=$(printf '%s\n' "$st" | wc -l)
assert_eq yes "$([ "$st_lines" -le 5 ] && echo yes)" "status output <= 5 lines ($st_lines)"
assert_contains "active (global)" "$st" "status reports active (global)"
assert_contains "claude" "$st" "status reports claude persona"
assert_contains "rate: 1" "$st" "status reports rate"
assert_contains "hooksPath:" "$st" "status reports hooksPath"
assert_contains "aliases: claude" "$st" "status reports aliases"

# git fakeauthor off inside repo pauses ONLY that repo; sibling remains active
new_repo "$SANDBOX/repo2"
git -C "$REPO" fakeauthor off >/dev/null
assert_eq true "$(git -C "$REPO" config --local --get fakeauthor.off)" "git fakeauthor off sets repo-local off=true"
assert_contains "paused (global)" "$(git -C "$REPO" fakeauthor status)" "repo status shows paused"
assert_contains "active (global)" "$(git -C "$SANDBOX/repo2" fakeauthor status)" "sibling repo status stays active"

echo "p1" > "$REPO/p1.txt"
git -C "$REPO" add p1.txt
git -C "$REPO" commit -m "paused commit" >/dev/null
assert_eq "" "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "paused repo skips trailer"

git -C "$REPO" fakeauthor on >/dev/null
assert_contains "active (global)" "$(git -C "$REPO" fakeauthor status)" "git fakeauthor on resumes repo"
echo "p2" > "$REPO/p2.txt"
git -C "$REPO" add p2.txt
git -C "$REPO" commit -m "resumed commit" >/dev/null
assert_eq "Co-Authored-By: Claude <noreply@anthropic.com>" \
    "$(git -C "$REPO" log -1 --pretty=%\(trailers\))" "resumed repo adds trailer"

# git fakeauthor off outside any repo pauses globally
off_glob=$(cd "$SANDBOX" && git fakeauthor off)
assert_contains "globally" "$off_glob" "outside repo off pauses globally"
assert_eq true "$(git config --global --get fakeauthor.off)" "global fakeauthor.off set to true"
(cd "$SANDBOX" && git fakeauthor on >/dev/null)
assert_eq false "$(git config --global --get fakeauthor.off)" "global fakeauthor on sets false"
git config --global --unset fakeauthor.off

# Switch persona claude -> codex offline via git fakeauthor, set user fakeauthor.name, then uninstall
git fakeauthor codex >/dev/null
git config --global fakeauthor.name "Keep Me"
git -C "$REPO" config --unset fakeauthor.off 2>/dev/null || true

uninst_out=$(git fakeauthor uninstall)
assert_eq no "$([ -e "$HOME/.local/share/fakeauthor" ] && echo yes || echo no)" "uninstall removes ~/.local/share/fakeauthor"
assert_eq unset "$(git config --global --get core.hooksPath 2>/dev/null || echo unset)" "uninstall unsets core.hooksPath"
assert_eq unset "$(git config --global --get fakeauthor.persona 2>/dev/null || echo unset)" "uninstall unsets fakeauthor.persona"
assert_eq unset "$(git config --global --get fakeauthor.rate 2>/dev/null || echo unset)" "uninstall unsets fakeauthor.rate"
assert_eq unset "$(git config --global --get alias.fakeauthor 2>/dev/null || echo unset)" "uninstall unsets alias.fakeauthor"
assert_eq "Keep Me" "$(git config --global --get fakeauthor.name)" "uninstall preserves user fakeauthor.name"
assert_contains "fakeauthor.name" "$uninst_out" "uninstall notes preserved user config key"

# Second uninstall via install.sh is idempotent and exits 0; status shows not installed
sh "$INSTALL_SH" uninstall >/dev/null
st_after=$(sh "$INSTALL_SH" status)
assert_contains "not installed" "$st_after" "status after uninstall reports not installed"

# 2. Hand-modified commit-msg is preserved and manifest remains on partial uninstall
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
hook="$HOME/.local/share/fakeauthor/hooks/commit-msg"
printf '# user edit\n' >> "$hook"
sh "$HOME/.local/share/fakeauthor/fakeauthor.sh" uninstall >/dev/null 2>&1
assert_eq yes "$([ -f "$hook" ] && echo yes)" "partial uninstall preserves hand-modified commit-msg"
assert_eq yes "$([ -f "$HOME/.local/share/fakeauthor/manifest" ] && echo yes)" "partial uninstall retains manifest"
st_part=$(sh "$INSTALL_SH" status)
assert_contains "partially uninstalled" "$st_part" "status reports partially uninstalled"

# 3. Extra untracked file in hooks dir is preserved and manifest remains on partial uninstall
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
extra="$HOME/.local/share/fakeauthor/hooks/custom-note"
printf 'keep me\n' > "$extra"
sh "$HOME/.local/share/fakeauthor/fakeauthor.sh" uninstall >/dev/null 2>&1
assert_eq yes "$([ -f "$extra" ] && echo yes)" "partial uninstall preserves extra untracked file"
assert_eq yes "$([ -f "$HOME/.local/share/fakeauthor/manifest" ] && echo yes)" "partial uninstall retains manifest when hooks dir not empty"

# 4. hooksPath_prev containing spaces is restored verbatim on uninstall
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
manifest="$HOME/.local/share/fakeauthor/manifest"
sed 's|^hooksPath_prev=.*|hooksPath_prev=/tmp/my hooks|' "$manifest" > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"
git fakeauthor uninstall >/dev/null
assert_eq "/tmp/my hooks" "$(git config --global --get core.hooksPath)" "uninstall restores hooksPath_prev with spaces verbatim"

# 5. --local repo: git fakeauthor status/off/on/uninstall auto-detect local manifest without --local flag
new_sandbox
(cd "$REPO" && sh "$INSTALL_SH" --local aider >/dev/null)
mkdir -p "$REPO/sub"
st_loc=$(cd "$REPO/sub" && git fakeauthor status)
assert_contains "active (local)" "$st_loc" "local git fakeauthor status auto-detects local mode"
assert_contains "aider" "$st_loc" "local status reports aider"

(cd "$REPO/sub" && git fakeauthor off >/dev/null)
assert_contains "paused (local)" "$(cd "$REPO" && git fakeauthor status)" "local git fakeauthor off pauses repo"
(cd "$REPO/sub" && git fakeauthor on >/dev/null)
assert_contains "active (local)" "$(cd "$REPO" && git fakeauthor status)" "local git fakeauthor on resumes repo"

(cd "$REPO/sub" && git fakeauthor uninstall >/dev/null)
assert_eq no "$([ -e "$REPO/.git/hooks/commit-msg" ] && echo yes || echo no)" "local uninstall removes repo commit-msg"
assert_eq no "$([ -e "$REPO/.git/fakeauthor.sh" ] && echo yes || echo no)" "local uninstall removes repo fakeauthor.sh"
assert_eq no "$([ -e "$REPO/.git/fakeauthor-manifest" ] && echo yes || echo no)" "local uninstall removes repo fakeauthor-manifest"
assert_eq unset "$(git -C "$REPO" config --local --get alias.fakeauthor 2>/dev/null || echo unset)" "local uninstall removes local alias.fakeauthor"
assert_eq unset "$(git -C "$REPO" config --local --get fakeauthor.persona 2>/dev/null || echo unset)" "local uninstall unsets local persona"
assert_eq unset "$(git -C "$REPO" config --local --get fakeauthor.rate 2>/dev/null || echo unset)" "local uninstall unsets local rate"
st_loc_after=$(cd "$REPO" && sh "$INSTALL_SH" --local status)
assert_contains "not installed" "$st_loc_after" "--local status after uninstall reports not installed"
