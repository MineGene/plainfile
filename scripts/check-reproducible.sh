#!/bin/bash
# Builds the app twice, from two copies of the source at different paths,
# and fails unless both builds have the same digest (scripts/app-digest.sh).
# Proves that the published app can be rebuilt from source by anyone.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
scripts/app-digest.sh build/Release/Plainfile.app > build/digest-a.txt

work=$(mktemp -d)
other="${RUNNER_TEMP:-$(mktemp -d)}/rebuild-elsewhere/plainfile"
rm -rf "$other"
git clone --quiet --no-checkout . "$other"
git -C "$other" checkout --quiet --detach "$(git rev-parse HEAD)"
(cd "$other" && scripts/build-app.sh >/dev/null && scripts/app-digest.sh build/Release/Plainfile.app) > build/digest-b.txt

# Explains a difference: for programs, their UUIDs and any text (usually a
# path) found in only one build; for other files, size and first differing byte.
explain() {
  local rel="$1" a="build/Release/Plainfile.app/${1#./}" b="$other/build/Release/Plainfile.app/${1#./}"
  if file -b "$a" | grep -q "Mach-O"; then
    echo "::error::$rel UUIDs: $(dwarfdump --uuid "$a" | awk '{print $2}') vs $(dwarfdump --uuid "$b" | awk '{print $2}')"
    diff <(strings -a -n 4 "$a" | sort -u) <(strings -a -n 4 "$b" | sort -u) | grep -E '^[<>]' | head -n 8 \
      | while IFS= read -r line; do echo "::error::$rel only in build ${line:0:1}: ${line:2:200}"; done
    # Which sections differ (after removing signatures, as the digest does).
    local ua="$work/a.bin" ub="$work/b.bin"
    cp "$a" "$ua"; cp "$b" "$ub"
    codesign --remove-signature "$ua" 2>/dev/null || true
    codesign --remove-signature "$ub" 2>/dev/null || true
    size -m -x "$ua" | awk '/^Segment/ {seg=$2; sub(":","",seg)} /^\tSection/ {sec=$2; sub(":","",sec); print seg, sec}' \
      | while read -r seg sec; do
          if ! cmp -s <(otool -X -s "$seg" "$sec" "$ua") <(otool -X -s "$seg" "$sec" "$ub"); then
            echo "::error::$rel section $seg,$sec differs (sizes: $(otool -X -s "$seg" "$sec" "$ua" | wc -l) vs $(otool -X -s "$seg" "$sec" "$ub" | wc -l) lines)"
          fi
        done
    diff <(otool -l "$ua" | grep -v -E 'uuid') <(otool -l "$ub" | grep -v -E 'uuid') | grep -E '^[<>]' | head -n 6 \
      | while IFS= read -r line; do echo "::error::$rel load command ${line:0:1}: ${line:2:200}"; done
  else
    echo "::error::$rel sizes: $(stat -f %z "$a") vs $(stat -f %z "$b"); first difference: $(cmp "$a" "$b" | head -n 1)"
    diff <(strings -a -n 8 "$a" | sort -u) <(strings -a -n 8 "$b" | sort -u) | grep -E '^[<>]' | head -n 4 \
      | while IFS= read -r line; do echo "::error::$rel only in build ${line:0:1}: ${line:2:200}"; done
  fi
}

if diff -u build/digest-a.txt build/digest-b.txt > build/digest.diff; then
  echo "Reproducible. App digest: $(shasum -a 256 build/digest-a.txt | cut -d' ' -f1)"
else
  echo "::error::The two builds differ, so the app isn't reproducible yet."
  grep -E '^[-+][^-+]' build/digest.diff | sed -E 's/^[-+][0-9a-f:]+  //' | sort -u | head -n 10 \
    | while IFS= read -r path; do echo "::error::Differs between builds: $path"; explain "$path"; done
  exit 1
fi
