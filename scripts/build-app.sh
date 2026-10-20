#!/bin/bash
# Builds an Apple-silicon, ad-hoc-signed Release app into
# build/Release/Plainfile.app using only Xcode. Used by CI and releases;
# also works on any Apple-silicon Mac with Xcode installed.
set -euo pipefail
cd "$(dirname "$0")/.."

# The build must be reproducible: the same source gives the same app on any
# machine (checked by scripts/check-reproducible.sh). So the build number
# comes from the source (its commit count), not from the CI run, and paths
# and timestamps are kept out of the binaries.
root=$(pwd)
derived="$root/build/DerivedData"
export ZERO_AR_DATE=1
# A fixed temporary folder: the compiler writes generated code (such as
# macro expansions) there, and a random path would leak into the build.
export TMPDIR=/tmp/plainfile-build
rm -rf "$TMPDIR" && mkdir -p "$TMPDIR"
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
extra=("CURRENT_PROJECT_VERSION=$build_number")
if [ -n "${PLAINFILE_VERSION:-}" ]; then
  extra+=("MARKETING_VERSION=$PLAINFILE_VERSION")
fi

mkdir -p build
set +e
xcodebuild build \
  -project Plainfile.xcodeproj \
  -scheme Plainfile \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES COPY_PHASE_STRIP=YES \
  GCC_GENERATE_DEBUGGING_SYMBOLS=NO DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  OTHER_SWIFT_FLAGS="-file-prefix-map $derived=/DerivedData -file-prefix-map $root=/Source" \
  OTHER_LDFLAGS="-Wl,-oso_prefix,$root/" \
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
