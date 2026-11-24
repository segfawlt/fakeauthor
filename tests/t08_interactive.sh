#!/bin/sh
# Task 8b: Interactive toggle picker via FAKEAUTHOR_TTY (line mode) and real PTY (raw TUI).

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

# 7. Real PTY tests for raw-mode TUI (arrows, j/k, Space, a, Enter, Esc, Ctrl-C, stty restore)
if command -v python3 >/dev/null 2>&1 && python3 -c 'import fcntl, pty, termios' 2>/dev/null; then
    pty_py="$SANDBOX/pty_driver.py"
    cat > "$pty_py" <<'PY'
import fcntl, os, pty, select, struct, subprocess, sys, termios, time

cwd = sys.argv[1]
cmd = sys.argv[2:]
steps = []
for item in os.environ["PTY_STEPS"].split(";;"):
    if not item:
        continue
    wait_s, hex_b = item.split("==", 1)
    steps.append((wait_s, bytes.fromhex(hex_b)))

master, slave = pty.openpty()
if "PTY_COLS" in os.environ:
    cols = int(os.environ["PTY_COLS"])
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, cols, 0, 0))
orig_attrs = termios.tcgetattr(slave)

def attach_tty():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)

env = os.environ.copy()
env["TERM"] = "xterm-256color"
env.pop("FAKEAUTHOR_TTY", None)

proc = subprocess.Popen(
    cmd,
    cwd=cwd,
    env=env,
    stdin=slave,
    stdout=slave,
    stderr=slave,
    close_fds=True,
    preexec_fn=attach_tty,
)
os.close(slave)

buf = b""
idx = 0
deadline = time.time() + 10.0
while time.time() < deadline:
    r, _, _ = select.select([master], [], [], 0.05)
    if r:
        try:
            chunk = os.read(master, 4096)
            if not chunk:
                break
            buf += chunk
        except OSError:
            break
    if idx < len(steps):
        wait_s, payload = steps[idx]
        if wait_s.encode() in buf:
            time.sleep(0.05)
            os.write(master, payload)
            idx += 1
    if proc.poll() is not None and not select.select([master], [], [], 0.05)[0]:
        break

rc = proc.wait(timeout=5)
after_attrs = termios.tcgetattr(master)
os.close(master)

want_flags = orig_attrs[3] & (termios.ECHO | termios.ICANON)
got_flags = after_attrs[3] & (termios.ECHO | termios.ICANON)
if want_flags != got_flags:
    sys.stderr.write(f"PTY_STTY_NOT_RESTORED: want={want_flags} got={got_flags}\n")
    sys.exit(99)

sys.stdout.buffer.write(buf)
sys.exit(rc)
PY

    # 7a. Fresh install inside repo: down arrow -> local, Enter, j -> copilot, Space, down arrow -> codex, Space, Enter
    new_sandbox
    # Scope: 1b5b420d = ESC[B + Enter; Persona: 6a201b5b42200d = 'j' + ' ' + ESC[B + ' ' + Enter
    pty_out1=$(PTY_STEPS="1) Scope==1b5b420d;;Pick co-author(s)==6a201b5b42200d" \
        python3 "$pty_py" "$REPO" sh "$INSTALL_SH")
    assert_contains "Saved: claude,copilot,codex (local)" "$pty_out1" "PTY scope+persona saves claude,copilot,codex locally"
    echo "pt1" > "$REPO/pt1.txt"
    git -C "$REPO" add pt1.txt
    git -C "$REPO" commit -m "pty multi" >/dev/null
    pt1_tr=$(git -C "$REPO" log -1 --pretty=%\(trailers\))
    assert_eq 3 "$(printf '%s\n' "$pt1_tr" | wc -l)" "PTY local commit appends 3 trailers"

    # 7b. Re-run git fakeauthor in global repo: Enter (this repo), a (all 5), k (wrap to 6), k (to 5 aider), Space (toggle off), Enter
    new_sandbox
    sh "$INSTALL_SH" claude >/dev/null
    # Scope Enter: 0d; Persona 'akk \r': 616b6b200d
    pty_out2=$(PTY_STEPS="Apply changes to:==0d;;Pick co-author(s)==616b6b200d" \
        python3 "$pty_py" "$REPO" git fakeauthor)
    assert_contains "Saved: claude,copilot,codex,cursor (this repo)" "$pty_out2" "PTY vim wrap k unchecks aider"
    assert_eq "claude,copilot,codex,cursor" "$(git -C "$REPO" config --local --get fakeauthor.persona)" "PTY repo-local persona updated"

    # 7c. Cancel via Esc (\x1b) in PTY restores stty and writes nothing
    new_sandbox
    pty_out3=$(PTY_STEPS="Pick co-author(s)==1b" python3 "$pty_py" "$SANDBOX" sh "$INSTALL_SH")
    assert_contains "Cancelled" "$pty_out3" "PTY Esc cancels cleanly"
    assert_eq no "$([ -e "$HOME/.local/share/fakeauthor" ] && echo yes || echo no)" "PTY Esc writes nothing"

    # 7d. Cancel via Ctrl-C (\x03) in PTY restores stty and writes nothing
    new_sandbox
    rc_ctrlc=0
    PTY_STEPS="Pick co-author(s)==03" python3 "$pty_py" "$SANDBOX" sh "$INSTALL_SH" >/dev/null 2>&1 || rc_ctrlc=$?
    assert_eq yes "$([ "$rc_ctrlc" -ne 0 ] && [ "$rc_ctrlc" -ne 99 ] && echo yes || echo no)" "PTY Ctrl-C aborts and restores stty (rc=$rc_ctrlc)"
    assert_eq no "$([ -e "$HOME/.local/share/fakeauthor" ] && echo yes || echo no)" "PTY Ctrl-C writes nothing"

    # 7e. 80x24 and 50x24 PTY redraw check: j, j, k, q leaves exactly 1 header line and restores DECAWM/cursor
    chk_py="$SANDBOX/chk_screen.py"
    cat > "$chk_py" <<'CHK'
import os, sys
cols = int(os.environ["PTY_SCREEN_COLS"])
s = sys.stdin.read()
if "\x1b[?7h" not in s or "\x1b[?25h" not in s:
    sys.stderr.write("MISSING_TERMINAL_RESTORE_SEQ\n")
    sys.exit(1)
rows = [""] * 24
cy, cx = 0, 0
wrap = True
i = 0
while i < len(s):
    ch = s[i]
    if ch == "\x1b" and i + 1 < len(s) and s[i+1] == "[":
        j = i + 2
        while j < len(s) and not ("@" <= s[j] <= "~"):
            j += 1
        seq = s[i+2:j]
        cmd = s[j] if j < len(s) else ""
        if cmd == "A":
            n = int(seq) if seq.isdigit() else 1
            cy = max(0, cy - n)
        elif cmd == "K":
            rows[cy] = rows[cy][:cx]
        elif seq == "?7" and cmd == "l":
            wrap = False
        elif seq == "?7" and cmd == "h":
            wrap = True
        i = j + 1
        continue
    elif ch == "\r":
        cx = 0
    elif ch == "\n":
        cy += 1
        if cy >= 24:
            rows.pop(0); rows.append(""); cy = 23
    else:
        if cx >= cols:
            if wrap:
                cx = 0
                cy += 1
                if cy >= 24:
                    rows.pop(0); rows.append(""); cy = 23
            else:
                cx = cols - 1
        line = rows[cy]
        if len(line) < cx:
            line = line.ljust(cx)
        rows[cy] = line[:cx] + ch + line[cx+1:]
        cx += 1
    i += 1
print(sum("Pick co-author(s)" in r for r in rows))
CHK
    for cols in 80 50; do
        new_sandbox
        pty_screen=$(PTY_COLS="$cols" PTY_STEPS="Pick co-author(s)==6a6a6b71" \
            python3 "$pty_py" "$SANDBOX" sh "$INSTALL_SH")
        hdr_count=$(printf '%s' "$pty_screen" | PTY_SCREEN_COLS="$cols" python3 "$chk_py")
        assert_eq 1 "$hdr_count" "PTY ${cols}x24 redraw keeps single header after jjkq"
    done
fi
