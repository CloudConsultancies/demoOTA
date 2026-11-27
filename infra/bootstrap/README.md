# AWS bootstrap (one-time, applied by hand)

Creates what every later demoOTA stack and workflow needs before it can
run: a place for Terraform state, roles that GitHub Actions can assume
without keys, and a cost guard. You apply it once from your machine. CI
never runs it.

demoOTA shares its AWS account with demoKubernetesCluster (region
`eu-north-1`, CLI profile `demo-k8s`). Naming (`demo-ota-*`), the tag
`Project=demoOTA` and roles that trust only this repository keep the two
projects apart.

## What it creates

| Resource | Purpose |
|---|---|
| S3 bucket `demo-ota-tfstate-<account ID>` | Terraform state of this stack (`bootstrap/`) and of later demoOTA stacks. Versioned (old versions expire after 90 days), SSE-S3 encrypted, public access blocked, ACLs off, TLS only. Locking with S3 lock files (`use_lockfile`), no DynamoDB table. `prevent_destroy`. |
| IAM role `demo-ota-plan` | Any branch, pull request or environment of **this repository**. AWS `ReadOnlyAccess`, minus data in other projects: object reads outside `demo-ota-*` buckets, parameters, secrets, log events and DynamoDB items are denied. Its only write is the state lock file (`*.tflock`). |
| IAM role `demo-ota-apply` | **`main` of this repository only.** `ReadOnlyAccess` (with the same data denies), plus write access to demoOTA resources only (see [Apply role scope](#apply-role-scope)). |
| IAM policy `demo-ota-boundary` | Permissions boundary that every role created by demoOTA stacks must carry. Such a role never gets more than the apply role. |
| AWS Budget `demo-ota-monthly` | $10/month (`budget_limit_usd`) on costs tagged `Project=demoOTA`. Emails at 50 %, 80 % and 100 % of the **forecast**. |
| GitHub OIDC provider | Shared with demoKubernetesCluster: created here or referenced, see below. |

Every resource carries `Project=demoOTA` (plus `ManagedBy`, `Stack`)
through the provider's `default_tags`.

### Role trust

This repository uses GitHub's **immutable OIDC subjects**, so the `sub`
claim contains the numeric owner and repository IDs:

```
repo:CloudConsultancies@255329107/demoOTA@1472192666:ref:refs/heads/main
```

You can check it with
`gh api repos/CloudConsultancies/demoOTA/actions/oidc/customization/sub`.

- `demo-ota-plan` accepts `repo:CloudConsultancies@255329107/demoOTA@1472192666:*`.
- `demo-ota-apply` accepts exactly `...:ref:refs/heads/main`. A job that
  uses a GitHub environment gets an `...:environment:<name>` subject and
  is refused as well.

A repository recreated under the same name gets a new ID and is
refused. If the immutable-subject setting is turned off, both roles
fail closed. The IDs are variables (`github_owner_id`,
`github_repository_id`).

### Apply role scope

`demo-ota-apply` (and, through the boundary, every role a demoOTA stack
creates) may:

- do anything on resources whose **name starts with `demo-ota-`**: S3
  buckets, and ARNs of the form `...:<acct>:demo-ota-*`, `.../demo-ota-*`
  or `...:demo-ota-*` (IAM roles, log groups, topics, ...);
- do anything on resources **tagged `Project=demoOTA`** (EC2 instances,
  KMS keys, and other resources that have IDs, not names);
- **create** resources only with the tag `Project=demoOTA` in the request.

It may not:

- change the bootstrap itself: the two roles, the boundary policy, the
  budget, the OIDC provider, the state bucket's settings, or the
  `bootstrap/` state (which it cannot read either);
- create a role without the `demo-ota-boundary` boundary, or remove the
  boundary from a role;
- create IAM users, access keys, login profiles or other long-lived
  credentials;
- tag a resource of another project into demoOTA (resources that already
  carry a `Project` tag, other projects' named resources, and existing EC2
  resources);
- act in any region other than `eu-north-1` (global services such as IAM,
  STS and Budgets excepted).

Later stacks need more than this in some places, for example running an
EC2 instance from a public AMI in the default VPC. They add that here,
in the bootstrap, so the scope stays reviewable in one place.

Known gap: an **untagged** resource of another project in a service that
has no names in its ARNs and is not covered by the tag denies (for
example a KMS key without a `Project` tag) could be tagged into demoOTA.
demoKubernetesCluster tags its resources with `Project`, which closes
that gap for it.

### Shared GitHub OIDC provider

An AWS account holds only **one** IAM OIDC provider for
`token.actions.githubusercontent.com`. demoOTA and demoKubernetesCluster
both need it, so exactly one bootstrap owns it:

- `create_github_oidc_provider = true` (default): this stack creates it
  and owns it.
- `create_github_oidc_provider = false`: another stack owns it, and this
  stack references it with a data source.

**Owner: demoOTA** (this stack). The account had no GitHub OIDC provider
when checked on 2026-11-27. demoKubernetesCluster's bootstrap
(CloudConsultancies/demoKubernetesCluster#2) references it with a data
source and must not create it. demoOTA's bootstrap has to be applied
first.

Rules for both projects:

- Only the owner's bootstrap creates or deletes the provider. The other
  project only references it.
- When the provider is created here, it has `prevent_destroy`. Destroying
  the owner's bootstrap needs a deliberate handover first: the other
  project imports the provider (`terraform import`) and becomes its owner.
- Each project's roles trust only their own repository, so sharing the
  provider grants no cross-project access.

Find out whether it exists already:

```sh
AWS_PROFILE=demo-k8s aws iam list-open-id-connect-providers
```

## Apply

Prerequisites: Terraform >= 1.10, the AWS CLI with the `demo-k8s`
profile, `gh` logged in, and `jq`.

### First apply: local state, then migrate into the bucket

The state bucket does not exist before the first apply, so that apply
uses local state (`backend_override.tf` replaces the S3 backend). The
state then moves into the bucket.

```sh
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars   # git-ignored
# set budget_email (create_github_oidc_provider stays true: demoOTA owns it)
cd ../..

make bootstrap-local     # writes infra/bootstrap/backend_override.tf
make bootstrap-init
make bootstrap-plan
make bootstrap-apply

make bootstrap-migrate   # removes the override; answer "yes" to copy the state
make bootstrap-plan      # expect: No changes
rm infra/bootstrap/terraform.tfstate infra/bootstrap/terraform.tfstate.backup
```

The state is now at `s3://demo-ota-tfstate-<account ID>/bootstrap/terraform.tfstate`.

### Later changes

In any checkout: `make bootstrap-init` (once per checkout), then
`make bootstrap-plan` and `make bootstrap-apply`.

The Makefile sets `AWS_PROFILE=demo-k8s` (override with
`BOOTSTRAP_PROFILE=...`) and derives the bucket name from the account ID
(override with `TFSTATE_BUCKET=...`).

## GitHub repository variables

The workflows read the role ARNs and the bucket name from repository
variables. None of them is secret. To set them all from the outputs:

```sh
terraform -chdir=infra/bootstrap output -json github_variables \
  | jq -r 'to_entries[] | "\(.key) \(.value)"' \
  | while read -r key value; do gh variable set "$key" --body "$value"; done
gh variable list
```

You can also set them by hand under *Settings → Secrets and variables →
Actions → Variables*. Show the values with `make bootstrap-outputs`.

| Variable | Value |
|---|---|
| `AWS_REGION` | `eu-north-1` |
| `AWS_PLAN_ROLE_ARN` | `arn:aws:iam::<acct>:role/demo-ota-plan` |
| `AWS_APPLY_ROLE_ARN` | `arn:aws:iam::<acct>:role/demo-ota-apply` |
| `AWS_TFSTATE_BUCKET` | `demo-ota-tfstate-<acct>` |
| `AWS_BOUNDARY_POLICY` | `arn:aws:iam::<acct>:policy/demo-ota-boundary` |

## Cost allocation tag `Project`

The budget filters on `Project=demoOTA`, and Cost Explorer splits costs
per demo by the same tag. AWS counts a tag only once it is **activated as
a cost allocation tag**. Neither `make` nor this stack does that: a tag
can be activated only after it has appeared on a billed resource, which
takes up to about 24 hours after the first apply.

Activate it once, after that delay:

- Console: *Billing and Cost Management → Cost allocation tags →
  User-defined*, select `Project`, *Activate*. Or:
- CLI: `AWS_PROFILE=demo-k8s aws ce update-cost-allocation-tags-status
  --cost-allocation-tags-status TagKey=Project,Status=Active`

In an AWS Organization, only the management account can activate it.
The key `Project` is shared: demoKubernetesCluster uses it too (with its
own value), so a single activation serves both projects. Activation
works going forward: costs from before it are not tagged. Until then the
tag-filtered budget shows $0, and demoKubernetesCluster's account-wide
budget is the safety net.

## Verify

The workflow [Verify AWS OIDC](../../.github/workflows/verify-aws-oidc.yml)
(`workflow_dispatch`) assumes the roles and runs `make aws-identity`
(`aws sts get-caller-identity`). GitHub can start a `workflow_dispatch`
workflow only once it is on the default branch, so run it after the
merge:

```sh
gh workflow run verify-aws-oidc.yml --ref main          # plan allowed, apply allowed
gh workflow run verify-aws-oidc.yml --ref <any-branch>  # plan allowed, apply refused
gh run list --workflow verify-aws-oidc.yml
```

The branch run passes only if `demo-ota-apply` is **refused**. It first
checks that `AWS_APPLY_ROLE_ARN` is set, so a missing variable is not
mistaken for a refusal.

## Teardown

There is no `make` target. This stack is the permanent base of the demo
and costs effectively nothing (see the cost impact in the PR of #3).
The state bucket (and the OIDC provider, if created here) have
`prevent_destroy`. To remove the bootstrap anyway:

1. Destroy every other demoOTA stack first; their state is in the bucket.
2. If this stack owns the OIDC provider, hand it over to
   demoKubernetesCluster first (see above).
3. Remove `prevent_destroy`, empty the versioned bucket, and run
   `terraform destroy` with local state.
