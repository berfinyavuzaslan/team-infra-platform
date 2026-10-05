#!/usr/bin/env bash
# Policy check on a plan: print every bucket that this plan makes public
# (new public bucket, or private -> public). Empty output means nothing to approve.
#
#   terraform show -json plan.tfplan > plan.json
#   scripts/public-bucket-gate.sh plan.json
set -euo pipefail

jq -r '
  .resource_changes[]?
  | select(.type == "aws_s3_bucket_public_access_block")
  | select(.change.actions | index("create") or index("update"))
  | select(.change.after.block_public_policy == false)
  | select(.change.before == null or .change.before.block_public_policy == true)
  | .index
' "$1"
