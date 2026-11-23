---
title: Git Shell Alias GIT_PREFIX and NO_FAKEAUTHOR
category: platform-issues
module: install.sh
tags: [git-alias, author-mode]
problem_type: integration-issue
date: 2026-11-23
last_updated: 2026-11-24
---

# Git Shell Alias GIT_PREFIX and NO_FAKEAUTHOR

## Problem

A `!f(){ GIT_AUTHOR_NAME='...' GIT_AUTHOR_EMAIL='...' git "$@"; };f` git alias fails when invoked from a subdirectory with relative pathspecs and double-attributes commits when the `commit-msg` hook is active.

## Symptoms

- Running `git claude commit file.txt -m "from subdir"` inside `sub/` exited `1` with `error: pathspec 'file.txt' did not match any file(s) known to git`.
- Running `git claude commit -m "author mode"` produced `Author: Claude <noreply@anthropic.com>` AND appended `Co-Authored-By: Claude <noreply@anthropic.com>` in the message body.

## What Didn't Work

Bare `!f(){ GIT_AUTHOR_NAME='...' GIT_AUTHOR_EMAIL='...' git "$@"; };f` without restoring the caller directory or disabling the hook.

## Solution

Restore `$GIT_PREFIX` when non-empty and set `NO_FAKEAUTHOR=1` inside `build_alias_val` in `install.sh`:

```sh
!f(){ [ -n "$GIT_PREFIX" ] && cd "$GIT_PREFIX"; GIT_AUTHOR_NAME='N' GIT_AUTHOR_EMAIL='E' NO_FAKEAUTHOR=1 git "$@"; };f
```

## Why This Works

Git executes `!` shell aliases from the repository worktree root and passes the caller's relative subdirectory in `GIT_PREFIX`. Changing into `$GIT_PREFIX` (terminated by `;` so empty `GIT_PREFIX` does not short-circuit) restores relative path resolution, while `NO_FAKEAUTHOR=1` suppresses trailer injection during author-mode commits.

## Prevention

Verify any alias template change with `tests/t07_alias.sh` subdirectory commit and zero-trailer assertions.

## References

0
