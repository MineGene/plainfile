#!/bin/bash
# Prints a digest of an app bundle: every file's SHA-256 and path, sorted.
# Two builds of the same source should print exactly the same lines.
#
# Ignored, because they can't be reproduced across machines and carry no
# trust: ad-hoc code signatures (they name no identity) and the build
# machine's macOS version (Info.plist BuildMachineOSBuild). Everything that
# runs is compared byte for byte.
# Usage: scripts/app-digest.sh path/to/Plainfile.app
set -euo pipefail

app=$(cd "${1:?usage: app-digest.sh path/to/Plainfile.app}" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ditto "$app" "$work/app"
cd "$work/app"

while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q "Mach-O"; then
    codesign --remove-signature "$f" 2>/dev/null || true
  fi
done < <(find . -type f -perm -u+x -print0)
find . -type d -name _CodeSignature -prune -exec rm -rf {} +

while IFS= read -r -d '' plist; do
  /usr/libexec/PlistBuddy -c 'Delete :BuildMachineOSBuild' "$plist" >/dev/null 2>&1 || true
  plutil -convert xml1 "$plist"
done < <(find . -name Info.plist -print0)

find . \( -type f -o -type l \) -print0 | LC_ALL=C sort -z |
  while IFS= read -r -d '' f; do
    if [ -L "$f" ]; then
      echo "link:$(readlink "$f")  $f"
    else
      echo "$(shasum -a 256 "$f" | cut -d' ' -f1)  $f"
    fi
  done
