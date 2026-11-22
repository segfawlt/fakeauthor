# Learnings Index

Indexed catalog of durable lessons captured by the `compound` skill. Check entries with relevant
tags before non-trivial work.

## Pending Terms

- `chain invariant` — every skip branch in `commit-msg` must fall through to `chain "$@"` instead of bare `exit 0` so repo-local hooks still enforce checks.

## Promote Candidates

Lessons referenced 3+ times. Promotion is a user decision.

## architecture-patterns/

- [Global hooksPath Chaining and Skip Invariant](./architecture-patterns/global-hookspath-chaining-and-skip-invariant.md) — Global `core.hooksPath` overrides all `.git/hooks/*` events, requiring 13 chaining stubs, a `--local` fallback, and skip-path fallthrough. `#git-hooks #chaining #security`

## platform-issues/

- [commit-msg Scissor Stripping and interpret-trailers](./platform-issues/commit-msg-scissor-strip-and-interpret-trailers.md) — Use `commit-msg` with scissor+comment stripping and `git interpret-trailers` instead of `prepare-commit-msg` + `awk` so empty-editor aborts and trailer blocks stay intact. `#git-hooks #trailers #editor`
- [Git Shell Alias GIT_PREFIX and NO_FAKEAI](./platform-issues/git-shell-alias-prefix-and-no-fakeai.md) — Git `!` aliases chdir to the worktree root unless restoring `$GIT_PREFIX` and must export `NO_FAKEAI=1` to avoid double-attributing commits. `#git-alias #author-mode`
- [POSIX sh Portability and CRLF Guard](./platform-issues/posix-sh-portability-and-crlf-guard.md) — Bash-as-sh hosts mask `$'\r'` bashisms while Windows CRLF checkouts break hooks; enforce POSIX `tr -cd '\r'` byte checks, PID-seeded `awk`, and isolated test sandboxes. `#posix-sh #crlf #testing`
