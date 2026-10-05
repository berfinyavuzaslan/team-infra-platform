#!/usr/bin/env bash
# Decide which teams a commit range affects.
#
#   scripts/detect-changed-teams.sh <base-sha> <head-sha>
#
# Outputs a JSON object with teams to plan/apply and deleted teams to offboard.
#
# Rules:
#   - Change under teams/<t>/          -> only team <t>
#   - Change to shared platform code   -> every team (the module affects all of them)
#   - teams/<t>/team.yaml deleted      -> <t> is offboarded (destroy, gated by approval)
set -euo pipefail

base="$1"
head="$2"
platform_paths='^(modules/|stack/|scripts/|schema/|buildspec/)'

list_all_teams() {
  git ls-tree -d --name-only "$head" teams/ | sed 's#^teams/##' | grep -v '^_' || true
}

if [[ "$base" =~ ^0+$ ]] || ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
  teams="$(list_all_teams)"
  offboarded=""
else
  changed="$(git diff --name-only "${base}...${head}")"
  if grep -Eq "$platform_paths" <<<"$changed"; then
    teams="$(list_all_teams)"
  else
    teams="$(grep -E '^teams/[^_/][^/]*/' <<<"$changed" | cut -d/ -f2 | sort -u |
      while read -r t; do git cat-file -e "${head}:teams/${t}/team.yaml" 2>/dev/null && echo "$t"; done || true)"
  fi
  offboarded="$(git diff --name-only --diff-filter=D "${base}...${head}" -- 'teams/*/team.yaml' |
    grep -v '^teams/_' | cut -d/ -f2 | sort -u || true)"
fi

to_json() { jq -Rcn '[inputs | select(length > 0)]'; }

# Directory names flow into state keys and CI job names: reject anything unexpected.
invalid="$(printf '%s\n%s\n' "$teams" "$offboarded" | grep -Ev '^([a-z][a-z0-9]{2,23})?$' || true)"
if [[ -n "$invalid" ]]; then
  echo "error: invalid team directory name(s): $invalid" >&2
  exit 1
fi

teams_json="$(to_json <<<"$teams")"
offboarded_json="$(to_json <<<"$offboarded")"

jq -cn --argjson teams "$teams_json" --argjson offboarded "$offboarded_json" \
  '{teams: $teams, offboarded: $offboarded}'
