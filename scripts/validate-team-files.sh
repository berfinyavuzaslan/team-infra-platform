#!/usr/bin/env bash
# Validate team files before Terraform ever runs: JSON schema + directory/name match.
# Requires: check-jsonschema (pip install check-jsonschema)
#
#   scripts/validate-team-files.sh                 # all teams
#   scripts/validate-team-files.sh payments ledger # selected teams
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ $# -gt 0 ]]; then
  files=()
  for t in "$@"; do files+=("teams/${t}/team.yaml"); done
else
  files=(teams/*/team.yaml)
fi

check-jsonschema --schemafile schema/team.schema.json "${files[@]}"

rc=0
for f in "${files[@]}"; do
  dir="$(basename "$(dirname "$f")")"
  [[ "$dir" == _* ]] && continue
  declared="$(sed -nE 's/^team:[[:space:]]*["'\'']?([a-z0-9]+)["'\'']?[[:space:]]*$/\1/p' "$f")"
  if [[ "$declared" != "$dir" ]]; then
    echo "error: $f declares team '$declared' but lives in teams/$dir/" >&2
    rc=1
  fi
done
exit "$rc"
