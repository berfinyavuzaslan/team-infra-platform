# team-baseline

Provisions the baseline AWS footprint for one team: **one IAM role** and **1–50 S3 buckets**.

```hcl
module "team" {
  source = "../modules/team-baseline"

  team_name              = "payments"
  name_prefix            = "sumup"
  owner_email            = "payments-team@sumup.example"
  cost_center            = "CC-1001"
  buckets = {
    invoices      = { visibility = "private" }
    public-assets = { visibility = "public", retention_days = 365 }
  }
}
```

## Inputs

| Name | Type | Required | Notes |
|---|---|---|---|
| `team_name` | string | yes | `^[a-z][a-z0-9]{2,23}$`. No hyphens, so bucket names can't be ambiguous. |
| `name_prefix` | string | yes | Org prefix, 2–12 lowercase alphanumerics. |
| `owner_email` | string | yes | `Owner` tag. |
| `cost_center` | string | yes | `CostCenter` tag. |
| `buckets` | map(object({visibility, retention_days})) | yes | `visibility` is required. Optional retention defaults to 90 days; overrides must be 1–36,500 whole days. |
| `permissions_boundary_arn` | string | no | Set by the platform stack. |
| `tags` | map(string) | no | Extra tags. These can't override the ownership tags. |
| `force_destroy` | bool | no | Defaults to `false`. Only for ephemeral tests. |

## Outputs

`team_name`, `role_arn`, `role_name`, `buckets` (`{ <key> = { name, arn, visibility } }`).

## What the module enforces

| Control | Private | Public |
|---|---|---|
| Name `<prefix>-<team>-<key>`, ≤ 63 chars | ✔ | ✔ |
| ACLs disabled (`BucketOwnerEnforced`) | ✔ | ✔ |
| Block public ACLs | ✔ | ✔ |
| Block public **policy** | ✔ | ✘ (needed for the read grant) |
| Anonymous access | none | `s3:GetObject` only (no list, no write) |
| TLS-only bucket policy | ✔ | ✔ |
| SSE-S3 encryption, versioning, MPU cleanup | ✔ | ✔ |
| Object Lock Compliance retention | Per-bucket `retention_days` | Per-bucket `retention_days` |

The role trusts the deployment account; callers still need identity-based `sts:AssumeRole` permission. Its S3 policy grants object read/write and list access only to this team's explicit bucket ARNs, with `s3:ResourceAccount` enforced. It has no wildcards, bucket-admin actions, `DeleteObjectVersion`, or `PutObjectRetention`. Default retention applies to new object versions; existing versions are not retroactively locked, and Compliance retention cannot be shortened or bypassed, including by account administrators.

`force_destroy = true` is reserved for ephemeral tests and disables Object Lock configuration so those tests can clean up. The platform stack does not expose this option.

## Tests

```bash
terraform init -backend=false
terraform test -test-directory=tests/unit         # offline, mocked provider
terraform init -backend=false -test-directory=tests/integration
terraform test -test-directory=tests/integration  # real sandbox account, auto-destroys
```
