---
title: POSIX sh Portability and CRLF Guard
category: platform-issues
module: tests/t09_bytes.sh
tags: [posix-sh, crlf, testing]
problem_type: design-decision
date: 2026-11-23
last_updated: 2026-11-24
---

# POSIX sh Portability and CRLF Guard

## Context

On Linux hosts where `/bin/sh` symlinks to `bash` (observed `/usr/sbin/sh -> /usr/bin/bash`) and `dash`/`shellcheck` are absent, bashisms such as `$'\r'` execute silently in tests while failing on strict POSIX shells or Git Bash when files acquire CRLF line endings.

## Guidance

1. Pin `*.sh text eol=lf` in `.gitattributes` and check every generated file after write via POSIX `LC_ALL=C tr -cd '\r' | wc -c` (`check_no_cr` in `install.sh`), never bashism `$'\r'`.
2. In `tests/t09_bytes.sh`, construct the `$'\r'` scan pattern via `printf '$%s' "'\\\\r'"` so the test script itself contains zero literal bashism patterns, and test `check_no_cr` using an `awk`-poisoned installer copy whose heredoc bodies carry `\r`. Because `t09_bytes.sh` scans for literal `[[` with `grep -q '\[\['`, avoid POSIX character classes starting with `[[` such as `[[:space:]]` in `install.sh` and `tests/*.sh` (use `[ \t]` or negated `[^[:space:]]`).
3. Seed `awk` rate randomness with PID + `rand()` (`srand(); x=rand(); srand(int(x*2147483647)+p)`) and coerce string rate inputs (`rv = r + 0`) after regex validation so rapid commits within one second do not share identical `time(NULL)` seeds and non-numeric configs do not string-compare as true.
4. Isolate test sandboxes by setting `HOME`, `XDG_CONFIG_HOME`, and `GIT_CONFIG_NOSYSTEM=1` (while unsetting `GIT_CONFIG_GLOBAL`) AND calling `cd "$SANDBOX"` inside `new_sandbox()` (restoring `cd "$ROOT_DIR"` in cleanup) so bare `git` commands in tests cannot read host `.git/config` when the developer runs tests inside a `--local`-configured repo.
5. For interactive POSIX `sh` prompts (`curl | sh` + regular-file `FAKEAUTHOR_TTY` tests), open input once on FD 3 (`exec 3<"${FAKEAUTHOR_TTY:-/dev/tty}"`), read with `<&3`, and close with `exec 3<&-` so multiple `read` calls advance sequentially instead of reopening from byte 0.
6. For raw-mode TUI keys (`can_raw_tui`), read single bytes with `b=$(dd bs=1 count=1 <&3 2>/dev/null; printf x); b=${b%x}` (the trailing `x` stops command substitution from stripping `Enter` newlines), read CSI/SS3 sequences (`[A`, `OA`, `[B`, `OB`) with a `stty min 0 time 1` timeout after `ESC`, disable line wrap during redraw (`\033[?7l` in `tui_enter`, restored with `\033[?7h` in `tui_cleanup`) while keeping lines under 66 columns so `\033[nA` cursor-up redraws never leave duplicate header lines behind, and restore `stty "$TUI_OLD_STTY"` + cursor (`\033[?25h`) in `INT`/`TERM`/`HUP`/`EXIT` traps before closing FD 3.

## Why This Matters

A bashism, CRLF regression, or stdin-reopening bug introduced on a permissive host breaks Windows Git Bash hook execution, strict `dash` systems, or piped `curl | sh` wizards unless static checks and FD-3 runtime tests enforce POSIX behavior.

## When to Apply

Apply whenever editing heredocs, file writers, rate logic, interactive prompts, or test assertions in `install.sh` or `tests/*.sh`.

## Examples

```sh
check_no_cr() {
    [ "$(LC_ALL=C tr -cd '\r' < "$1" | wc -c)" -eq 0 ] && return 0
    echo "fakeauthor: error: CR bytes found in $1; LF-only output required" >&2
    exit 1
}
```

## References

0
