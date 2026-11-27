#!/usr/bin/env bash
# Validate the IAM policies of a saved Terraform plan with IAM Access
# Analyzer (aws accessanalyzer validate-policy). Read-only: nothing in the
# account changes. Catches what terraform validate cannot, such as
# MalformedPolicyDocument errors that IAM raises only on create.
#
# Usage: validate-iam-policies.sh <terraform dir> <plan file>
# Needs: terraform, jq, the AWS CLI with credentials (AWS_PROFILE).
# Exit 1 if any policy has an ERROR or SECURITY_WARNING finding.
set -euo pipefail

dir=${1:?terraform directory}
plan=${2:?plan file}
region=${AWS_REGION:-eu-north-1}

[[ -f "$dir/$plan" ]] || { echo "No saved plan $dir/$plan: run make bootstrap-plan first." >&2; exit 1; }

plan_json=$(terraform -chdir="$dir" show -json "$plan")

# address|attribute|policy type|resource type (for resource policies)
checks=(
  "aws_iam_role_policy.plan|policy|IDENTITY_POLICY|"
  "aws_iam_role_policy.apply|policy|IDENTITY_POLICY|"
  "aws_iam_policy.boundary|policy|IDENTITY_POLICY|"
  "aws_iam_role.plan|assume_role_policy|RESOURCE_POLICY|AWS::IAM::AssumeRolePolicyDocument"
  "aws_iam_role.apply|assume_role_policy|RESOURCE_POLICY|AWS::IAM::AssumeRolePolicyDocument"
)

failed=0
for check in "${checks[@]}"; do
  IFS='|' read -r address attr type resource_type <<<"$check"

  policy=$(jq -r --arg a "$address" --arg k "$attr" \
    '.resource_changes[] | select(.address == $a) | .change.after[$k] // empty' <<<"$plan_json")
  if [[ -z "$policy" ]]; then
    echo "!! $address: $attr not known in the plan, cannot validate" >&2
    failed=1
    continue
  fi

  args=(--region "$region" --policy-type "$type" --policy-document "$policy" --output json)
  [[ -n "$resource_type" ]] && args+=(--validate-policy-resource-type "$resource_type")

  findings=$(aws accessanalyzer validate-policy "${args[@]}")
  count=$(jq '.findings | length' <<<"$findings")
  blocking=$(jq '[.findings[] | select(.findingType == "ERROR" or .findingType == "SECURITY_WARNING")] | length' <<<"$findings")

  if [[ "$count" -eq 0 ]]; then
    echo "ok $address ($attr)"
  else
    echo "-- $address ($attr): $count finding(s)"
    jq -r '.findings[] | "   \(.findingType) \(.issueCode): \(.findingDetails)"' <<<"$findings"
    [[ "$blocking" -gt 0 ]] && failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "Policy validation failed: fix the ERROR / SECURITY_WARNING findings above." >&2
  exit 1
fi
echo "All policies valid (warnings and suggestions, if any, are listed above)."
