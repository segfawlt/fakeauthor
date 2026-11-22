#!/bin/sh
# Task 7: Offline manifest-driven off and status (global and --local).

set -eu
. "$(dirname "$0")/lib.sh"

# 1. Offline status & off after deleting source install.sh copy; persona switch cleanup
new_sandbox
cp "$INSTALL_SH" "$SANDBOX/tmp-install.sh"
sh "$SANDBOX/tmp-install.sh" claude >/dev/null
rm -f "$SANDBOX/tmp-install.sh"

ctl="$HOME/.config/fakeai/fakeai.sh"
assert_eq yes "$([ -x "$ctl" ] && echo yes)" "offline fakeai.sh exists after source removed"

st=$(sh "$ctl" status)
st_lines=$(printf '%s\n' "$st" | wc -l)
assert_eq yes "$([ "$st_lines" -le 5 ] && echo yes)" "status output <= 5 lines ($st_lines)"
assert_contains "installed" "$st" "status reports installed"
assert_contains "claude" "$st" "status reports claude persona"
assert_contains "rate: 1" "$st" "status reports rate"
assert_contains "hooksPath:" "$st" "status reports hooksPath"
assert_contains "alias:" "$st" "status reports alias"

# Switch persona claude -> codex before off; set user-owned fakeai.name that off must preserve
sh "$INSTALL_SH" codex >/dev/null
git config --global fakeai.name "Keep Me"

off_out=$(sh "$ctl" off)
assert_eq no "$([ -e "$HOME/.config/fakeai" ] && echo yes || echo no)" "off removes ~/.config/fakeai when clean"
assert_eq unset "$(git config --global --get core.hooksPath 2>/dev/null || echo unset)" "off unsets core.hooksPath"
assert_eq unset "$(git config --global --get fakeai.persona 2>/dev/null || echo unset)" "off unsets fakeai.persona"
assert_eq unset "$(git config --global --get fakeai.rate 2>/dev/null || echo unset)" "off unsets fakeai.rate"
assert_eq "Keep Me" "$(git config --global --get fakeai.name)" "off preserves user-set fakeai.name"
assert_contains "Keep Me" "$(printf '%s' "$off_out"; git config --global --get fakeai.name)" "user key kept"
assert_contains "fakeai.name" "$off_out" "off notes preserved user config key"

# Second off via install.sh is idempotent and exits 0; status shows not installed
sh "$INSTALL_SH" off >/dev/null
st_after=$(sh "$INSTALL_SH" status)
assert_contains "not installed" "$st_after" "status after off reports not installed"

# 2. Hand-modified commit-msg is preserved and manifest remains on partial off
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
hook="$HOME/.config/fakeai/hooks/commit-msg"
printf '# user edit\n' >> "$hook"
sh "$HOME/.config/fakeai/fakeai.sh" off >/dev/null 2>&1
assert_eq yes "$([ -f "$hook" ] && echo yes)" "partial off preserves hand-modified commit-msg"
assert_eq yes "$([ -f "$HOME/.config/fakeai/manifest" ] && echo yes)" "partial off retains manifest"
st_part=$(sh "$INSTALL_SH" status)
assert_contains "partially uninstalled" "$st_part" "status reports partially uninstalled"

# 3. Extra untracked file in hooks dir is preserved and manifest remains on partial off
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
extra="$HOME/.config/fakeai/hooks/custom-note"
printf 'keep me\n' > "$extra"
sh "$HOME/.config/fakeai/fakeai.sh" off >/dev/null 2>&1
assert_eq yes "$([ -f "$extra" ] && echo yes)" "partial off preserves extra untracked file in hooks dir"
assert_eq yes "$([ -f "$HOME/.config/fakeai/manifest" ] && echo yes)" "partial off retains manifest when hooks dir not empty"

# 4. hooksPath_prev containing spaces is restored verbatim on off
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
manifest="$HOME/.config/fakeai/manifest"
sed 's|^hooksPath_prev=.*|hooksPath_prev=/tmp/my hooks|' "$manifest" > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"
sh "$HOME/.config/fakeai/fakeai.sh" off >/dev/null
assert_eq "/tmp/my hooks" "$(git config --global --get core.hooksPath)" "off restores hooksPath_prev with spaces verbatim"

# 5. --local status and --local off clean repo-only install without touching global config
new_sandbox
(cd "$REPO" && sh "$INSTALL_SH" --local aider >/dev/null)
st_loc=$(cd "$REPO" && sh "$INSTALL_SH" --local status)
assert_contains "installed (local)" "$st_loc" "--local status reports installed (local)"
assert_contains "aider" "$st_loc" "--local status reports aider"

(cd "$REPO" && sh "$INSTALL_SH" --local off >/dev/null)
assert_eq no "$([ -e "$REPO/.git/hooks/commit-msg" ] && echo yes || echo no)" "--local off removes repo commit-msg"
assert_eq no "$([ -e "$REPO/.git/fakeai-manifest" ] && echo yes || echo no)" "--local off removes repo fakeai-manifest"
assert_eq unset "$(git -C "$REPO" config --local --get fakeai.persona 2>/dev/null || echo unset)" "--local off unsets local persona"
assert_eq unset "$(git -C "$REPO" config --local --get fakeai.rate 2>/dev/null || echo unset)" "--local off unsets local rate"
st_loc_after=$(cd "$REPO" && sh "$INSTALL_SH" --local status)
assert_contains "not installed" "$st_loc_after" "--local status after off reports not installed"
