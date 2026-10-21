#!/bin/bash
# Fails if a pull request changes security-sensitive files without the
# maintainer's review (the "maintainer-reviewed" label).
#
# Sensitive files are those that define what the app is allowed to do, how
# it is built and released, or how AI sessions are instructed. Most code
# can't escape the app's sandbox even if it's wrong; these files can change
# the sandbox itself.
# Usage: scripts/check-sensitive.sh <base> <head> <comma-separated labels>
set -euo pipefail

base="${1:?usage: check-sensitive.sh <base> <head> <labels>}"
head="${2:?usage: check-sensitive.sh <base> <head> <labels>}"
labels="${3:-}"

sensitive='^(Config/|\.github/|scripts/|PlainfileParser/|Plainfile\.xcodeproj/|Plainfile/Resources/|Packages/PlainfileCore/Package\.swift$|Packages/PlainfileCore/Sources/PlainfileCore/ParserServiceProtocol\.swift$|\.xcode-version$|CLAUDE\.md$)'

changed=$(git diff --name-only "$base...$head" | grep -E "$sensitive" || true)
if [ -z "$changed" ]; then
  echo "No sensitive files changed."
  exit 0
fi

echo "Sensitive files changed:"
echo "$changed" | sed 's/^/  /'
if [[ ",$labels," == *",maintainer-reviewed,"* ]]; then
  echo "The maintainer has reviewed this version (label: maintainer-reviewed)."
  exit 0
fi
echo "$changed" | head -n 20 | while IFS= read -r f; do
  echo "::error file=$f::Sensitive file changed. The maintainer must review it and add the 'maintainer-reviewed' label."
done
exit 1
