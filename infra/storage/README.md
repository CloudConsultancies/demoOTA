# Storage (S3)

Buckets for the image build, the releases and the fleet. The first stack
that CI plans and applies through the OIDC roles of the
[bootstrap](../bootstrap/README.md). Later stacks follow the same
pattern.

State: `s3://demo-ota-tfstate-<account ID>/storage/terraform.tfstate`.

## Buckets

| Bucket | Holds | Versioning | Lifecycle | Destroy |
|---|---|---|---|---|
| `demo-ota-artifacts-<account ID>` | RAUC bundles, SBOMs, CVE reports | on | old versions expire after 7 days (`artifacts_noncurrent_days`) | `prevent_destroy`, kept |
| `demo-ota-cache-<account ID>` | Yocto downloads and sstate | off | objects expire 30 days after creation (`cache_expiration_days`) | `force_destroy`, `make storage-destroy-cache` |
| `demo-ota-records-<account ID>` | rollout audit log, per-device update results | on | none: kept long-term | `prevent_destroy`, kept |

Every bucket has the same baseline
([modules/private-bucket](modules/private-bucket/main.tf)):

- SSE-S3 encryption, which is free (no KMS key);
- public access blocked;
- ACLs off (`BucketOwnerEnforced`);
- a bucket policy that denies requests without TLS.

All buckets carry the tags `Project=demoOTA`, `ManagedBy=terraform` and
`Stack=demo-ota-storage`. Incomplete multipart uploads are aborted after
one day.

Devices will read artifacts only through pre-signed URLs (HTTPS), which
the TLS-only policy allows. There is no public access.

S3 lifecycle rules count days from when an object was created, not from
its last read. A cache object that is still in use therefore also
expires after 30 days, and the next build uploads it again.

## How it is applied

The [Infra workflow](../../.github/workflows/infra.yml) runs `make`
targets only:

| Event | Role | Targets |
|---|---|---|
| pull request | `demo-ota-plan` (read-only) | `tf-check`, `infra-plan`, `infra-plan-comment` (one comment per stack, updated on every push) |
| push to `main`, or run by hand on `main` | `demo-ota-apply` | `tf-check`, `infra-plan`, `infra-apply` |

The apply on `main` plans again and applies that plan. It does not reuse
the pull request's plan, so check the plan in the PR comment against
what `main` will hold after the merge.

Locally (read-only, a human):

```sh
AWS_PROFILE=demo-k8s make infra-plan    # STACK=storage is the default
```

## GitHub repository variables

The bucket names are fixed. After the first apply, store them once as
repository variables (with the `demo-k8s` profile and `gh`):

```sh
make storage-github-vars
```

| Variable | Value |
|---|---|
| `AWS_ARTIFACTS_BUCKET` | `demo-ota-artifacts-<acct>` |
| `AWS_CACHE_BUCKET` | `demo-ota-cache-<acct>` |
| `AWS_RECORDS_BUCKET` | `demo-ota-records-<acct>` |

CI cannot do this step itself: `GITHUB_TOKEN` cannot write repository
variables.

## Cost

About $1 per month for what stays between demos (~5 GB of artifacts,
~40 GB of cache, records in KB, at $0.023 per GB-month in eu-north-1),
plus a few cents of requests per build. This was agreed in #4.

## Teardown

After a demo:

```sh
make storage-destroy-cache   # shows the plan, asks for confirmation
```

This removes the cache bucket with its contents. Artifacts and records
are kept on purpose and have `prevent_destroy`. The next apply on `main`
(or a manual run of the Infra workflow) creates the cache bucket again.
