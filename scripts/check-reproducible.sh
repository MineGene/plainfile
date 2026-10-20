#!/bin/bash
# Builds the app twice, from two copies of the source at different paths,
# and fails unless both builds have the same digest (scripts/app-digest.sh).
# Proves that the published app can be rebuilt from source by anyone.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
scripts/app-digest.sh build/Release/Plainfile.app > build/digest-a.txt

other="${RUNNER_TEMP:-$(mktemp -d)}/rebuild-elsewhere/plainfile"
rm -rf "$other"
git clone --quiet --no-checkout . "$other"
git -C "$other" checkout --quiet --detach "$(git rev-parse HEAD)"
(cd "$other" && scripts/build-app.sh >/dev/null && scripts/app-digest.sh build/Release/Plainfile.app) > build/digest-b.txt

if diff -u build/digest-a.txt build/digest-b.txt > build/digest.diff; then
  echo "Reproducible. App digest: $(shasum -a 256 build/digest-a.txt | cut -d' ' -f1)"
else
  echo "::error::The two builds differ, so the app isn't reproducible yet."
  grep -E '^[-+][^-+]' build/digest.diff | sed -E 's/^[-+][0-9a-f:]+  //' | sort -u | head -n 30 \
    | while IFS= read -r path; do echo "::error::Differs between builds: $path"; done
  exit 1
fi
