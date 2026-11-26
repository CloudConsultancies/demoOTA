# CLAUDE.md

Demo of Over-The-Air (OTA) updates: a Raspberry Pi 4 (extendable to a
small fleet) running a Yocto + RAUC image built in AWS, with updates,
manual and automatic rollbacks (green / blue / red images) and staged
fleet rollouts driven from GitHub Actions. See README.md for the goal,
architecture, scenarios and roadmap.

## Principles

- **Cheap and ephemeral.** Cloud resources exist only for a demo and are
  destroyed afterwards. No always-on paid resources unless agreed. State a
  cost impact in any issue or PR that adds cloud resources.
- **Makefile is the single entry point.** CI calls `make` targets and does
  not duplicate logic in workflow YAML.
- **Traceable.** Every release and rollout leaves evidence (SBOM, signed
  bundle, audit log, per-device result); see README "Compliance and
  traceability".
- **No secrets in the repo.** CI reaches cloud providers through OIDC (no
  long-lived keys); signing keys and tokens are GitHub secrets.

## Architecture constraints

- Image: Yocto (`meta-raspberrypi`) for the Raspberry Pi 4 (arm64), A/B
  updates with RAUC (`meta-rauc-community`). Bundles are signed in CI.
- Partitions: boot, rootfs A, rootfs B (read-only), data (persistent).
- Automatic rollback is on the device: boot counting + hardware watchdog;
  a slot is marked good only after the health check passes.
- One image for the whole fleet: nothing device-specific in the image;
  device identity (ID, X.509 certificate) is provisioned into the data
  partition separately.
- Yocto builds run on an ephemeral EC2 (spot) instance; downloads and
  sstate caches live in S3.
- Fleet backend: not decided yet (AWS IoT Core Jobs recommended, Eclipse
  hawkBit the alternative). Do not build on either before the decision.

## Issue workflow

Work is tracked as GitHub issues (`gh` is installed and authenticated).

- **Capturing:** when a task comes up in discussion, draft the issue in
  the chat first (title, labels, body with *Context*, *Acceptance
  criteria*, *Notes*; scenarios use the scenario template). Create it with
  `gh issue create` only after the user approves the draft.
- **Labels:** `enhancement`, `bug`, `documentation`, `scenario`, `ci`,
  `security`, `cost`, `tech-debt`. Add area labels once the architecture
  is decided.
- **"Work on #N":** read it with `gh issue view N --comments`; branch
  `issue/N-short-name` from the latest `origin/main`; commit messages
  reference `Refs #N`.
- **Ask before pushing:** when the work is committed locally, stop and ask
  the user; they may review the branch locally first.
- **After approval:** push the branch and open the PR with `gh pr create`
  (body ends with `Closes #N`). Report the CI result of the branch
  (`gh run list --branch <branch>`). Never merge; the user merges.
- Questions or decisions about an issue go into an issue comment as well
  as the chat, so the history stays with the issue.

## Environment

- Dev machine: ~8 GB RAM; docker and terraform are installed. Check
  before assuming other tools.

## Gotchas

(Fill in as we learn.)
