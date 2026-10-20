#!/bin/bash
# Builds an Apple-silicon, ad-hoc-signed Release app into
# build/Release/Plainfile.app using only Xcode. Used by CI and releases;
# also works on any Apple-silicon Mac with Xcode installed.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${PLAINFILE_VERSION:-}"
extra=()
if [ -n "$version" ]; then
  extra+=("MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=${GITHUB_RUN_NUMBER:-1}")
fi

mkdir -p build
set +e
xcodebuild build \
  -project Plainfile.xcodeproj \
  -scheme Plainfile \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  ${extra[@]+"${extra[@]}"} \
  > build/xcodebuild.log 2>&1
status=$?
set -e
grep -E "warning:|error:|BUILD (SUCCEEDED|FAILED)" build/xcodebuild.log || true
if [ "$status" -ne 0 ]; then
  tail -n 80 build/xcodebuild.log
  scripts/annotate-errors.sh build/xcodebuild.log
  echo "::error::xcodebuild failed"
  exit 1
fi

mkdir -p build/Release
rm -rf build/Release/Plainfile.app
ditto build/DerivedData/Build/Products/Release/Plainfile.app build/Release/Plainfile.app
echo "Built build/Release/Plainfile.app"
