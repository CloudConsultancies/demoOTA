#!/usr/bin/env bash
# Sets the built-in Status of an issue of this repository (Backlog, Todo,
# In progress, In review, Done, Not planned, Duplicate). It is GitHub's
# issue status, not a Projects field and not a label; gh has no
# subcommand for it, so this uses GraphQL (setIssueStatus).
#
#   set_status.sh <issue number> "<status name>"
#   set_status.sh 4 "In progress"
set -euo pipefail

number=${1:?issue number}
status=${2:?status name, for example "In progress"}

repo=$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"')
read -r owner name <<<"$repo"

data=$(gh api graphql \
  -F owner="$owner" -F name="$name" -F number="$number" \
  -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        planningStatuses(first: 50) { nodes { id name } }
        issue(number: $number) { id }
      }
    }')

issue_id=$(jq -r '.data.repository.issue.id' <<<"$data")
status_id=$(jq -r --arg s "$status" \
  '.data.repository.planningStatuses.nodes[] | select((.name | ascii_downcase) == ($s | ascii_downcase)) | .id' <<<"$data")

if [[ -z "$status_id" ]]; then
  echo "Unknown status '$status'. Available:" >&2
  jq -r '.data.repository.planningStatuses.nodes[].name' <<<"$data" | sed 's/^/  /' >&2
  exit 1
fi

gh api graphql -f issue="$issue_id" -f status="$status_id" \
  -f query='
    mutation($issue: ID!, $status: ID!) {
      setIssueStatus(input: {issueId: $issue, statusId: $status}) {
        issue { number status { name } }
      }
    }' --jq '"#\(.data.setIssueStatus.issue.number): \(.data.setIssueStatus.issue.status.name)"'
