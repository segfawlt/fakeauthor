---
title: Batching git config Reads with --get-regexp
category: performance
module: install.sh
tags: [git-config, git-hooks, performance]
problem_type: design-decision
date: 2026-11-24
---

# Batching git config Reads with --get-regexp

## Context

`commit-msg` needs up to five `git config` keys per commit (`fakeauthor.off`, `fakeauthor.rate`, `fakeauthor.persona`, `fakeauthor.name`, `fakeauthor.email`), where spawning separate `git config` processes per key multiplies fork overhead (especially on MSYS2/Windows).

## Guidance

1. Read all keys in one call after checking `NO_FAKEAUTHOR`:
   `cfg_out=$(git config --get-regexp '^fakeauthor\.' 2>/dev/null || true)`
2. Parse lines top-to-bottom so higher-precedence scopes (`local`, `-c` overrides) overwrite earlier ones (`system`, `global`).
3. Handle lines without a separating space (`*" "*` mismatch) as bare valueless config keys (`[fakeauthor]\n\toff`): map bare `fakeauthor.off` to a `__BARE__` sentinel (treated as `true`), and clear `__BARE__` to empty string for string-valued keys (`rate`, `persona`, `name`, `email`).
4. For unrecognized `fakeauthor.off` values (such as `"maybe"` or `"TRUE"`), fall back to `git config --bool fakeauthor.off` so git's native boolean coercion and exit-128 error handling remain exact.

## Why This Matters

- **Empirical verification (`git 2.56.1`):** `git config --get-regexp '^fakeauthor\.'` lowercases section/variable names (`FakeAuthor.OFF` -> `fakeauthor.off`), appends `-c fakeauthor.off=false` after repo config entries, prints bare valueless `off` without any trailing space (`fakeauthor.off`), and prints empty values with one space (`fakeauthor.email `).
- **Skip invariant:** Every skip branch (`__BARE__`, `true`, fallback `--bool` `true`) must still invoke `chain "$@"`. See [Global hooksPath Chaining and Skip Invariant](../architecture-patterns/global-hookspath-chaining-and-skip-invariant.md).

## When to Apply

Apply whenever adding or modifying `fakeauthor.*` runtime config keys read inside `emit_hook()`.

## Examples

```sh
case "$cfg_line" in
    *" "*) cfg_k=${cfg_line%% *}; cfg_v=${cfg_line#* } ;;
    *)     cfg_k=$cfg_line; cfg_v="__BARE__" ;;
esac
```

## References

0
