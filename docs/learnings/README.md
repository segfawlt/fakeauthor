# Learnings Index

Indexed catalog of durable lessons captured by the `compound` skill. Check entries with relevant
tags before non-trivial work.

## Pending Terms

- `chain invariant` — every skip branch in `commit-msg` must fall through to `chain "$@"` instead of bare `exit 0` so repo-local hooks still enforce checks.

## Promote Candidates

Lessons referenced 3+ times. Promotion is a user decision.

## architecture-patterns/

- [Global hooksPath Chaining and Skip Invariant](./architecture-patterns/global-hookspath-chaining-and-skip-invariant.md) — Global `core.hooksPath` overrides all `.git/hooks/*` events, requiring 13 chaining stubs, a `--local` fallback, and skip-path fallthrough. `#git-hooks #chaining #security`

## performance/

- [Batching git config Reads with --get-regexp](./performance/batching-git-config-get-regexp.md) — Read all `fakeauthor.*` keys in one `git config --get-regexp` call while handling bare valueless keys and `--bool` fallback. `#git-config #git-hooks #performance`

## platform-issues/

- [commit-msg Scissor Stripping and interpret-trailers](./platform-issues/commit-msg-scissor-strip-and-interpret-trailers.md) — Use `commit-msg` with CR+scissor+comment stripping and `git interpret-trailers --if-exists addIfDifferent` instead of `prepare-commit-msg` + `awk` so empty-editor aborts, CRLF `commit -v` handling, multi-co-author trailers, and trailer blocks stay intact. `#git-hooks #trailers #editor`
- [Git Shell Alias GIT_PREFIX and NO_FAKEAUTHOR](./platform-issues/git-shell-alias-prefix-and-no-fakeauthor.md) — Git `!` aliases chdir to the worktree root unless restoring `$GIT_PREFIX` and must export `NO_FAKEAUTHOR=1` to avoid double-attributing commits. `#git-alias #author-mode`
- [POSIX sh Portability and CRLF Guard](./platform-issues/posix-sh-portability-and-crlf-guard.md) — Bash-as-sh hosts mask `$'\r'` bashisms while Windows CRLF checkouts break hooks; enforce POSIX `tr -cd '\r'` byte checks, `[ \t]` instead of `[[:space:]]` against the `[[` scan, FD-3 TTY reads, PID-seeded `awk`, and isolated test sandboxes. `#posix-sh #crlf #testing`
- [Windows Path Canonicalization and Hook Basename Stripping](./platform-issues/windows-path-canonicalization-and-hook-basename.md) — Guard `canon_path` against `dirname "Z:"` returning `.`, strip both `/` and `\` from `$0` in hooks/stubs, and strip `\r` in `trim_ws`. `#windows #paths #git-hooks #posix-sh`
