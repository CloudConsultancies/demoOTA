---
name: cost-impact
description: Write the "Cost impact" section for an issue or PR in this repo that adds, changes or removes cloud resources (AWS - EC2, S3, IoT Core, KMS, NAT, CloudWatch - Terraform, hawkBit host). Lists each resource with its pricing model, cost per demo run and per month if left running, what stays on permanently, and checks a make teardown target removes it. Use when a change "adds an S3 bucket", "starts an EC2 instance", touches infra/ or Terraform, or the user asks "what does this cost".
---

# Cost impact

The project rule: cloud resources exist only for a demo and are destroyed
afterwards; nothing always-on and paid unless the user agreed. Every issue or PR
that adds or changes cloud resources states its cost impact. This skill writes
that section.

## 1. List the resources

From the issue's acceptance criteria, or for a PR from the diff
(`git diff origin/main...HEAD -- infra/ Makefile .github/workflows/`), list every
cloud resource that is created, changed or removed. Include the hidden ones that
cost money by existing:

- NAT gateways, public IPv4 addresses, load balancers (per hour)
- KMS customer-managed keys, Secrets Manager secrets (per month)
- EBS volumes and snapshots left after an instance is gone
- CloudWatch log groups without retention, S3 buckets without lifecycle rules
- data transfer out to the internet (devices downloading bundles)

Resources with no charge of their own (IAM roles, OIDC provider, security
groups) are listed once as "no charge".

## 2. Price each resource

**Terraform resources: Infracost first.** If the change touches a stack
under `infra/` (not the bootstrap, which CI does not plan), use the
Infracost estimate when it exists:

- On a PR: the comment that starts with `<!-- infracost:<stack> -->`
  (`gh api repos/{owner}/{repo}/issues/<PR>/comments --jq '.[] | select(.body | startswith("<!-- infracost:")) | .body'`).
- Locally, if the user ran it: `infra/<stack>/cost-summary.md` from
  `make infra-plan` + `make cost-estimate`.

Take the monthly cost before, after and the difference from it, and the
per-resource lines from its collapsed diff. Its usage-based numbers come
from `infra/<stack>/infracost-usage.yml`: quote those as the assumptions,
and if the change adds usage-based resources (S3, data transfer), check that
the usage file covers them; add the missing entries to the change, otherwise
they show as $0. Infracost gives the cost per month; work out the per-demo-run
cost from the assumptions.

**Everything else, or no estimate: prices.md.** Use [prices.md](prices.md)
when the estimate is missing or says "Skipped", for resources outside
Terraform (build hosts started by CI, data transfer to devices) and for
issues, which have no plan yet. Say in the section which source each number
comes from.

Each price in `prices.md` has a source and the date it was checked. If you have
web access, check the AWS pricing page for the resources involved and update `prices.md` (price, *Checked* date). If
not, use the table as it is and say the prices are unverified.

State the region assumed (the Terraform provider region if it exists; otherwise
say "us-east-1 list prices, region not decided yet").

Estimate with the demo's real usage, stated as assumptions: build hours per
run, GB stored, number of devices, requests. Round up; this is an estimate, not
a quote.

## 3. Check teardown

- For each resource, find what removes it: a `make` target (for example
  `make infra-destroy`, `make build-host-down`), an instance that terminates
  itself, a lifecycle rule. CI must call the same `make` target.
- If there is no teardown path, say so and add it as an acceptance criterion
  ("`make <x>-destroy` removes ...").
- Anything that stays on permanently and costs money (storage kept between
  demos, a KMS key, a running host) is flagged **needs the user's agreement**,
  with the monthly cost. Storage that is meant to persist (artifacts, audit
  records) is fine once agreed, but say so explicitly.

## 4. Write the section

```markdown
### Cost impact

Region: <region>. Prices: Infracost estimate on this PR (commit <sha>) and/or <prices.md source>, checked <date> (or "unverified").

| Resource | Pricing model | Per demo run | Per month if left running | Always on? | Removed by |
|---|---|---|---|---|---|
| EC2 build host (c6i.4xlarge spot) | spot, per second | ~$0.45 (1.5 h at ~$0.30/h) | ~$220 | no, terminated after build | `make build-host-down`, instance self-terminates |
| S3 cache bucket (~20 GB) | storage + requests | < $0.01 | ~$0.50 | yes, by design (agreed in #N) | lifecycle rule; `make infra-destroy` |

**Total:** ~$X per demo run, ~$Y per month for what stays between demos.

**Assumptions:** <usage numbers used above>.

**Needs agreement:** <always-on items and their monthly cost, or "nothing">.
```

- "Per month if left running" means the resource forgotten and running all
  month: the worst case the teardown protects against.
- If the change adds no cloud resources, the section is one line:
  `**Cost impact:** none. The change adds no cloud resources.`

## 5. Place it

- Issue: under *Notes*, or as a comment on an existing issue
  (`gh issue comment N --body-file ...`, after the user approves the text).
- PR: a *Cost impact* section in the PR body.
- If an item needs the user's agreement, ask in the chat and record the answer
  in an issue comment.
