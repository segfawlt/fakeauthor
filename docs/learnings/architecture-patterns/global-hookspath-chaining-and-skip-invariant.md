---
title: Global hooksPath Chaining and Skip Invariant
category: architecture-patterns
module: install.sh
tags: [git-hooks, chaining, security]
problem_type: design-decision
date: 2026-11-23
---

# Global hooksPath Chaining and Skip Invariant

## Context

Setting global `core.hooksPath` in git overrides every repository's `.git/hooks/` directory rather than augmenting it. In earlier designs, installing only `prepare-commit-msg` or returning `exit 0` early on opt-out paths silently disabled pre-existing repository hooks.

## Guidance

1. Install lightweight `exec` chaining stubs for all 13 standard client-side hooks alongside `commit-msg`, skipping high-frequency plumbing hooks (`reference-transaction`, `post-index-change`, `fsmonitor-watchman`).
2. Guard chaining with both `_FAKEAI_CHAINED=1` and canonical directory comparison (`pwd -P` on `dirname "$0"` vs `$(git rev-parse --git-common-dir)/hooks`) to prevent self-exec recursion.
3. Route every skip path in `commit-msg` (`NO_FAKEAI`, `fakeai.off`, `fakeai.rate`, `MERGE_HEAD`/`SQUASH_MSG`, empty commit messages, `devin`/unknown persona) through `chain "$@"`, never bare `exit 0`.
4. Provide `--local` per-repo installation because Python `pre-commit install` refuses to run while global `core.hooksPath` is set (whereas husky and lefthook use repo-local `core.hooksPath`).

## Why This Matters

- **Empirical verification (`git 2.56.1`):** Before setting global `core.hooksPath`, a repo `.git/hooks/pre-commit` exiting `1` blocked commits (`rc=1`); after setting global `core.hooksPath` without a `pre-commit` stub, git skipped the repo hook completely (`rc=0`).
- **Skip-path enforcement:** A user disabling fakeai in a work repository via `fakeai.off=true` or `NO_FAKEAI=1` still depends on that repository's `commit-msg` validator or sign-off check.
- **Stdin preservation:** `_FAKEAI_CHAINED=1 exec "$h" "$@"` keeps stdin intact for hooks such as `pre-push` (`tests/t05_chain.sh`).

## When to Apply

Apply whenever adding a new hook event, a new guard or early-exit branch in `emit_hook()`, or changing how `core.hooksPath` interacts with repository hook managers.

## Examples

```sh
chain() {
    [ "${_FAKEAI_CHAINED:-0}" = "1" ] && exit 0
    common=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
    h="$common/hooks/${0##*/}"
    [ -x "$h" ] || exit 0
    self_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || self_dir=""
    hook_dir=$(cd "$(dirname "$h")" 2>/dev/null && pwd -P) || hook_dir=""
    [ -n "$self_dir" ] && [ "$self_dir" = "$hook_dir" ] && exit 0
    _FAKEAI_CHAINED=1 exec "$h" "$@"
}
```

## References

0
