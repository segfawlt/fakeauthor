---
title: POSIX sh Portability and CRLF Guard
category: platform-issues
module: tests/t08_bytes.sh
tags: [posix-sh, crlf, testing]
problem_type: design-decision
date: 2026-11-23
---

# POSIX sh Portability and CRLF Guard

## Context

On Linux hosts where `/bin/sh` symlinks to `bash` (observed `/usr/sbin/sh -> /usr/bin/bash`) and `dash`/`shellcheck` are absent, bashisms such as `$'\r'` execute silently in tests while failing on strict POSIX shells or Git Bash when files acquire CRLF line endings.

## Guidance

1. Pin `*.sh text eol=lf` in `.gitattributes` and check every generated file after write via POSIX `LC_ALL=C tr -cd '\r' | wc -c` (`check_no_cr` in `install.sh`), never bashism `$'\r'`.
2. In `tests/t08_bytes.sh`, construct the `$'\r'` scan pattern via `printf '$%s' "'\\\\r'"` so the test script itself contains zero literal bashism patterns, and test `check_no_cr` using an `awk`-poisoned installer copy whose heredoc bodies carry `\r`.
3. Seed `awk` rate randomness with PID + `rand()` (`srand(); x=rand(); srand(int(x*2147483647)+p)`) and coerce string rate inputs (`rv = r + 0`) after regex validation so rapid commits within one second do not share identical `time(NULL)` seeds and non-numeric configs do not string-compare as true.
4. Isolate test sandboxes by setting `HOME`, `XDG_CONFIG_HOME`, and `GIT_CONFIG_NOSYSTEM=1` (while unsetting `GIT_CONFIG_GLOBAL`) so tests never leak host `/etc/gitconfig` or `~/.config/fakeai`.

## Why This Matters

A bashism or CRLF regression introduced on a permissive host breaks Windows Git Bash hook execution or strict `dash` systems silently unless both static checks and CR-poisoned runtime checks enforce POSIX hygiene.

## When to Apply

Apply whenever editing heredocs, file writers, rate logic, or test assertions in `install.sh` or `tests/*.sh`.

## Examples

```sh
check_no_cr() {
    [ "$(LC_ALL=C tr -cd '\r' < "$1" | wc -c)" -eq 0 ] && return 0
    echo "fakeai: error: CR bytes found in $1; LF-only output required" >&2
    exit 1
}
```

## References

0
