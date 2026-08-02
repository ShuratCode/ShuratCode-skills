#!/usr/bin/env bash
# test.sh — run every plugin test suite (plugins/*/tests/test-*.sh).
#
# A suite is any executable-or-not bash file matching that glob. It must print
# its own results and exit non-zero on failure; nothing here inspects output.

set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
RAN=0

while IFS= read -r t; do
  RAN=$((RAN + 1))
  if bash "$t"; then
    printf '\033[32mPASS\033[0m %s\n' "$t"
  else
    printf '\033[31mFAIL\033[0m %s\n' "$t"
    FAIL=$((FAIL + 1))
  fi
done < <(find plugins -path '*/tests/test-*.sh' | sort)

echo
if [ "$RAN" -eq 0 ]; then
  echo "No test suites found."
  exit 0
fi
if [ "$FAIL" -gt 0 ]; then
  printf '\033[31m%d of %d suite(s) failed.\033[0m\n' "$FAIL" "$RAN"
  exit 1
fi
printf '\033[32mAll %d suite(s) passed.\033[0m\n' "$RAN"
