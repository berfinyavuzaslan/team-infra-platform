#!/usr/bin/env bash
# Run Terraform for one team against its own isolated state.
#
#   scripts/tf.sh <team> plan
#   scripts/tf.sh <team> apply -auto-approve
#   scripts/tf.sh <team> show -json plans/<team>.tfplan
#
# Every team gets its own state object (teams/<team>/terraform.tfstate) and its own
# local working directory (TF_DATA_DIR), so several teams can be processed in one job.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <team> <terraform-command> [args...]" >&2
  exit 2
fi

team="$1"; shift
cmd="$1"; shift

# Validated before it is used in a state key or path.
if [[ ! "$team" =~ ^[a-z][a-z0-9]{2,23}$ ]]; then
  echo "error: invalid team name '$team'" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TF_DATA_DIR="${repo_root}/.terraform-data/${team}"

tf() { terraform -chdir="${repo_root}/stack" "$@"; }

tf init -input=false -reconfigure \
  -backend-config=backend.hcl \
  -backend-config="key=teams/${team}/terraform.tfstate" >/dev/null

case "$cmd" in
  init) ;;
  plan | apply | destroy | import | console | refresh)
    tf "$cmd" -input=false -var="team_name=${team}" "$@" ;;
  *)
    tf "$cmd" "$@" ;;
esac
