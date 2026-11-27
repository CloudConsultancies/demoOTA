#!/usr/bin/env bash
# Writes a Markdown cost estimate of a saved Terraform plan to stdout:
# the monthly cost before and after the plan, the difference, and the
# Infracost diff per resource in a collapsed block. Usage-based costs
# (S3 storage, requests) come from <stack dir>/infracost-usage.yml.
#
# The estimate is optional: without an Infracost API key (the
# INFRACOST_API_KEY environment variable, or `infracost auth login`
# locally) it prints a "skipped" note and exits 0.
#
#   scripts/cost-estimate.sh <stack dir> <plan file> <stack name>
set -euo pipefail

dir=$1 plan=$2 stack=$3
usage=$dir/infracost-usage.yml
# No "new version available" notice in the logs or the PR comment
export INFRACOST_SKIP_UPDATE_CHECK=true
work=$dir/.infracost
mkdir -p "$work"

skip() {
  echo "Cost estimate skipped: $1" >&2
  cat <<MD
### Cost estimate: \`$stack\`

Skipped: $1 See the \`cost-impact\` skill for a manual estimate.
MD
  exit 0
}

key=$("$(dirname "$0")/infracost-key.sh")
[[ -n "$key" ]] || skip "no Infracost API key (secret \`INFRACOST_API_KEY\`, see \`make infracost-github-secret\`)."

# Infracost v0.10 (CI pins 0.10.x). v2 is a different CLI (scan,
# inspect) without diff --path / output; INFRACOST points at a v0.10
# binary when v2 comes first on PATH.
infracost=${INFRACOST:-infracost}
command -v "$infracost" >/dev/null || {
  echo "infracost is not installed: https://www.infracost.io/docs/#quick-start" >&2
  exit 1
}
version=$(INFRACOST_SKIP_UPDATE_CHECK=true "$infracost" --version 2>/dev/null || true)
[[ $version == *v0.10.* ]] || {
  echo "Needs Infracost v0.10.x, found: ${version:-unknown} ($(command -v "$infracost"))." >&2
  echo "Run with a v0.10 binary, e.g. INFRACOST=/usr/local/bin/infracost make cost-estimate" >&2
  exit 1
}

# The plan JSON holds resource values: it stays in the git-ignored work dir
terraform -chdir="$dir" show -json "$plan" > "$work/plan.json"

usage_args=()
[[ -f "$usage" ]] && usage_args=(--usage-file "$usage")

# Plan JSON: the diff is between the prior state and the planned state.
# Results stay here: nothing is uploaded to the Infracost Cloud dashboard.
INFRACOST_ENABLE_CLOUD=false INFRACOST_API_KEY=$key "$infracost" diff --path "$work/plan.json" "${usage_args[@]}" \
  --format json --out-file "$work/infracost.json" >&2
diff_text=$("$infracost" output --path "$work/infracost.json" --format diff --no-color)

read -r past total change currency < <(jq -r '
  [(.pastTotalMonthlyCost // "0"), (.totalMonthlyCost // "0"),
   (.diffTotalMonthlyCost // "0"), (.currency // "USD")] | @tsv' "$work/infracost.json")

money() { printf '%.2f' "$1"; }
sign=+
[[ $change == -* ]] && sign=

cat <<MD
### Cost estimate: \`$stack\`

| Monthly cost before | After this plan | Difference |
|---|---|---|
| $(money "$past") $currency | $(money "$total") $currency | **$sign$(money "$change") $currency** |

Infracost list prices for the plan's region. Usage-based costs (storage,
requests) use the assumptions in \`$usage\`$( [[ -f "$usage" ]] || echo " (missing: shown as \$0)" ).
Resources outside Terraform (build hosts, data transfer to devices) are not
included: see the \`cost-impact\` skill.

<details><summary>Infracost diff</summary>

\`\`\`
$diff_text
\`\`\`

</details>

Commit \`${GITHUB_SHA:-local}\`.
MD
