# Signing RAUC bundles

A device installs an update bundle only if its signature chains to the
**keyring** built into the image. This page covers the keys behind that
signature, how CI signs, how to rotate the signing certificate, and what to
do if a key leaks.

## Key hierarchy

Two levels, both EC P-256:

1. **Root CA** (`demoOTA RAUC root CA`, valid 20 years). Its certificate is
   the RAUC keyring in the image, committed at
   [`yocto/meta-demo-ota/recipes-core/rauc/files/ca.cert.pem`](../yocto/meta-demo-ota/recipes-core/rauc/files/ca.cert.pem).
   Its private key signs only signing certificates (and revocation lists). It
   is encrypted with a passphrase and kept **offline**.
2. **Signing certificate** (`demoOTA RAUC signing <date>`, valid 2 years,
   issued by the CA, key usage `digitalSignature`, extended key usage
   `codeSigning`, not a CA). CI signs bundles with its key. Because the
   devices trust the CA and not this certificate, it can be replaced without
   reflashing anything.

Nothing in the image is device-specific: every device carries the same CA
certificate. Device identity certificates for the fleet backend are a
separate PKI (Phase 3, provisioning).

## Where the keys are

| Item | Where | Who can use it |
|---|---|---|
| CA private key `ca.key.pem` | encrypted, on offline storage (a USB stick kept in a drawer, or an attachment in your password manager), passphrase in your password manager | you, only for `make pki-init` and `make pki-rotate` |
| CA certificate `ca.cert.pem` | committed in the repo (public) | everyone; built into the image |
| Signing key and certificate | secrets `RAUC_SIGNING_KEY`, `RAUC_SIGNING_CERT` of the GitHub environment `release`; working copy in `~/.demo-ota-pki/` | jobs in the `release` environment, which only `main` may use |
| Serial counter, old signing certificates | `~/.demo-ota-pki/ca.srl`, `~/.demo-ota-pki/archive/` | you |

## Set up (once)

1. `make pki-init`. It creates the PKI in `~/.demo-ota-pki/` (change it with
   `PKI_DIR=`) and asks twice for the CA key passphrase. It refuses to run if a
   PKI already exists. It copies the CA certificate into the repo.
2. Move `~/.demo-ota-pki/ca.key.pem` to offline storage and delete the local
   copy. Store the passphrase in your password manager. Keep a second offline
   copy: if the CA key is lost, the next signing certificate needs a new CA,
   and with it a new image on every device.
3. `make pki-github-secrets` creates the `release` environment and allows
   deployments from `main` only. It then stores the signing key and
   certificate as environment secrets. It checks first that the signing
   certificate chains to the CA certificate in the repo. Do this **before**
   the signing workflow runs for the first time: GitHub creates a missing
   environment by itself, without the branch rule.
4. Commit the CA certificate.

## How CI signs

The *Signing* workflow (`.github/workflows/signing.yml`) runs on `main` when
the CA certificate or the bundle script changes. You can also start it by
hand.

1. The `sign` job declares `environment: release`. GitHub releases the
   environment's secrets only to jobs started from `main`. A job started from
   any other branch is refused before its first step.
2. `make bundle-dummy` writes the key from `RAUC_SIGNING_KEY` into a
   temporary directory (mode 600) and runs `rauc bundle`. The directory is
   removed when the step ends. The key is never written into the workspace or
   the build output.
3. `make bundle-verify` runs `rauc info` with the committed CA certificate as
   the keyring, the same check a device makes. It also checks that a foreign
   CA does not accept the bundle. Both steps use a minimal RAUC config with
   `check-purpose=codesign` (see Notes).
4. The `no-key` job runs without the environment and checks with
   `make signing-key-absent` that the secret is empty there.

The image build (Phase 1) will sign the real bundles the same way, in a job
in the `release` environment.

To see that a branch cannot sign, start the workflow by hand from a feature
branch. `no-key` passes, and `sign` fails with "Branch … is not allowed to
deploy to release due to environment protection rules".

## Rotate the signing certificate

Rotate before it expires (2 years; `openssl x509 -in
~/.demo-ota-pki/signing.cert.pem -noout -enddate`), or at any time:

1. Get the CA key from offline storage.
2. `make pki-rotate CA_KEY=/path/to/ca.key.pem`. The old signing key and
   certificate move to `~/.demo-ota-pki/archive/<date>-<serial>/`, and a new
   pair is issued by the same CA.
3. `make pki-github-secrets` replaces the secrets.
4. Put the CA key back offline.
5. Start the *Signing* workflow on `main` to check the new pair.

Devices need nothing: the new certificate chains to the same CA. Bundles
signed with the old certificate stay installable until it expires, or until
it is revoked (below).

## If a key leaks

**Signing key leaked** (for example a compromised CI run or an exposed
secret). The attacker can sign bundles that every device accepts.

1. Rotate at once (above), so CI signs only with the new key.
2. Revoke the leaked certificate. Use the CA to issue a revocation list (CRL)
   that lists its serial, for example with `openssl ca -revoke` and
   `openssl ca -gencrl`. These need an `openssl ca` database, which
   `make pki-init` does not create; there is no make target for this yet.
3. Build an image whose keyring contains the CA certificate *and* the CRL,
   with `check-crl=true` in the `[keyring]` section of RAUC's `system.conf`.
   Sign it with the new key and roll it out to the whole fleet. Devices
   accept it because the new certificate chains to the same CA. After the
   update they refuse anything signed with the leaked key.
4. Until a device has that update, it still accepts the leaked key, so roll
   out quickly. Record the incident (see README, "Compliance and
   traceability").

**CA key leaked** (with its passphrase). The attacker can issue their own
signing certificates, so revocation lists do not help. Create a new PKI
(`make pki-init` with a new `PKI_DIR`) and roll out an image whose keyring
holds only the new CA, signed with the *current* signing key while it is still
trusted. A device the attacker updated first cannot be recovered over the
air. Reflash it.

**CA key lost** (not leaked). Existing bundles and devices keep working, but
no new signing certificate can be issued. Before the current one expires,
roll out an image whose keyring holds a new CA, as for a leak.

## Notes

- **Certificate purpose.** By default RAUC checks certificates for the
  S/MIME signing purpose, which rejects a certificate made for code signing
  only ("unsuitable certificate purpose"). The device's `system.conf` (Phase 2)
  must therefore set `check-purpose=codesign` in the `[keyring]` section, as
  the CI check does.
- **No hardware clock on the Pi.** After a boot without network time, the
  clock can be wrong (for example the last saved time, or 1970), and RAUC
  then rejects a valid certificate as "not yet valid" or "expired". The device
  setup (Phase 2) should set `use-bundle-signing-time=true` in the `[keyring]`
  section of `system.conf`, so certificates are checked against the time the
  bundle was signed.
- **Development keys.** Local builds will use a separate self-signed
  development CA, which production images never trust. Which keyring goes
  into which image is decided with the first Yocto build.
- **Hardening later.** The signing key could live in AWS KMS and never leave
  the HSM. RAUC would then sign through PKCS#11, which adds complexity, so
  this is left for later.
