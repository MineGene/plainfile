#!/bin/bash
# Installs a pinned, checksum-verified XcodeGen into build/tools and prints
# the path to its binary. Builds never use whatever version Homebrew serves.
#
# To update: change VERSION, download the new xcodegen.zip from
# https://github.com/yonaskolb/XcodeGen/releases, run `shasum -a 256` on it
# and update SHA256.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="2.46.0"
SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
URL="https://github.com/yonaskolb/XcodeGen/releases/download/${VERSION}/xcodegen.zip"

dest="build/tools/xcodegen-${VERSION}"
binary="$dest/xcodegen/bin/xcodegen"

if [ ! -x "$binary" ]; then
  mkdir -p "$dest"
  zip="$dest/xcodegen.zip"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 -o "$zip" "$URL"
  actual=$(shasum -a 256 "$zip" | cut -d' ' -f1)
  if [ "$actual" != "$SHA256" ]; then
    rm -f "$zip"
    echo "::error::XcodeGen download checksum mismatch (expected $SHA256, got $actual)" >&2
    exit 1
  fi
  unzip -q -o "$zip" -d "$dest"
  rm -f "$zip"
fi

echo "$binary"
