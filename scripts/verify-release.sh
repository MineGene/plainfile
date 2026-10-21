#!/bin/bash
# Verifies a Plainfile release without trusting the maintainer, the AI that
# wrote the code, or the download page. Run it on a Mac:
#
#   scripts/verify-release.sh 0.1.1            # check the download
#   scripts/verify-release.sh 0.1.1 --rebuild  # also rebuild from source
#
# It checks that:
#   1. the DMG matches its published SHA-256 checksum
#   2. GitHub's signed build record (attestation, logged publicly by Sigstore)
#      says this DMG and its app digest were built by this repository's
#      release workflow (needs the GitHub CLI, "gh")
#   3. the app inside the DMG matches the attested app digest
#   4. the app and its file reader have no network access, and the reader
#      can't open files on its own
#   5. with --rebuild: building the release's source with the pinned Xcode
#      gives exactly the same app
set -euo pipefail

repo="MineGene/plainfile"
version="${1:?usage: verify-release.sh <version, e.g. 0.1.1> [--rebuild]}"
version="${version#v}"
rebuild="${2:-}"

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
mount=""
cleanup() {
  [ -n "$mount" ] && hdiutil detach -quiet "$mount" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; exit 1; }

dmg="Plainfile-$version.dmg"
digest="Plainfile-$version-app-digest.txt"
base="https://github.com/$repo/releases/download/v$version"

echo "Downloading release v$version…"
for f in "$dmg" "$dmg.sha256" "$digest"; do
  curl --fail --silent --show-error --location --proto '=https' -o "$work/$f" "$base/$f" \
    || fail "couldn't download $f (does v$version exist?)"
done

echo "1. Checksum"
(cd "$work" && shasum -a 256 -c "$dmg.sha256" >/dev/null) || fail "the DMG doesn't match its checksum"
pass "the DMG matches its published SHA-256"

echo "2. Build record (attestation)"
if command -v gh >/dev/null; then
  for f in "$dmg" "$digest"; do
    gh attestation verify "$work/$f" --repo "$repo" >/dev/null 2>&1 \
      || fail "no valid attestation for $f from $repo"
  done
  pass "both files were built by $repo's release workflow (Sigstore-signed)"
else
  echo "  – skipped: install the GitHub CLI (gh) to check this, or check by hand at"
  echo "    https://github.com/$repo/attestations"
fi

echo "3. The app inside the DMG"
mount=$(hdiutil attach -nobrowse -readonly -noautoopen "$work/$dmg" | awk -F'\t' '/\/Volumes\// {print $NF}')
[ -d "$mount/Plainfile.app" ] || fail "no Plainfile.app inside the DMG"
"$here/app-digest.sh" "$mount/Plainfile.app" > "$work/actual-digest.txt"
diff -q "$work/$digest" "$work/actual-digest.txt" >/dev/null \
  || fail "the app in the DMG doesn't match the attested app digest"
pass "the app matches the attested digest, file by file"

echo "4. Permissions"
app="$mount/Plainfile.app"
service="$app/Contents/XPCServices/PlainfileParser.xpc"
for bundle in "$app" "$service"; do
  ents=$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null)
  echo "$ents" | grep -q "com.apple.security.app-sandbox" || fail "$(basename "$bundle") isn't sandboxed"
  echo "$ents" | grep -q "com.apple.security.network" && fail "$(basename "$bundle") has network access"
done
codesign -d --entitlements - --xml "$service" 2>/dev/null | grep -q "com.apple.security.files" \
  && fail "the file reader has file access"
pass "sandboxed, no network access; the file reader can't open files"

if [ "$rebuild" = "--rebuild" ]; then
  echo "5. Rebuild from source"
  git clone --quiet "https://github.com/$repo.git" "$work/src"
  git -C "$work/src" checkout --quiet "v$version"
  xcode=$(cd "$work/src" && scripts/select-xcode.sh) \
    || fail "the rebuild needs Xcode $(cat "$work/src/.xcode-version"), as pinned in .xcode-version"
  (cd "$work/src" && eval "$(tail -n 1 <<<"$xcode")" \
    && PLAINFILE_VERSION="$version" scripts/build-app.sh >/dev/null \
    && scripts/app-digest.sh build/Release/Plainfile.app) > "$work/rebuilt-digest.txt" \
    || fail "the rebuild failed"
  diff -q "$work/$digest" "$work/rebuilt-digest.txt" >/dev/null \
    || fail "rebuilding v$version from source gives a different app"
  pass "rebuilding the source gives exactly the same app"
fi

echo
echo "Plainfile $version verified."
