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

## Workflows (project skills)

The repeated workflows are project skills in `.claude/skills/`. Each skill
holds the full procedure; follow it instead of improvising the steps.

| When | Skill |
|---|---|
| a task, bug or demo scenario comes up; "draft an issue" | `issue-draft`: draft in the chat, labels, create only after approval |
| "work on #N"; pushing or opening the PR for an issue | `work-on-issue`: branch naming, `Refs #N`, ask before pushing, PR with `Closes #N`, never merge |
| adding or changing a diagram | `drawio-diagram`: `docs/<name>.drawio.svg`, white background, text description, checker |
| an issue or PR adds or changes cloud resources | `cost-impact`: "Cost impact" section, teardown check, always-on needs agreement |

Repo facts the skills rely on:

- Work is tracked as GitHub issues (`gh` is installed and authenticated).
  Questions and decisions about an issue go into an issue comment as well
  as the chat.
- `main` accepts changes only through PRs (ruleset "Protect main": no
  direct push, no force push, no deletion, review threads resolved). The
  `Branch name` workflow is a required check. Merged branches are deleted
  automatically.

## Environment

- Dev machine: ~8 GB RAM; docker and terraform are installed. Check
  before assuming other tools.

## Gotchas

- `gh issue view N --comments` can fail with a "Projects (classic) is being
  deprecated" GraphQL error. Use `gh issue view N --json
  number,title,state,labels,body,comments` instead.
