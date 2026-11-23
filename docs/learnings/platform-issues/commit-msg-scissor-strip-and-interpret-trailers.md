---
title: commit-msg Scissor Stripping and interpret-trailers
category: platform-issues
module: install.sh
tags: [git-hooks, trailers, editor]
problem_type: logic-error
date: 2026-11-23
last_updated: 2026-11-24
---

# commit-msg Scissor Stripping and interpret-trailers

## Problem

Inserting trailers in `prepare-commit-msg` with custom `awk` text manipulation broke interactive `git commit` workflows, `-s` sign-off trailer blocks, custom `core.commentChar`, and prose mentioning `Co-authored-by`.

## Symptoms

Observed against `git 2.56.1`:
- Quitting an empty editor (`GIT_EDITOR=true git commit`) succeeded (`rc=0`) with subject `Co-Authored-By: Claude <noreply@anthropic.com>` instead of aborting.
- Typing a subject on line 1 in the editor produced `fix login\nCo-Authored-By: ...` with no blank line and empty `%(trailers)`.
- `git commit -s -m "fix bug"` placed `Signed-off-by:` outside the final trailer block (`%(trailers)` omitted `Signed-off-by`).
- On `commit-msg`, checking `git stripspace --strip-comments` directly on `git commit -v` returned 117 bytes of diff text even when the user left the message empty (`RAW_LEN=117`).

## What Didn't Work

1. Appending trailers in `prepare-commit-msg` before `/^#/`: runs before the editor opens, breaks `core.commentChar=;`, fails on CRLF trailing lines, and cannot merge cleanly with `Signed-off-by:`.
2. Bare `git stripspace --strip-comments < "$1"` on `commit-msg`: fails to strip the diff following git's `-v` scissor marker (`-- >8 --`).
3. Unanchored case-insensitive `grep -i Co-authored-by`: false-positives when commit prose mentions `Co-authored-by`.
4. Using `--if-exists doNothing` when multi-co-author support (`claude,copilot,codex`) or human co-authors are present: matches on trailer key only and drops subsequent `Co-Authored-By:` entries.

## Solution

1. Move trailer insertion to `commit-msg` (which runs after the editor closes).
2. Strip scissor diffs (`sed '/^[^[:space:]]* -\{1,\} >8 -\{1,\}$/,$d' "$1"`) before piping into `git stripspace --strip-comments`; if empty, skip to `chain "$@"`.
3. Skip `$gitdir/MERGE_HEAD` and `$gitdir/SQUASH_MSG` using `git rev-parse --git-dir` (handles linked worktrees).
4. Append trailers in a comma-delimited loop using `git interpret-trailers --in-place --if-exists addIfDifferent --trailer "$key: $name <$email>" "$1"` without touching `"$@"` (no `set --`).

## Why This Works

- Leaving empty messages untouched lets git abort bare `git commit` and `git commit -v` (verified with `core.commentChar=;`, `rc=1`).
- `git interpret-trailers --if-exists addIfDifferent` handles blank-line separation, CRLF `-F` files, `Signed-off-by` merging, `core.commentChar`, multi-co-author trailers, human co-authors, and `--amend` deduplication cleanly.

## Prevention

Keep `tests/t02_hook.sh` and `tests/t03_guards.sh` covering empty-editor abort (normal and `-v` with `core.commentChar=;`), line-1 editor input, `-s`, CRLF `-F`, prose mentions, and merge/squash states.

## References

0
