#!/usr/bin/env bash
# Submit Slurm job(s) for MOSAiC AYIL DALES runs. Skips complete days unless --force.
#
# Default: chunked mode — short sim segments (default 600 s) with sbatch --time scaled
# from AYIL_CHUNK_SIM_SEC. Use --no-chunked for one job/day (wall scales to full runtime).
#
# Usage:
#   slurm_submit.sh --pending                 # chunked chains for all eligible days
#   slurm_submit.sh --pending --limit 5
#   slurm_submit.sh 20200720 20200721         # explicit dates
#   slurm_submit.sh --pending --dry-run
#   slurm_submit.sh --pending --force         # re-run complete days
#   slurm_submit.sh --pending --no-chunked    # single 3 h job per day (needs walltime)
#
# Options:
#   --force       Re-run .ayil_complete days; chunk 0 wipes outputs, later chunks keep them
#   --dry-run     Print what would be submitted; do not call sbatch
#   --limit N     Submit at most N days
#   --no-chunked  One sbatch per day (no restart chain; may hit 8 h wall before 10800 s)
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
# shellcheck source=lib/chunk_run.sh
source "${SCRIPT_DIR}/lib/chunk_run.sh"
# shellcheck source=lib/zenodo_inputs.sh
source "${SCRIPT_DIR}/lib/zenodo_inputs.sh"

FORCE=0
DRY_RUN=0
LIMIT=0
CHUNKED=1
MODE="pending"
DATES=()

usage() {
  sed -n '2,28p' "$0"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --no-chunked) CHUNKED=0; shift ;;
    --chunked) CHUNKED=1; shift ;;
    --pending) MODE="pending"; shift ;;
    --status) MODE="status"; shift ;;
    --separate)
      echo "NOTE: --separate is ignored; chunked mode always uses per-day job chains." >&2
      shift
      ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *) DATES+=("$1"); MODE="explicit"; shift ;;
  esac
done

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
    if [[ "${CHUNKED}" -eq 1 ]]; then
      n_chunks="$(ayil_n_chunks)"
      first="$(ayil_first_incomplete_chunk "${run_dir}" "${n_chunks}")"
      if (( first < 0 )) && (( FORCE != 1 )); then
        SKIPPED+=("${date}")
        continue
      fi
    fi
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

# Reject dates that are not in ayil_config_input_results (calendar YYYYMMDD ≠ AYIL day).
INVALID_INPUTS=()
VALID_SUBMIT=()
for date in "${TO_SUBMIT[@]}"; do
  if ayil_day_inputs_ready "${date}"; then
    VALID_SUBMIT+=("${date}")
  else
    INVALID_INPUTS+=("${date}")
  fi
done
TO_SUBMIT=("${VALID_SUBMIT[@]}")

if [[ "${MODE}" == "status" ]]; then
  printf "%-12s %-10s %-12s %s\n" "DATE" "INPUTS" "STATE" "SUBMIT?"
  for date in "${AYIL_PENDING_DATES[@]}"; do
    run_dir="${AYIL_RUNS}/${date}"
    state="$(ayil_run_state "${run_dir}")"
    inputs="no"
    if ayil_day_inputs_ready "${date}"; then
      inputs="yes"
    fi
    sub="no"
    if [[ "${inputs}" == "yes" ]] && ayil_should_submit_date "${run_dir}" "${FORCE}"; then
      sub="yes"
    fi
    printf "%-12s %-10s %-12s %s\n" "${date}" "${inputs}" "${state}" "${sub}"
  done
  echo ""
  echo "Would submit: ${#TO_SUBMIT[@]}  Would skip: ${#SKIPPED[@]}  No inputs: ${#INVALID_INPUTS[@]}"
  exit 0
fi

if ((${#INVALID_INPUTS[@]} > 0)); then
  log_msg "ERROR: ${#INVALID_INPUTS[@]} date(s) are not MOSAiC AYIL input days under ${AYIL_INPUTS}:"
  for date in "${INVALID_INPUTS[@]}"; do
    log_msg "  NO_INPUTS ${date}  (not in Zenodo bundle — do not use arbitrary calendar dates)"
  done
  log_msg "Fix the date list or use: ./scripts/slurm_submit.sh --pending --dry-run"
  if ((${#TO_SUBMIT[@]} == 0)); then
    exit 1
  fi
  log_msg "Continuing with ${#TO_SUBMIT[@]} valid day(s) only."
fi

if ((${#SKIPPED[@]} > 0)); then
  log_msg "Skipping ${#SKIPPED[@]} day(s) (complete or running; use --force to include):"
  for date in "${SKIPPED[@]}"; do
    log_msg "  SKIP ${date}  state=$(ayil_run_state "${AYIL_RUNS}/${date}")"
  done
fi

if ((${#TO_SUBMIT[@]} == 0)); then
  log_msg "Nothing to submit — all requested days are skipped (complete, running in queue, or no incomplete chunks)."
  if ((${#SKIPPED[@]} > 0)); then
    for date in "${SKIPPED[@]}"; do
      run_dir="${AYIL_RUNS}/${date}"
      ayil_recover_stale_run_state "${run_dir}"
      extra=""
      if [[ "${CHUNKED}" -eq 1 ]]; then
        first="$(ayil_first_incomplete_chunk "${run_dir}" "$(ayil_n_chunks)")"
        extra=" first_incomplete_chunk=${first}"
      fi
      log_msg "  SKIP ${date}  state=$(ayil_run_state "${run_dir}")${extra}"
    done
    log_msg "If a Slurm TIMEOUT left a stale lock: rm runs/YYYYMMDD/.ayil_running then re-submit, or pull latest scripts (auto-clears)."
  fi
  exit 0
fi

log_msg "Submit list (${#TO_SUBMIT[@]} days) chunked=${CHUNKED}"
for date in "${TO_SUBMIT[@]}"; do
  log_msg "  RUN ${date}"
done

if [[ "${CHUNKED}" -eq 1 ]]; then
  export AYIL_SLURM_WALL_SIM_SEC="${AYIL_CHUNK_SIM_SEC}"
else
  export AYIL_SLURM_WALL_SIM_SEC="${AYIL_DAY_RUNTIME_SEC}"
fi

ayil_slurm_sbatch_opts SBATCH_OPTS
WALL_TIME="$(ayil_slurm_resolve_time)"
WALL_PER_SIM="$(ayil_slurm_effective_wall_per_sim_sec)"
log_msg "sbatch --time=${WALL_TIME} (sim_seg=${AYIL_SLURM_WALL_SIM_SEC}s, ntasks=${AYIL_SLURM_NTASKS}, wall/sim=${WALL_PER_SIM}, cap=${AYIL_SLURM_WALL_MAX_SEC}s)"
SLURM_SCRIPT="${SCRIPT_DIR}/slurm/run_day.slurm"
EXPORT_BASE="ALL,AYIL_FORCE=${FORCE},MOSAiC_AYIL_ROOT=${MOSAiC_AYIL_ROOT}"

if [[ "${CHUNKED}" -eq 1 ]]; then
  N_CHUNKS="$(ayil_n_chunks)"
  EXPORT_BASE="${EXPORT_BASE},AYIL_USE_RESTART_CHUNKS=1,AYIL_N_CHUNKS=${N_CHUNKS}"
  EXPORT_BASE="${EXPORT_BASE},AYIL_DAY_RUNTIME_SEC=${AYIL_DAY_RUNTIME_SEC},AYIL_CHUNK_SIM_SEC=${AYIL_CHUNK_SIM_SEC}"
else
  EXPORT_BASE="${EXPORT_BASE},AYIL_USE_RESTART_CHUNKS=0"
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log_msg "DRY-RUN (no sbatch): would submit with:"
  printf '  %s\n' "${SBATCH_OPTS[@]}"
  for date in "${TO_SUBMIT[@]}"; do
    if [[ "${CHUNKED}" -eq 1 ]]; then
      first="$(ayil_first_incomplete_chunk "${AYIL_RUNS}/${date}" "${N_CHUNKS}")"
      (( first < 0 )) && first=0
      dep=""
      for ((c = first; c < N_CHUNKS; c++)); do
        dep_flag=""
        [[ -n "${dep}" ]] && dep_flag=" --dependency=afterok:${dep}"
        log_msg "  sbatch${dep_flag} ${SBATCH_OPTS[*]} --job-name=ayil_${date}_c${c} --export=${EXPORT_BASE},DATE=${date},AYIL_CHUNK_INDEX=${c} ${SLURM_SCRIPT}"
        dep="<job_${c}>"
      done
    else
      log_msg "  sbatch ${SBATCH_OPTS[*]} --export=${EXPORT_BASE},DATE=${date} ${SLURM_SCRIPT}"
    fi
  done
  exit 0
fi

if ! command -v sbatch &>/dev/null; then
  echo "ERROR: sbatch not found (not on a Slurm cluster?)" >&2
  exit 1
fi

if [[ ! -x "${DALES_BIN}" && "${AYIL_SLURM_BUILD:-0}" != "1" ]]; then
  echo "ERROR: ${DALES_BIN} missing. Build on the login node:" >&2
  echo "  ./scripts/build_dales.sh" >&2
  echo "Or set AYIL_SLURM_BUILD=1 in scripts/env.local to compile in each job." >&2
  exit 1
fi

submit_chunk_chain() {
  local date="$1"
  local run_dir="${AYIL_RUNS}/${date}"
  local first n_chunks c
  n_chunks="$(ayil_n_chunks)"
  first="$(ayil_first_incomplete_chunk "${run_dir}" "${n_chunks}")"
  if (( first < 0 )); then
    first=0
  fi
  local prev_jid="" jid dep_args
  for ((c = first; c < n_chunks; c++)); do
    dep_args=()
    if [[ -n "${prev_jid}" ]]; then
      dep_args=(--dependency=afterok:"${prev_jid}")
    fi
    jid="$(
      sbatch "${SBATCH_OPTS[@]}" "${dep_args[@]}" \
        --job-name="ayil_${date}_c${c}" \
        --export="${EXPORT_BASE},DATE=${date},AYIL_CHUNK_INDEX=${c}" \
        "${SLURM_SCRIPT}" | awk '{print $NF}'
    )"
    log_msg "  ${jid}  DATE=${date}  chunk=${c}/${n_chunks}"
    prev_jid="${jid}"
  done
}

submit_one_day() {
  local date="$1"
  sbatch "${SBATCH_OPTS[@]}" \
    --job-name="ayil_${date}" \
    --export="${EXPORT_BASE},DATE=${date}" \
    "${SLURM_SCRIPT}"
}

total_jobs=0
if [[ "${CHUNKED}" -eq 1 ]]; then
  for date in "${TO_SUBMIT[@]}"; do
    log_msg "Submit chain ${date} ($(ayil_n_chunks) chunks, --time=${WALL_TIME} each):"
    submit_chunk_chain "${date}"
    total_jobs=$(( total_jobs + $(ayil_n_chunks) ))
  done
  log_msg "Submitted ${#TO_SUBMIT[@]} day(s) (${total_jobs} chunk jobs total; many days can run in parallel)."
else
  for date in "${TO_SUBMIT[@]}"; do
    jid="$(submit_one_day "${date}")"
    log_msg "${jid}  DATE=${date}"
    total_jobs=$(( total_jobs + 1 ))
  done
  log_msg "Submitted ${total_jobs} job(s) (one per day; ensure walltime covers ${AYIL_DAY_RUNTIME_SEC}s sim)."
fi

log_msg "Per-run logs: ${AYIL_RUNS}/<DATE>/logs/{slurm.out,progress.log,dales.log}"
