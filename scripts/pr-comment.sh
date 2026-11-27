#!/usr/bin/env bash
# Creates or updates one comment on a pull request, found by a marker
# line, so every push updates the same comment instead of adding one.
# Needs GH_TOKEN with pull-requests: write.
#
#   scripts/pr-comment.sh <pull request number> <marker> <body file>
set -euo pipefail

pr=$1 marker=$2 file=$3

body=$(printf '%s\n%s\n' "$marker" "$(cat "$file")")

id=$(gh api --paginate "repos/{owner}/{repo}/issues/$pr/comments" \
  --jq ".[] | select(.user.type == \"Bot\" and (.body | startswith(\"$marker\"))) | .id" \
  | tail -n 1)

if [[ -n "$id" ]]; then
  gh api --method PATCH "repos/{owner}/{repo}/issues/comments/$id" -f body="$body" >/dev/null
  echo "Updated comment $id on #$pr."
else
  gh api --method POST "repos/{owner}/{repo}/issues/$pr/comments" -f body="$body" >/dev/null
  echo "Created a comment on #$pr."
fi
