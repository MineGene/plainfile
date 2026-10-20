#!/bin/bash
# Checks a built Plainfile.app: structure, architectures, signature and
# entitlements. Fails if any network entitlement appears anywhere.
# Usage: scripts/check-app.sh path/to/Plainfile.app
set -euo pipefail

app="${1:?usage: check-app.sh path/to/Plainfile.app}"
service="$app/Contents/XPCServices/PlainfileParser.xpc"
fail() { echo "::error::$*"; exit 1; }

[ -d "$app" ] || fail "App not found at $app"
[ -d "$service" ] || fail "Parser service is not embedded at Contents/XPCServices"

echo "== Architectures"
for binary in "$app/Contents/MacOS/Plainfile" "$service/Contents/MacOS/PlainfileParser"; do
  archs=$(lipo -archs "$binary")
  echo "$binary: $archs"
  [ "$archs" = "arm64" ] || fail "$binary should be Apple silicon only, found: $archs"
done

echo "== Icon"
icon=$(plutil -extract CFBundleIconName raw "$app/Contents/Info.plist" 2>/dev/null || true)
[ "$icon" = "AppIcon" ] || fail "App icon isn't set (CFBundleIconName is '${icon:-missing}')"
[ -f "$app/Contents/Resources/AppIcon.icns" ] || fail "App icon fallback (AppIcon.icns) is missing"
echo "AppIcon present"

echo "== Signature"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --verbose=2 "$app" 2>&1 | grep -q "flags=.*runtime" || fail "Hardened runtime is not enabled"

check_entitlements() {
  local bundle="$1" label="$2"
  local ents
  ents=$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null)
  echo "-- $label"
  echo "$ents" | plutil -p - || true
  echo "$ents" | grep -q "com.apple.security.app-sandbox" || fail "$label is not sandboxed"
  if echo "$ents" | grep -q "com.apple.security.network"; then
    fail "$label has a network entitlement. Plainfile must never have network access."
  fi
  local weak
  weak=$(echo "$ents" | grep -oE "[a-z.-]*(disable-library-validation|allow-jit|allow-unsigned-executable-memory|get-task-allow)" | sort -u | tr '\n' ' ' || true)
  if [ -n "$weak" ]; then
    fail "$label has a weakening entitlement: $weak"
  fi
}

echo "== Entitlements"
check_entitlements "$app" "App"
check_entitlements "$service" "Parser service"
if codesign -d --entitlements - --xml "$service" 2>/dev/null | grep -q "com.apple.security.files"; then
  fail "Parser service must not have file-access entitlements"
fi

echo "All checks passed."
