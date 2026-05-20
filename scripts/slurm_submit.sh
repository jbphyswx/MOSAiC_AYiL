#!/usr/bin/env bash
# Submit Slurm job(s) for MOSAiC AYIL DALES runs. Skips complete days unless --force.
#
# Usage:
#   slurm_submit.sh --pending                 # one job array for all submit-eligible days
#   slurm_submit.sh --pending --limit 5
#   slurm_submit.sh 20200720 20200721         # explicit dates (still skips complete)
#   slurm_submit.sh --pending --separate      # one sbatch per day (not an array)
#   slurm_submit.sh --pending --dry-run
#   slurm_submit.sh --pending --force         # include complete days (re-run)
#
# Options:
#   --force       Re-run complete days (passed to jobs as AYIL_FORCE=1)
#   --dry-run     Print what would be submitted; do not call sbatch
#   --limit N     Submit at most N days
#   --separate    Individual sbatch per day (default: single job array, no concurrency cap)
#   --status      Show submit/skip breakdown only
#
# Prereqs: build dales4 on the login node (./scripts/build_dales.sh) unless
#   AYIL_SLURM_BUILD=1 in env.local.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/run_status.sh
source "${SCRIPT_DIR}/lib/run_status.sh"
# shellcheck source=lib/pending_dates.sh
source "${SCRIPT_DIR}/lib/pending_dates.sh"
# shellcheck source=lib/slurm_defaults.sh
source "${SCRIPT_DIR}/lib/slurm_defaults.sh"
# shellcheck source=lib/logging_paths.sh
source "${SCRIPT_DIR}/lib/logging_paths.sh"

FORCE=0
DRY_RUN=0
LIMIT=0
SEPARATE=0
MODE="pending"
DATES=()

usage() {
  sed -n '2,22p' "$0"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --separate) SEPARATE=1; shift ;;
    --pending) MODE="pending"; shift ;;
    --status) MODE="status"; shift ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *) DATES+=("$1"); MODE="explicit"; shift ;;
  esac
done

if ! command -v sbatch &>/dev/null; then
  echo "ERROR: sbatch not found (not on a Slurm cluster?)" >&2
  exit 1
fi

if [[ "${MODE}" == "pending" ]]; then
  ayil_collect_submit_dates "${FORCE}" pending
elif [[ ${#DATES[@]} -eq 0 ]]; then
  echo "No dates given. Use --pending or YYYYMMDD list." >&2
  usage 1
else
  ayil_collect_submit_dates "${FORCE}" explicit "${DATES[@]}"
fi

TO_SUBMIT=()
SKIPPED=()

for date in "${AYIL_PENDING_DATES[@]}"; do
  run_dir="${AYIL_RUNS}/${date}"
  if ayil_should_submit_date "${run_dir}" "${FORCE}"; then
    TO_SUBMIT+=("${date}")
  else
    SKIPPED+=("${date}")
  fi
done

if [[ "${LIMIT}" -gt 0 && ${#TO_SUBMIT[@]} -gt "${LIMIT}" ]]; then
  TO_SUBMIT=("${TO_SUBMIT[@]:0:${LIMIT}}")
fi

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if [[ "${MODE}" == "status" ]]; then
  printf "%-12s %-12s %s\n" "DATE" "STATE" "SUBMIT?"
  for date in "${AYIL_PENDING_DATES[@]}"; do
    run_dir="${AYIL_RUNS}/${date}"
    state="$(ayil_run_state "${run_dir}")"
    sub="no"
    if ayil_should_submit_date "${run_dir}" "${FORCE}"; then
      sub="yes"
    fi
    printf "%-12s %-12s %s\n" "${date}" "${state}" "${sub}"
  done
  echo ""
  echo "Would submit: ${#TO_SUBMIT[@]}  Would skip: ${#SKIPPED[@]}"
  exit 0
fi

if ((${#SKIPPED[@]} > 0)); then
  log_msg "Skipping ${#SKIPPED[@]} day(s) (complete or running; use --force to include):"
  for date in "${SKIPPED[@]}"; do
    log_msg "  SKIP ${date}  state=$(ayil_run_state "${AYIL_RUNS}/${date}")"
  done
fi

if ((${#TO_SUBMIT[@]} == 0)); then
  log_msg "Nothing to submit — all requested days are complete or running."
  exit 0
fi

mkdir -p "${AYIL_SLURM_LOG_DIR}"
DATE_LIST="${AYIL_RUNS}/.slurm_pending_dates"
printf '%s\n' "${TO_SUBMIT[@]}" > "${DATE_LIST}"

log_msg "Submit list (${#TO_SUBMIT[@]} days) -> ${DATE_LIST}"
for date in "${TO_SUBMIT[@]}"; do
  log_msg "  RUN ${date}"
done

ayil_slurm_sbatch_opts SBATCH_OPTS
SLURM_SCRIPT="${SCRIPT_DIR}/slurm/run_day.slurm"
EXPORT_BASE="ALL,AYIL_SLURM_DATE_LIST=${DATE_LIST},AYIL_FORCE=${FORCE},MOSAiC_AYIL_ROOT=${MOSAiC_AYIL_ROOT}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log_msg "DRY-RUN: would submit with:"
  printf '  %s\n' "${SBATCH_OPTS[@]}"
  if [[ "${SEPARATE}" -eq 1 ]]; then
    for date in "${TO_SUBMIT[@]}"; do
      log_msg "  sbatch ${SBATCH_OPTS[*]} --export=${EXPORT_BASE},DATE=${date} ${SLURM_SCRIPT}"
    done
  else
    local_last=$(( ${#TO_SUBMIT[@]} - 1 ))
    array_spec="$(ayil_slurm_array_spec "${local_last}")"
    log_msg "  sbatch ${SBATCH_OPTS[*]} --array=${array_spec} --export=${EXPORT_BASE} ${SLURM_SCRIPT}"
  fi
  exit 0
fi

if [[ ! -x "${DALES_BIN}" && "${AYIL_SLURM_BUILD:-0}" != "1" ]]; then
  echo "ERROR: ${DALES_BIN} missing. Build on the login node:" >&2
  echo "  ./scripts/build_dales.sh" >&2
  echo "Or set AYIL_SLURM_BUILD=1 in scripts/env.local to compile in each job." >&2
  exit 1
fi

submit_one() {
  local date="$1"
  local run_dir="${AYIL_RUNS}/${date}"
  ayil_ensure_run_logs "${run_dir}"
  sbatch "${SBATCH_OPTS[@]}" \
    --output="$(ayil_slurm_log_out "${run_dir}")" \
    --error="$(ayil_slurm_log_err "${run_dir}")" \
    --export="${EXPORT_BASE},DATE=${date}" \
    "${SLURM_SCRIPT}"
}

submit_array() {
  local last="$1"
  local array_spec="$2"
  sbatch "${SBATCH_OPTS[@]}" \
    --array="${array_spec}" \
    --export="${EXPORT_BASE}" \
    "${SLURM_SCRIPT}"
}

ARRAY_LAST=$(( ${#TO_SUBMIT[@]} - 1 ))
ARRAY_SPEC="$(ayil_slurm_array_spec "${ARRAY_LAST}")"

if [[ "${SEPARATE}" -eq 1 ]]; then
  job_ids=()
  for date in "${TO_SUBMIT[@]}"; do
    jid="$(submit_one "${date}")"
    log_msg "${jid}  DATE=${date}"
    job_ids+=("${jid}")
  done
  log_msg "Submitted ${#job_ids[@]} separate jobs."
else
  jid="$(submit_array "${ARRAY_LAST}" "${ARRAY_SPEC}")"
  log_msg "${jid}  array=${ARRAY_SPEC}  (${#TO_SUBMIT[@]} tasks)"
  log_msg "Monitor: squeue -u \$USER   Cancel: scancel ${jid%% *}"
fi

log_msg "Per-run logs: ${AYIL_RUNS}/<DATE>/logs/{slurm.out,slurm.err,dales.log}"
log_msg "Slurm cluster copy (arrays): ${AYIL_SLURM_LOG_DIR}/"
