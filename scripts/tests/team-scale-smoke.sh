#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

origin="$test_root/origin.git"
seed="$test_root/seed"
markers="$test_root/markers"
mkdir -p "$markers"

git init --bare --initial-branch=main "$origin" >/dev/null
git clone "$origin" "$seed" >/dev/null
git -C "$seed" config user.name "Team scale smoke test"
git -C "$seed" config user.email "scale-smoke@example.invalid"
mkdir -p "$seed/scripts" "$seed/teams" "$seed/modules/team-baseline"
cp "$repo_root/scripts/codebuild-team-infra.sh" "$seed/scripts/"
cp "$repo_root/scripts/detect-changed-teams.sh" "$seed/scripts/"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  ': > "${SMOKE_MARKERS}/validated-${1}"' \
  > "$seed/scripts/validate-team-files.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'team="$1"' \
  'command="$2"' \
  'shift 2' \
  'if [[ "$command" == "plan" ]]; then' \
  '  : > "${SMOKE_MARKERS}/planned-${team}"' \
  '  for argument in "$@"; do' \
  '    if [[ "$argument" == -out=* ]]; then printf "%s\n" fake-plan > "${argument#-out=}"; fi' \
  '  done' \
  'elif [[ "$command" == "show" && "${1:-}" == "-json" ]]; then' \
  '  printf "%s\n" '\''{"resource_changes":[]} '\''' \
  'fi' \
  > "$seed/scripts/tf.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'exit 0' \
  > "$seed/scripts/public-bucket-gate.sh"
chmod +x "$seed/scripts/validate-team-files.sh" "$seed/scripts/tf.sh" "$seed/scripts/public-bucket-gate.sh"

for number in $(seq -w 1 300); do
  team="team${number}"
  mkdir -p "$seed/teams/$team"
  printf 'team: %s\n' "$team" > "$seed/teams/$team/team.yaml"
done

git -C "$seed" add .
git -C "$seed" commit -m "Add 300 synthetic teams" >/dev/null
git -C "$seed" push origin main >/dev/null

prepare_change() {
  local checkout="$1"
  local branch="$2"
  git clone --branch main "$origin" "$checkout" >/dev/null
  git -C "$checkout" config user.name "Team scale smoke test"
  git -C "$checkout" config user.email "scale-smoke@example.invalid"
  git -C "$checkout" checkout -b "$branch" >/dev/null
}

run_plan() {
  local checkout="$1"
  local log="$2"
  pushd "$checkout" >/dev/null
  if ! CODEBUILD_SRC_DIR="$checkout" SMOKE_MARKERS="$markers" TEAM_PARALLELISM=8 \
    bash scripts/codebuild-team-infra.sh plan > "$log" 2>&1; then
    tail -n 80 "$log" >&2
    popd >/dev/null
    return 1
  fi
  popd >/dev/null
}

count_markers() {
  find "$markers" -type f -name "$1" -print | wc -l | tr -d '[:space:]'
}

single_checkout="$test_root/single-team-change"
prepare_change "$single_checkout" "single-team-change"
printf '\n# scale smoke change\n' >> "$single_checkout/teams/team042/team.yaml"
git -C "$single_checkout" add teams/team042/team.yaml
git -C "$single_checkout" commit -m "Change one team" >/dev/null
run_plan "$single_checkout" "$test_root/single-team.log"
single_count="$(count_markers 'planned-*')"
if [[ "$single_count" != "1" || ! -f "$markers/planned-team042" ]]; then
  echo "error: a team-only change should plan only team042; planned ${single_count} teams" >&2
  exit 1
fi

find "$markers" -type f -delete
shared_checkout="$test_root/shared-platform-change"
prepare_change "$shared_checkout" "shared-platform-change"
mkdir -p "$shared_checkout/modules/team-baseline"
printf 'shared platform change\n' > "$shared_checkout/modules/team-baseline/scale-smoke.txt"
git -C "$shared_checkout" add modules/team-baseline/scale-smoke.txt
git -C "$shared_checkout" commit -m "Change shared module" >/dev/null
run_plan "$shared_checkout" "$test_root/shared-platform.log"
shared_count="$(count_markers 'planned-*')"
validated_count="$(count_markers 'validated-*')"
if [[ "$shared_count" != "300" || "$validated_count" != "300" ]]; then
  echo "error: shared-code change should validate and plan 300 teams; validated=${validated_count} planned=${shared_count}" >&2
  exit 1
fi

printf '%s\n' "Scale smoke test passed: one-team changes plan one team; shared-code changes plan all 300 with bounded parallelism."