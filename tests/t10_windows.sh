#!/bin/sh
# Task 10: Windows portability guards (paths, backslash hooks/dir, CRLF TTY, -c off chaining, install.ps1 checks).

set -eu
. "$(dirname "$0")/lib.sh"

# 1. canon_path terminates cleanly on non-existent Windows drive paths and normalizes backslashes
new_sandbox
cp_helper="$SANDBOX/cp_helper.sh"
sed -n '/^norm_slashes()/,/^}/p;/^canon_path()/,/^}/p' "$INSTALL_SH" > "$cp_helper"
assert_eq "Z:/nonexistent/dir" "$(sh -c ". \"$cp_helper\"; canon_path 'Z:/nonexistent/dir'")" \
    "canon_path handles Z:/nonexistent/dir without prepending PWD"
assert_eq "Z:/nonexistent/dir" "$(sh -c ". \"$cp_helper\"; canon_path 'Z:\\nonexistent\\dir'")" \
    "canon_path normalizes backslashes on Z:\\nonexistent\\dir"

git config --global core.hooksPath "Z:/nonexistent/foreign"
rc=0
FAKEAUTHOR_DIR="Z:/nonexistent/fa" sh "$INSTALL_SH" claude >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc" "global install aborts cleanly against non-existent drive hooksPath"

# 2. Backslash FAKEAUTHOR_DIR installs, reports status, and uninstalls cleanly
new_sandbox
win_fa="$SANDBOX\\win\\\\fa"
FAKEAUTHOR_DIR="$win_fa" sh "$INSTALL_SH" claude >/dev/null
assert_eq yes "$([ -x "$SANDBOX/win/fa/hooks/commit-msg" ] && echo yes)" "backslash FAKEAUTHOR_DIR creates commit-msg"
assert_eq yes "$([ -x "$SANDBOX/win/fa/fakeauthor.sh" ] && echo yes)" "backslash FAKEAUTHOR_DIR creates fakeauthor.sh"
st_w=$(cd "$REPO" && FAKEAUTHOR_DIR="$win_fa" git fakeauthor status)
assert_contains "active (global)" "$st_w" "status works with backslash FAKEAUTHOR_DIR"
(cd "$REPO" && FAKEAUTHOR_DIR="$win_fa" git fakeauthor uninstall >/dev/null)
assert_eq no "$([ -e "$SANDBOX/win/fa" ] && echo yes || echo no)" "uninstall removes backslash FAKEAUTHOR_DIR"

# 3. trim_ws handles CRLF FAKEAUTHOR_TTY interactive inputs cleanly
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
printf '1\r\n1,3\r\n\r\n' > "$SANDBOX/crlf_in"
out_crlf=$(cd "$REPO" && FAKEAUTHOR_TTY="$SANDBOX/crlf_in" git fakeauthor)
assert_contains "Saved: codex (this repo)" "$out_crlf" "CRLF FAKEAUTHOR_TTY toggles claude off and codex on"
assert_eq codex "$(git -C "$REPO" config --local --get fakeauthor.persona)" "CRLF FAKEAUTHOR_TTY saves codex locally"

new_sandbox
printf '2\r\n3\r\n\r\n' > "$SANDBOX/crlf_wiz"
out_wiz=$(cd "$REPO" && FAKEAUTHOR_TTY="$SANDBOX/crlf_wiz" sh "$INSTALL_SH")
assert_contains "Saved: claude,codex (local)" "$out_wiz" "CRLF wizard chooses local and saves claude,codex"
assert_eq "claude,codex" "$(git -C "$REPO" config --local --get fakeauthor.persona)" "CRLF wizard persists local persona"

# 4. git -c fakeauthor.off=true obeys the chain invariant
new_sandbox
sh "$INSTALL_SH" claude >/dev/null
cat > "$REPO/.git/hooks/commit-msg" <<'EOF'
#!/bin/sh
echo "CHAINED_ON_CLI_OFF" >&2
exit 1
EOF
chmod +x "$REPO/.git/hooks/commit-msg"
echo "ch" > "$REPO/ch.txt"
git -C "$REPO" add ch.txt
ch_err=$SANDBOX/ch.err
rc=0
git -C "$REPO" -c fakeauthor.off=true commit -m "blocked" >/dev/null 2>"$ch_err" || rc=$?
assert_eq 1 "$rc" "-c fakeauthor.off=true chains to failing repo commit-msg"
assert_contains "CHAINED_ON_CLI_OFF" "$(cat "$ch_err")" "-c fakeauthor.off=true runs repo commit-msg"

# 5. Backslash $0 hook-chaining basename logic on generated commit-msg and pre-commit
hook_cm="$HOME/.local/share/fakeauthor/hooks/commit-msg"
hook_pc="$HOME/.local/share/fakeauthor/hooks/pre-commit"
assert_contains 'hook_name=${0##*/}' "$(cat "$hook_cm")" "commit-msg extracts slash basename"
assert_contains 'hook_name=${hook_name##*\\}' "$(cat "$hook_cm")" "commit-msg extracts backslash basename"
assert_contains 'hook_name=${0##*/}' "$(cat "$hook_pc")" "pre-commit stub extracts slash basename"
assert_contains 'hook_name=${hook_name##*\\}' "$(cat "$hook_pc")" "pre-commit stub extracts backslash basename"

extracted=$(sh -c 'hook_name=${0##*/}; hook_name=${hook_name##*\\}; printf "%s\n" "$hook_name"' \
    'C:\Users\alice\.local\share\fakeauthor\hooks\pre-commit')
assert_eq "pre-commit" "$extracted" "backslash Windows path yields pre-commit basename"

case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *)
        mkdir -p "$SANDBOX/bs"
        bs_pc="$SANDBOX/bs/C:\\fake\\hooks\\pre-commit"
        cp "$hook_pc" "$bs_pc"
        chmod +x "$bs_pc"
        printf '#!/bin/sh\ntouch "%s/bs_chained"\n' "$SANDBOX" > "$REPO/.git/hooks/pre-commit"
        chmod +x "$REPO/.git/hooks/pre-commit"
        (cd "$REPO" && sh "$bs_pc")
        assert_eq yes "$([ -f "$SANDBOX/bs_chained" ] && echo yes)" \
            "generated pre-commit stub chains when invoked with backslash path"
        ;;
esac

# 6. Static checks on install.ps1
ps1="$ROOT_DIR/install.ps1"
ps1_body=$(cat "$ps1")
assert_contains "SecurityProtocolType]::Tls12" "$ps1_body" "install.ps1 enables TLS 1.2"
assert_contains 'UTF8Encoding($false)' "$ps1_body" "install.ps1 writes UTF-8 without BOM"
assert_contains "PSCommandPath" "$ps1_body" "install.ps1 guards exit with PSCommandPath for iex safety"
first_code=$(awk '/^[ \t]*(#|$)/ { next } { print; exit }' "$ps1")
case "$first_code" in
    param\(*|Param\(*|PARAM\(*)
        echo "FAIL: install.ps1 must not declare top-level param(...)" >&2
        exit 1
        ;;
esac
