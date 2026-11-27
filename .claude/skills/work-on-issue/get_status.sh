#!/usr/bin/env bash
# Prints the built-in Status of an issue of this repository (Backlog, Todo,
# In progress, In review, Done, Not planned, Duplicate), or nothing if the
# issue has no status. Counterpart of set_status.sh; uses GraphQL because
# gh has no subcommand for it.
#
#   get_status.sh <issue number>
#   get_status.sh 4        # -> Todo
set -euo pipefail

number=${1:?issue number}

repo=$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"')
read -r owner name <<<"$repo"

gh api graphql \
  -F owner="$owner" -F name="$name" -F number="$number" \
  -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        issue(number: $number) { status { name } }
      }
    }' --jq '.data.repository.issue.status.name // ""'
