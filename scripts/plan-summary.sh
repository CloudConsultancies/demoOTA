#!/usr/bin/env bash
# Writes a Markdown summary of a saved Terraform plan to stdout: the
# resource changes as a table, then the full plan in a collapsed block.
#
#   scripts/plan-summary.sh <stack dir> <plan file> <stack name>
set -euo pipefail

dir=$1 plan=$2 stack=$3
# GitHub comments hold at most 65,536 characters
max_plan_chars=55000

json=$(terraform -chdir="$dir" show -json "$plan")
text=$(terraform -chdir="$dir" show -no-color "$plan")

changes=$(jq -r '
  [.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])]
  | if length == 0 then "No changes."
    else (["| Action | Resource |", "|---|---|"]
          + map("| \(.change.actions | join(", ")) | `\(.address)` |"))
         | join("\n")
    end' <<<"$json")

counts=$(grep -E '^(Plan:|No changes\.)' <<<"$text" || true)

if (( ${#text} > max_plan_chars )); then
  text="${text:0:max_plan_chars}

... truncated: see the workflow log for the full plan."
fi

cat <<MD
### Terraform plan: \`$stack\`

${counts:-No summary line found.}

$changes

<details><summary>Full plan</summary>

\`\`\`
$text
\`\`\`

</details>

Commit \`${GITHUB_SHA:-local}\`. Applied on merge to \`main\` (re-planned there).
MD
