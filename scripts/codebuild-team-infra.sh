#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
if [[ "$mode" != "plan" && "$mode" != "apply" ]]; then
  echo "usage: $0 plan|apply" >&2
  exit 2
fi

cd "${CODEBUILD_SRC_DIR:?CODEBUILD_SRC_DIR must be set}"
head="$(git rev-parse HEAD)"
git fetch --no-tags origin main

if [[ "$mode" == "plan" ]]; then
  base="$(git merge-base origin/main "$head")"
else
  checkpoint="$(aws ssm get-parameter --name "$CHECKPOINT_PARAMETER" --query 'Parameter.Value' --output text)"
  if [[ "$checkpoint" == "UNINITIALIZED" ]]; then
    base="0000000000000000000000000000000000000000"
  elif git cat-file -e "${checkpoint}^{commit}" 2>/dev/null; then
    base="$checkpoint"
  else
    echo "error: deployment checkpoint $checkpoint is not present in the source history" >&2
    exit 1
  fi
fi

changes="$(scripts/detect-changed-teams.sh "$base" "$head")"
teams="$(jq -r '.teams[]' <<<"$changes")"
offboarded="$(jq -r '.offboarded[]' <<<"$changes")"

team_parallelism="${TEAM_PARALLELISM:-8}"
if ! [[ "$team_parallelism" =~ ^([1-9]|1[0-9]|20)$ ]]; then
  echo "error: TEAM_PARALLELISM must be a whole number between 1 and 20" >&2
  exit 2
fi

logs_dir="$(mktemp -d)"
trap 'rm -rf "$logs_dir"' EXIT

process_team() {
  local team="$1"
  local plan_file public_buckets

  scripts/validate-team-files.sh "$team"
  echo "--- Terraform $mode: $team ---"
  if [[ "$mode" == "plan" ]]; then
    plan_file="${CODEBUILD_SRC_DIR}/.${team}.tfplan"
    scripts/tf.sh "$team" plan -lock-timeout=5m -out="$plan_file"
    scripts/tf.sh "$team" show -json "$plan_file" > "${plan_file}.json"
    public_buckets="$(scripts/public-bucket-gate.sh "${plan_file}.json")"
    if [[ -n "$public_buckets" ]]; then
      echo "Public bucket change for ${team}; include it in the required CodePipeline platform/security approval: ${public_buckets//$'\n'/, }"
    fi
    scripts/tf.sh "$team" show -no-color "$plan_file"
  else
    scripts/tf.sh "$team" apply -lock-timeout=5m -auto-approve
    if ! scripts/tf.sh "$team" plan -lock-timeout=5m -detailed-exitcode >/dev/null; then
      echo "error: ${team} is not idempotent: plan after apply is not empty" >&2
      exit 1
    fi
  fi
}

process_offboarded_team() {
  local team="$1"
  local old_file="${CODEBUILD_SRC_DIR}/.${team}-offboarding-team.yaml"
  git show "${base}:teams/${team}/team.yaml" > "$old_file"
  if [[ "$mode" == "plan" ]]; then
    scripts/tf.sh "$team" plan -destroy -lock-timeout=5m -var="team_file=${old_file}"
  else
    scripts/tf.sh "$team" apply -destroy -lock-timeout=5m -auto-approve -var="team_file=${old_file}"
  fi
}

worker_pids=()
worker_teams=()

wait_for_workers() {
  local failed=0
  local index

  for index in "${!worker_pids[@]}"; do
    if ! wait "${worker_pids[$index]}"; then
      echo "error: ${worker_teams[$index]} failed"
      failed=1
    fi
    printf '\n===== %s =====\n' "${worker_teams[$index]}"
    cat "${logs_dir}/${worker_teams[$index]}.log"
  done

  worker_pids=()
  worker_teams=()
  return "$failed"
}

run_parallel() {
  local worker="$1"
  local task_names="$2"
  local task_prefix="$3"
  local failed=0
  local team

  while IFS= read -r team; do
    [[ -z "$team" ]] && continue
    if [[ ! "$team" =~ ^[a-z][a-z0-9]{2,23}$ ]]; then
      echo "error: invalid team name '$team'"
      failed=1
      continue
    fi

    "$worker" "$team" > "${logs_dir}/${task_prefix}${team}.log" 2>&1 &
    worker_pids+=("$!")
    worker_teams+=("${task_prefix}${team}")

    if (( ${#worker_pids[@]} >= team_parallelism )); then
      if ! wait_for_workers; then
        failed=1
      fi
    fi
  done < <(printf '%s\n' "$task_names")

  if ! wait_for_workers; then
    failed=1
  fi
  return "$failed"
}

failed=0
if ! run_parallel process_team "$teams" ""; then
  failed=1
fi
if ! run_parallel process_offboarded_team "$offboarded" "offboard-"; then
  failed=1
fi
if ((failed != 0)); then
  exit 1
fi

if [[ "$mode" == "apply" ]]; then
  aws ssm put-parameter --name "$CHECKPOINT_PARAMETER" --type String --value "$head" --overwrite >/dev/null
fi