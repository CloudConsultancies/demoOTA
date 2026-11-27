#!/usr/bin/env bash
# Prints the Infracost API key to stdout, or nothing if there is none:
# INFRACOST_API_KEY if set (CI: the secret), else the key that
# `infracost auth login` saved. `infracost configure get api_key` cannot
# be used: Infracost v2 removed `infracost configure`.
#
#   scripts/infracost-key.sh
set -euo pipefail

if [[ -n "${INFRACOST_API_KEY:-}" ]]; then
  printf '%s' "$INFRACOST_API_KEY"
  exit 0
fi

credentials=${XDG_CONFIG_HOME:-$HOME/.config}/infracost/credentials.yml
[[ -f "$credentials" ]] || exit 0

# A line like `api_key: ico-...`, possibly quoted
key=$(sed -n 's/^api_key:[[:space:]]*//p' "$credentials" | head -n 1)
key=${key//\"/}
key=${key//\'/}
key=${key%%[[:space:]]*}
printf '%s' "$key"
