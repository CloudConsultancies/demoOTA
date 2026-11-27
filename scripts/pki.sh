#!/usr/bin/env bash
# Signing PKI for RAUC bundles (see docs/signing.md). Run by a human,
# locally; never from CI.
#
#   pki.sh init            root CA + first signing key and certificate
#   pki.sh rotate          new signing key and certificate from the CA
#   pki.sh github-secrets  environment "release" (main only) + its secrets
#
# Environment:
#   PKI_DIR            where the PKI lives (default ~/.demo-ota-pki), outside the repo
#   CA_KEY             CA private key (default $PKI_DIR/ca.key.pem); point it at
#                      the offline copy for rotate
#   PKI_CA_PASSPHRASE  CA key passphrase; openssl prompts when unset
set -euo pipefail

PKI_DIR="${PKI_DIR:-$HOME/.demo-ota-pki}"
CA_KEY="${CA_KEY:-$PKI_DIR/ca.key.pem}"
CA_CERT="$PKI_DIR/ca.cert.pem"
SIGNING_KEY="$PKI_DIR/signing.key.pem"
SIGNING_CERT="$PKI_DIR/signing.cert.pem"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The CA certificate in the repo becomes the RAUC keyring of the image
KEYRING="$REPO_ROOT/yocto/meta-demo-ota/recipes-core/rauc/files/ca.cert.pem"

CA_DAYS=7305      # 20 years: the keyring is in the image, changing it means an update
SIGNING_DAYS=731  # 2 years: rotated without reflashing devices
ENVIRONMENT=release

umask 077

die() { echo "error: $*" >&2; exit 1; }

# Temporary files (extension config, CSR), removed on exit
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

pass_args() {
  if [[ -n "${PKI_CA_PASSPHRASE:-}" ]]; then printf '%s\n' "$1" env:PKI_CA_PASSPHRASE; fi
}

new_ec_key() { openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 "$@"; }

# Signing key and certificate issued by the CA: code signing only
issue_signing_cert() {
  local subject
  subject="/O=demoOTA/CN=demoOTA RAUC signing $(date -u +%Y-%m-%d)"
  local ext="$WORK/signing.ext" csr="$WORK/signing.csr.pem"
  cat > "$ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF
  new_ec_key -out "$SIGNING_KEY"
  openssl req -new -key "$SIGNING_KEY" -subj "$subject" -out "$csr"
  # shellcheck disable=SC2046
  openssl x509 -req -in "$csr" -days "$SIGNING_DAYS" \
    -CA "$CA_CERT" -CAkey "$CA_KEY" $(pass_args -passin) \
    -CAserial "$PKI_DIR/ca.srl" -CAcreateserial \
    -extfile "$ext" -out "$SIGNING_CERT"
  openssl verify -CAfile "$CA_CERT" -purpose any "$SIGNING_CERT"
}

cmd_init() {
  command -v openssl >/dev/null || die "openssl not found"
  [[ -e "$CA_KEY" || -e "$CA_CERT" ]] && die "a PKI already exists in $PKI_DIR; nothing changed"
  mkdir -p "$PKI_DIR"

  echo "Root CA (the key is encrypted: choose a passphrase and keep it safe)"
  # shellcheck disable=SC2046
  new_ec_key -aes-256-cbc $(pass_args -pass) -out "$CA_KEY"
  # shellcheck disable=SC2046
  openssl req -x509 -new -key "$CA_KEY" $(pass_args -passin) -days "$CA_DAYS" \
    -subj "/O=demoOTA/CN=demoOTA RAUC root CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash" \
    -out "$CA_CERT"

  echo "Signing key and certificate"
  issue_signing_cert

  mkdir -p "$(dirname "$KEYRING")"
  cp "$CA_CERT" "$KEYRING"
  chmod 644 "$KEYRING"

  cat <<EOF

PKI created in $PKI_DIR:
  ca.key.pem        CA private key (encrypted). Copy it to two USB sticks,
                    store the passphrase apart, then delete it here
                    (docs/signing.md, "Managing the CA key").
  ca.cert.pem       CA certificate, copied to ${KEYRING#"$REPO_ROOT"/} (commit it)
  signing.*.pem     signing key and certificate: store them with
                    make pki-github-secrets
EOF
}

cmd_rotate() {
  [[ -f "$CA_KEY" ]] || die "CA key not found at $CA_KEY: set CA_KEY to the offline copy"
  [[ -f "$CA_CERT" ]] || die "CA certificate not found at $CA_CERT"
  if [[ -f "$SIGNING_CERT" ]]; then
    local serial old
    serial="$(openssl x509 -in "$SIGNING_CERT" -noout -serial | cut -d= -f2)"
    old="$PKI_DIR/archive/$(date -u +%Y%m%d)-$serial"
    mkdir -p "$old"
    mv "$SIGNING_KEY" "$SIGNING_CERT" "$old/"
    echo "Previous signing key and certificate moved to $old"
  fi
  issue_signing_cert
  echo "New signing certificate issued. Store it with make pki-github-secrets."
}

cmd_github_secrets() {
  command -v gh >/dev/null || die "gh not found"
  [[ -f "$SIGNING_KEY" && -f "$SIGNING_CERT" ]] || die "no signing key in $PKI_DIR: run make pki-init"
  [[ -f "$KEYRING" ]] || die "no CA certificate at $KEYRING"
  # The signing certificate must chain to the CA committed in the repo
  openssl verify -CAfile "$KEYRING" -purpose any "$SIGNING_CERT" >/dev/null \
    || die "the signing certificate does not chain to ${KEYRING#"$REPO_ROOT"/}"

  local repo; repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  echo "Environment $ENVIRONMENT in $repo, deployments from main only"
  gh api -X PUT "repos/$repo/environments/$ENVIRONMENT" --input - >/dev/null <<'EOF'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF
  local policies
  policies="$(gh api "repos/$repo/environments/$ENVIRONMENT/deployment-branch-policies" \
    --jq '[.branch_policies[] | "\(.type):\(.name)"] | join(" ")')"
  if [[ " $policies " != *" branch:main "* ]]; then
    gh api -X POST "repos/$repo/environments/$ENVIRONMENT/deployment-branch-policies" \
      -f name=main -f type=branch >/dev/null
  fi
  gh api "repos/$repo/environments/$ENVIRONMENT/deployment-branch-policies" \
    --jq '.branch_policies[] | "  allowed: \(.type) \(.name)"'

  gh secret set RAUC_SIGNING_KEY --env "$ENVIRONMENT" --repo "$repo" < "$SIGNING_KEY"
  gh secret set RAUC_SIGNING_CERT --env "$ENVIRONMENT" --repo "$repo" < "$SIGNING_CERT"
  gh secret list --env "$ENVIRONMENT" --repo "$repo"
}

case "${1:-}" in
  init) cmd_init ;;
  rotate) cmd_rotate ;;
  github-secrets) cmd_github_secrets ;;
  *) die "usage: $0 init|rotate|github-secrets" ;;
esac
