---
title: Windows Path Canonicalization and Hook Basename Stripping
category: platform-issues
module: install.sh
tags: [windows, paths, git-hooks, posix-sh]
problem_type: bug-fix
date: 2026-11-24
---

# Windows Path Canonicalization and Hook Basename Stripping

## Problem

`canon_path()` in `install.sh` and `emit_ctl()` corrupted non-existent Windows drive paths (`Z:/nonexistent/dir`), while `${0##*/}` chaining and `trim_ws()` broke on backslashes and CRLF line inputs.

## Symptoms

- On a non-existent drive path `Z:/nonexistent/dir`, `dirname "Z:/nonexistent"` yields `Z:` and `dirname "Z:"` yields `.`. Because `[ -d "." ]` is true, `canon_path` terminated at `.` and prepended `$(pwd -P)`, producing `$PWD/Z:/nonexistent/dir`.
- When `git.exe` passes backslash paths in `$0` (`C:\...\hooks\pre-commit`), `${0##*/}` leaves the full string intact instead of `pre-commit`.
- CRLF lines read into `trim_ws()` (`FAKEAUTHOR_TTY` from Windows files) retained trailing `\r`, causing `case` option matching (`"1\r"`) to fail.

## What Didn't Work

1. Stopping the `canon_path` walk only on `/` or `.` without checking `[A-Za-z]:` / `[A-Za-z]:/` drive roots.
2. Stripping only `/` via `${0##*/}` in `chain()` and `emit_chain_stub()`.

## Solution

1. Normalize `\` to `/` first via `norm_slashes` (`tr '\\' '/'`), stop the `canon_path` walk on `[A-Za-z]:|[A-Za-z]:/` or when `dirname "$p"` equals `$p`, promote bare `[A-Za-z]:` parents to `[A-Za-z]:/` before `[ -d "$p" ]`, and return `orig_p` if the root is not a directory.
2. Strip both slash and backslash prefixes in `chain()` and `emit_chain_stub()`:
   `hook_name=${0##*/}; hook_name=${hook_name##*\\}`
3. Strip `"$CR_CH"` (`$(printf '\r')`) alongside spaces and tabs in `trim_ws()`.

## Why This Works

Stopping on Windows drive roots prevents `dirname "Z:"` from collapsing into `.` and picking up `$PWD`, while two-stage parameter expansion extracts hook basenames regardless of host path separator using pure POSIX `sh`.

## Prevention

Keep `tests/t10_windows.sh` asserting `canon_path` on `Z:/nonexistent/dir` and `Z:\nonexistent\dir`, backslash `FAKEAUTHOR_DIR`, CRLF `FAKEAUTHOR_TTY` inputs, and backslash `$0` extraction in generated hooks and stubs.

## References

0
