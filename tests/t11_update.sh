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

# 10. Interactive wizard reinstall from unversioned manifest displays updated notice
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
m_unv="$HOME/.local/share/fakeauthor/manifest"
grep -v '^script_version=' "$m_unv" > "$m_unv.tmp" && mv "$m_unv.tmp" "$m_unv"
printf '\n' > "$SANDBOX/wiz_in"
wiz_out=$(FAKEAUTHOR_TTY="$SANDBOX/wiz_in" sh "$INSTALL_SH")
assert_contains "existing install detected (unversioned)" "$wiz_out" "wizard announces existing unversioned install"
assert_contains "fakeauthor: updated claude" "$wiz_out" "wizard displays updated notice on unversioned upgrade"
assert_contains "Saved: claude (global)" "$wiz_out" "wizard preserves Saved line"

# 11. Cached auto-update check inside git fakeauthor prints notice, writes cache, and uninstall removes cache
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
printf '\n' > "$SANDBOX/ctl_in"
auto_out=$(FAKEAUTHOR_UPDATE_CHECK_FORCE=1 FAKEAUTHOR_UPDATE_URL="file://$new_remote" \
    FAKEAUTHOR_TTY="$SANDBOX/ctl_in" git fakeauthor)
assert_contains "update available (v0.2.0 -> v0.9.9)" "$auto_out" \
    "git fakeauthor interactive menu displays auto-update notice"
assert_eq yes "$([ -f "$HOME/.local/share/fakeauthor/last_update_check" ] && echo yes)" \
    "auto-update check writes last_update_check cache"

# Cached hit within 24h on real PTY serves update notice without hitting network
if command -v python3 >/dev/null 2>&1 && python3 -c 'import fcntl, pty, termios' 2>/dev/null; then
    pty_auto=$(FAKEAUTHOR_UPDATE_URL="file://$bad_remote" python3 -c '
import fcntl, os, pty, select, subprocess, termios, time
m, s = pty.openpty()
def attach():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
env = os.environ.copy()
env["TERM"] = "xterm-256color"
env.pop("FAKEAUTHOR_TTY", None)
p = subprocess.Popen(["git", "fakeauthor"], env=env, stdin=s, stdout=s, stderr=s, close_fds=True, preexec_fn=attach)
os.close(s)
buf = b""
sent = False
deadline = time.time() + 5
while time.time() < deadline:
    r, _, _ = select.select([m], [], [], 0.05)
    if r:
        try: chunk = os.read(m, 4096)
        except OSError: break
        if not chunk: break
        buf += chunk
        if not sent and b"Pick co-author" in buf:
            time.sleep(0.05)
            os.write(m, b"q")
            sent = True
    if p.poll() is not None and not select.select([m], [], [], 0.05)[0]:
        break
p.wait(timeout=5)
os.close(m)
print(buf.decode("utf-8", "replace"))
')
    assert_contains "update available (v0.2.0 -> v0.9.9)" "$pty_auto" \
        "24h cache serves update notice without hitting network"
fi

git fakeauthor uninstall >/dev/null
assert_eq no "$([ -e "$HOME/.local/share/fakeauthor" ] && echo yes || echo no)" \
    "uninstall removes last_update_check and ~/.local/share/fakeauthor cleanly"
