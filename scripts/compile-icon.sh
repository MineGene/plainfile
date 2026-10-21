#!/bin/bash
# Compiles the app icon (Design/AppIcon.icon, made in Apple's Icon Composer)
# into Plainfile/Resources/Assets.car and AppIcon.icns.
#
# Apple's asset compiler renders the icon slightly differently on every run,
# so compiling it in each build would make builds unreproducible. Instead it
# is compiled once, here, and the result is committed; builds copy it in
# unchanged. Run this whenever the icon's source changes (on a Mac with the
# pinned Xcode, or via the "Compile icon" workflow).
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun actool Design/AppIcon.icon \
  --compile "$out" \
  --platform macosx \
  --minimum-deployment-target "$(awk -F' = ' '/MACOSX_DEPLOYMENT_TARGET/ {gsub(/;/,"",$2); print $2; exit}' Plainfile.xcodeproj/project.pbxproj)" \
  --app-icon AppIcon \
  --include-all-app-icons \
  --output-partial-info-plist "$out/partial.plist" \
  --output-format human-readable-text --notices --warnings --errors

mkdir -p Plainfile/Resources
cp "$out/Assets.car" Plainfile/Resources/Assets.car
cp "$out/AppIcon.icns" Plainfile/Resources/AppIcon.icns
echo "Compiled icon:"
ls -l Plainfile/Resources/
shasum -a 256 Plainfile/Resources/Assets.car Plainfile/Resources/AppIcon.icns
