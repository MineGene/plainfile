#!/bin/bash
# Turns compiler and XCTest error lines in a log into GitHub annotations,
# so failures show on the check itself without opening the full log.
# Usage: scripts/annotate-errors.sh <logfile>
set -uo pipefail
log="${1:?usage: annotate-errors.sh <logfile>}"
root="${GITHUB_WORKSPACE:-$(pwd)}/"

grep -E '^[^ ]+\.swift:[0-9]+(:[0-9]+)?: error: ' "$log" \
  | sort -u | head -n 50 \
  | while IFS= read -r line; do
      file=${line%%:*}
      rest=${line#*:}
      lineno=${rest%%:*}
      message=${line#*: error: }
      message=${message//'%'/'%25'}
      echo "::error file=${file#"$root"},line=${lineno}::${message}"
    done
# Failures without a file location (for example a crashed test run).
grep -E '^(error: |Test Suite .* failed|.*Fatal error)' "$log" | head -n 10 \
  | while IFS= read -r line; do echo "::error::${line//'%'/'%25'}"; done
# A crash (e.g. signal 5) prints no error line; name the test that was running.
if grep -q "unexpected signal" "$log"; then
  last=$(grep -E "^Test Case '.*' started" "$log" | tail -n 1)
  [ -n "$last" ] && echo "::error::Crashed during: ${last}"
  grep -n -E "Fatal error|Assertion failed|Precondition failed|EXC_|Crash" "$log" | head -n 5 \
    | while IFS= read -r l; do echo "::error::${l//'%'/'%25'}"; done
fi
exit 0
