#!/bin/sh
# Run tests/t*.sh in sorted order; stop on first failure.

set -eu
cd "$(dirname "$0")/.."

n=0
for t in tests/t*.sh; do
    n=$((n + 1))
    echo "== $t"
    sh "$t"
done
echo "ok: $n tests"
