#!/bin/bash
# Selects the exact Xcode version pinned in .xcode-version, so every build
# (CI, release, and anyone rebuilding to verify a release) uses the same one.
# In GitHub Actions it exports DEVELOPER_DIR for later steps; locally it
# prints the export line to use.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(tr -d '[:space:]' < .xcode-version)
for dir in "/Applications/Xcode_${version}.app" "/Applications/Xcode-${version}.app" "/Applications/Xcode.app"; do
  [ -d "$dir" ] || continue
  actual=$(DEVELOPER_DIR="$dir/Contents/Developer" xcodebuild -version | awk 'NR==1 {print $2}')
  if [ "$actual" = "$version" ]; then
    echo "Using Xcode $actual at $dir"
    if [ -n "${GITHUB_ENV:-}" ]; then
      echo "DEVELOPER_DIR=$dir/Contents/Developer" >> "$GITHUB_ENV"
    else
      echo "export DEVELOPER_DIR=\"$dir/Contents/Developer\""
    fi
    exit 0
  fi
done

installed=$(ls -d /Applications/Xcode*.app 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')
echo "::error::Xcode $version (pinned in .xcode-version) isn't installed. Found: ${installed:-none}"
exit 1
