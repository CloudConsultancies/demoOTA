#!/usr/bin/env bash
# Dummy RAUC bundle to prove the signing chain (see docs/signing.md).
#
#   bundle-dummy.sh sign <out-dir>     sign a dummy bundle
#   bundle-dummy.sh verify <out-dir>   verify it with the committed CA certificate,
#                                      and check a foreign CA is refused
#
# Signing key and certificate, in this order:
#   RAUC_SIGNING_KEY / RAUC_SIGNING_CERT   PEM contents (CI: secrets of the
#                                          "release" environment)
#   $PKI_DIR/signing.{key,cert}.pem        local PKI (default ~/.demo-ota-pki)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYRING="$REPO_ROOT/yocto/meta-demo-ota/recipes-core/rauc/files/ca.cert.pem"
PKI_DIR="${PKI_DIR:-$HOME/.demo-ota-pki}"

die() { echo "error: $*" >&2; exit 1; }

cmd="${1:-}"; out="${2:-}"
[[ -n "$out" ]] || die "usage: $0 sign|verify <out-dir>"
bundle="$out/dummy.raucb"
command -v rauc >/dev/null || die "rauc not found (Ubuntu: apt-get install rauc squashfs-tools)"
[[ -f "$KEYRING" ]] || die "no CA certificate at $KEYRING: run make pki-init"

# Temporary files, removed on exit. In CI the signing key exists only here.
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# Minimal RAUC config with the given keyring. RAUC checks the certificate
# purpose; its default (smimesign) rejects a certificate made for code
# signing only, so this uses the setting the devices' system.conf needs
# as well: check-purpose=codesign.
rauc_conf() {
  local conf="$TMP/system-$RANDOM.conf"
  cat > "$conf" <<EOF
[system]
compatible=demo-ota-dummy
bootloader=noop
data-directory=$TMP/data

[keyring]
path=$1
check-purpose=codesign
EOF
  echo "$conf"
}

sign() {
  local key="$TMP/signing.key.pem" cert="$TMP/signing.cert.pem"
  if [[ -n "${RAUC_SIGNING_KEY:-}" ]]; then
    [[ -n "${RAUC_SIGNING_CERT:-}" ]] || die "RAUC_SIGNING_CERT is empty"
    (umask 077; printf '%s\n' "$RAUC_SIGNING_KEY" > "$key")
    printf '%s\n' "$RAUC_SIGNING_CERT" > "$cert"
  elif [[ -f "$PKI_DIR/signing.key.pem" ]]; then
    (umask 077; cp "$PKI_DIR/signing.key.pem" "$key")
    cp "$PKI_DIR/signing.cert.pem" "$cert"
  else
    die "no signing key: RAUC_SIGNING_KEY is empty (CI outside the release environment?) and $PKI_DIR has none"
  fi

  mkdir -p "$TMP/content" "$out"
  # A verity bundle needs a squashfs larger than 4 KiB: random data does not compress
  { echo "demoOTA dummy payload $(date -u +%FT%TZ) ${GITHUB_SHA:-local}"
    head -c 65536 /dev/urandom; } > "$TMP/content/rootfs.img"
  cat > "$TMP/content/manifest.raucm" <<EOF
[update]
compatible=demo-ota-dummy
version=0.0.0+${GITHUB_SHA:-local}

[bundle]
format=verity

[image.rootfs]
filename=rootfs.img
EOF
  rm -f -- "$bundle"
  # With --keyring, rauc checks the new signature against the CA before writing
  rauc --conf="$(rauc_conf "$KEYRING")" bundle \
    --cert="$cert" --key="$key" --keyring="$KEYRING" "$TMP/content" "$bundle"
  openssl x509 -in "$cert" -noout -subject -issuer -serial -enddate
}

verify() {
  [[ -f "$bundle" ]] || die "no bundle at $bundle: run sign first"
  echo "Verify with the committed CA certificate"
  rauc --conf="$(rauc_conf "$KEYRING")" info "$bundle"

  echo "A foreign CA must be refused"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$TMP/foreign.key.pem" -out "$TMP/foreign.pem" -days 1 \
    -subj "/CN=foreign CA" 2>/dev/null
  if rauc --conf="$(rauc_conf "$TMP/foreign.pem")" info "$bundle" >/dev/null 2>&1; then
    die "the bundle verified against a foreign CA"
  fi
  echo "refused, as expected"
}

case "$cmd" in
  sign) sign ;;
  verify) verify ;;
  *) die "usage: $0 sign|verify <out-dir>" ;;
esac
