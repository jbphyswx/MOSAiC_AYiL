# shellcheck shell=bash
# Decide which MOSAiC days are eligible to run or submit.
# Source lib/run_status.sh before this file.

# Return 0 if this day should be run/submitted (not complete/running unless force).
ayil_should_submit_date() {
  local run_dir="$1"
  local force="${2:-0}"
  local state
  state="$(ayil_run_state "${run_dir}")"
  case "${state}" in
    complete | running)
      (( force == 1 ))
      ;;
    *)
      return 0
      ;;
  esac
}

# Populate global array AYIL_PENDING_DATES from explicit list or all inputs.
# Respects ayil_should_submit_date unless force includes complete days for listing.
ayil_collect_submit_dates() {
  local force="${1:-0}"
  local mode="${2:-explicit}" # explicit | pending | all
  shift 2 || true
  AYIL_PENDING_DATES=()
  local explicit=("$@")
  local candidates=()

  if [[ "${mode}" == "pending" || "${mode}" == "all" ]]; then
    mapfile -t candidates < <(
      find "${AYIL_INPUTS}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    )
  else
    candidates=("${explicit[@]}")
  fi

  local date run_dir
  for date in "${candidates[@]}"; do
    run_dir="${AYIL_RUNS}/${date}"
    if [[ "${mode}" == "all" ]] || ayil_should_submit_date "${run_dir}" "${force}"; then
      AYIL_PENDING_DATES+=("${date}")
    fi
  done
}
