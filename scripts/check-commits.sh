#!/bin/bash
# Fails if any commit in a range would publish private details:
#   - an author or committer email that isn't a GitHub no-reply address
#   - a trailer (the "Key: value" lines at the end of a message) other than
#     the few allowed below, or one that carries a real email address.
# AI attribution (Co-authored-by: Claude <noreply@anthropic.com>) is allowed.
# Usage: scripts/check-commits.sh <base> <head>
set -euo pipefail

base="${1:?usage: check-commits.sh <base> <head>}"
head="${2:?usage: check-commits.sh <base> <head>}"

# A new branch push has no base; check just the pushed commit then.
if [[ "$base" =~ ^0+$ ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  range="$head^!"
else
  range="$base..$head"
fi

allowed_email='(^[0-9]+\+[A-Za-z0-9._-]+(\[bot\])?@users\.noreply\.github\.com$)|(^(noreply|support)@github\.com$)'
allowed_trailers='^(Signed-off-by|Co-authored-by|Fixes|Closes|Resolves|Refs|Claude-Session):'
# Trailer emails may also be the AI tool's own no-reply address.
allowed_trailer_email="$allowed_email|(^noreply@anthropic\.com\$)"

status=0
commits=$(git rev-list "$range")
[ -n "$commits" ] || { echo "No commits to check."; exit 0; }

for sha in $commits; do
  short=${sha:0:7}
  author=$(git log -1 --format=%ae "$sha")
  committer=$(git log -1 --format=%ce "$sha")
  for email in $(printf '%s\n%s\n' "$author" "$committer" | sort -u); do
    if ! [[ "$email" =~ $allowed_email ]]; then
      echo "::error::$short uses the email '$email'. Use your GitHub no-reply address (github.com/settings/emails)."
      status=1
    fi
  done

  while IFS= read -r trailer; do
    [ -n "$trailer" ] || continue
    shopt -s nocasematch
    if ! [[ "$trailer" =~ $allowed_trailers ]]; then
      shopt -u nocasematch
      echo "::error::$short has a trailer that isn't allowed: '$trailer'"
      status=1
    elif shopt -u nocasematch && [[ "$trailer" == *"<"*"@"*">"* ]]; then
      email=$(sed -E 's/.*<([^>]+)>.*/\1/' <<<"$trailer")
      if ! [[ "$email" =~ $allowed_trailer_email ]]; then
        echo "::error::$short has a trailer exposing the email '$email'."
        status=1
      fi
    fi
  done < <(git log -1 --format=%B "$sha" | git interpret-trailers --parse)
done

[ "$status" -eq 0 ] && echo "Checked $(wc -w <<<"$commits" | tr -d ' ') commit(s): no private details found."
exit "$status"
