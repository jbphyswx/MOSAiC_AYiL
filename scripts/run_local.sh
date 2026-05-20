#!/usr/bin/env bash
# Run AYIL DALES simulations locally (no Slurm): one day at a time, resumable, interrupt-safe.
#
# Usage:
#   run_local.sh 20200720 20200721          # specific dates
#   run_local.sh --pending                  # all not complete
#   run_local.sh --pending --limit 3        # next 3 incomplete days
#   run_local.sh --status 20200720          # print status only
#
# Options:
#   --nproc N       MPI ranks (default: DALES_NPROC or 64; must divide 320)
#   --force         Re-run even if complete; delete prior outputs (keeps inputs)
#   --prepare-only  Stage inputs, do not run
#   --dry-run       Print planned actions
#   --limit N       Max number of days to run this invocation
#   --interval SEC  Progress log interval (default: 30)
#
# Run ONE simulation at a time on shared workstations (CPU + RAM + disk).
# MPI rank count must divide grid 320; auto-detected via ./scripts/diagnose_mpi.sh
#
# Interrupts: Ctrl+C sends SIGTERM to mpirun, writes .ayil_interrupted, exits.
#   Re-run the same date without --force to retry incomplete days.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/run_status.sh
source "${SCRIPT_DIR}/lib/run_status.sh"
# shellcheck source=lib/mpi_slots.sh
source "${SCRIPT_DIR}/lib/mpi_slots.sh"
# shellcheck source=lib/logging_paths.sh
source "${SCRIPT_DIR}/lib/logging_paths.sh"
# shellcheck source=lib/chunk_run.sh
source "${SCRIPT_DIR}/lib/chunk_run.sh"

NPROC_REQUESTED="${DALES_NPROC:-64}"
NPROC="${NPROC_REQUESTED}"
FORCE=0
AUTO_NPROC=1
PREPARE_ONLY=0
DRY_RUN=0
LIMIT=0
INTERVAL="${AYIL_PROGRESS_INTERVAL:-30}"
MODE="run"
DATES=()

usage() {
  sed -n '2,22p' "$0"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --nproc) NPROC_REQUESTED="$2"; NPROC="$2"; AUTO_NPROC=0; shift 2 ;;
    --force) FORCE=1; shift ;;
    --prepare-only) PREPARE_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --pending) MODE="pending"; shift ;;
    --status) MODE="status"; shift ;;
    --estimate) "${SCRIPT_DIR}/estimate_output_gb.sh" "${NPROC}"; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *) DATES+=("$1"); shift ;;
  esac
done

if (( AUTO_NPROC == 1 )); then
  NPROC="$(ayil_resolve_nproc "${NPROC_REQUESTED}")"
  if (( NPROC != NPROC_REQUESTED )); then
    echo "NOTE: Adjusted MPI ranks ${NPROC_REQUESTED} -> ${NPROC} (Open MPI slots / grid factors)." >&2
  fi
fi
valid_factors=(1 2 4 5 8 10 16 20 32 40 64 80 160 320)
ok=0
for f in "${valid_factors[@]}"; do
  if (( NPROC == f )); then ok=1; break; fi
done
if (( ok == 0 )); then
  echo "ERROR: NPROC=${NPROC} must divide grid 320. Run: ./scripts/diagnose_mpi.sh" >&2
  exit 1
fi
# Final launch check
if ! "${MPIRUN}" ${AYIL_MPIRUN_EXTRA:-} -np "${NPROC}" /bin/true &>/dev/null; then
  echo "ERROR: ${MPIRUN} -np ${NPROC} failed. Run: ./scripts/diagnose_mpi.sh" >&2
  exit 1
fi

if [[ "${MODE}" == "pending" && ${#DATES[@]} -eq 0 ]]; then
  mapfile -t ALL < <(find "${AYIL_INPUTS}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  for d in "${ALL[@]}"; do
    state="$(ayil_run_state "${AYIL_RUNS}/${d}")"
    if [[ "${state}" != "complete" ]]; then
      DATES+=("${d}")
    fi
  done
fi

if [[ ${#DATES[@]} -eq 0 ]]; then
  echo "No dates to process. Pass YYYYMMDD list or --pending." >&2
  usage 1
fi

if [[ ! -x "${DALES_BIN}" && "${PREPARE_ONLY}" -eq 0 && "${MODE}" != "status" ]]; then
  echo "ERROR: ${DALES_BIN} missing. Run ./scripts/build_dales.sh" >&2
  exit 1
fi

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

ayil_clean_outputs() {
  local run_dir="$1"
  log_msg "Cleaning prior outputs in ${run_dir}"
  ayil_clean_run_outputs "${run_dir}"
}

monitor_run() {
  local run_dir="$1"
  local log="$2"
  local runtime="$3"
  local start_bytes
  start_bytes=$(ayil_dir_size_bytes "${run_dir}")
  local last_bytes="${start_bytes}"

  while [[ -f "${run_dir}/${AYIL_STATUS_RUNNING}" ]]; do
    sleep "${INTERVAL}"
    [[ -f "${log}" ]] || continue
    local now_bytes sim pct disk_h
    now_bytes=$(ayil_dir_size_bytes "${run_dir}")
    sim="$(ayil_last_sim_time "${log}" 2>/dev/null || echo "?")"
    if [[ "${sim}" != "?" && "${runtime}" != "" ]]; then
      pct=$(awk -v s="${sim}" -v r="${runtime}" 'BEGIN { if (r>0) printf "%.1f", 100*s/r; else print "?" }')
    else
      pct="?"
    fi
    disk_h="$(du -sh "${run_dir}" 2>/dev/null | awk '{print $1}')"
    local delta=$(( now_bytes - last_bytes ))
    log_msg "  progress  sim=${sim}/${runtime}s (${pct}%)  disk=${disk_h} (+$(ayil_human_bytes "${delta}") since last)"
    last_bytes="${now_bytes}"
  done
}

run_one_date() {
  local DATE="$1"
  local RUN_DIR="${AYIL_RUNS}/${DATE}"
  ayil_ensure_run_logs "${RUN_DIR}"
  local LOG PROGRESS_LOG
  LOG="$(ayil_dales_log "${RUN_DIR}")"
  PROGRESS_LOG="$(ayil_progress_log "${RUN_DIR}")"

  local state
  state="$(ayil_run_state "${RUN_DIR}")"

  if [[ "${MODE}" == "status" ]]; then
    log_msg "${DATE}: ${state}  $( [[ -d "${RUN_DIR}" ]] && du -sh "${RUN_DIR}" | awk '{print $1}' || echo '-' )"
    return 0
  fi

  if [[ "${state}" == "complete" && "${FORCE}" -eq 0 ]]; then
    log_msg "SKIP ${DATE} (already complete — use --force to re-run)"
    return 10
  fi

  if [[ "${state}" == "running" && "${FORCE}" -eq 0 ]]; then
    log_msg "SKIP ${DATE} (marked running; if stale, remove ${RUN_DIR}/${AYIL_STATUS_RUNNING})"
    return 10
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_msg "DRY-RUN would run ${DATE} nproc=${NPROC} -> ${RUN_DIR}"
    return 0
  fi

  "${SCRIPT_DIR}/prepare_case.sh" "${DATE}" "${RUN_DIR}"

  if [[ "${PREPARE_ONLY}" -eq 1 ]]; then
    log_msg "Prepared ${DATE} only"
    return 0
  fi

  if ayil_should_clean_run_outputs "${RUN_DIR}" "${FORCE}" 0 0; then
    ayil_clean_outputs "${RUN_DIR}"
  fi

  local runtime
  runtime="$(ayil_read_runtime "${RUN_DIR}/namoptions")"

  log_msg "START ${DATE}  nproc=${NPROC}  runtime=${runtime}s  dir=${RUN_DIR}"
  log_msg "  estimate: $("${SCRIPT_DIR}/estimate_output_gb.sh" "${NPROC}" | tail -3 | sed 's/^/    /')"

  ayil_mark_running "${RUN_DIR}" "${DATE}" "${NPROC}"
  : > "${PROGRESS_LOG}"

  local MPI_PID MON_PID
  trap 'handle_interrupt' INT TERM

  handle_interrupt() {
    log_msg "Interrupt received — stopping MPI for ${DATE}"
    if [[ -n "${MPI_PID:-}" ]]; then
      kill -TERM "${MPI_PID}" 2>/dev/null || true
      wait "${MPI_PID}" 2>/dev/null || true
    fi
    if [[ -n "${MON_PID:-}" ]]; then
      kill -TERM "${MON_PID}" 2>/dev/null || true
    fi
    ayil_mark_interrupted "${RUN_DIR}" "${LOG}"
    log_msg "Marked interrupted. Re-run without --force to continue later (may need --force to restart cold)."
    trap - INT TERM
    exit 130
  }

  (
    cd "${RUN_DIR}"
    # shellcheck disable=SC2086
    "${MPIRUN}" ${AYIL_MPIRUN_EXTRA:-} -np "${NPROC}" "${DALES_BIN}" namoptions
  ) >>"${LOG}" 2>&1 &
  MPI_PID=$!

  (
    monitor_run "${RUN_DIR}" "${LOG}" "${runtime}"
  ) >>"${PROGRESS_LOG}" 2>&1 &
  MON_PID=$!

  local exit_code=0
  wait "${MPI_PID}" || exit_code=$?
  kill "${MON_PID}" 2>/dev/null || true
  wait "${MON_PID}" 2>/dev/null || true
  trap - INT TERM

  if [[ ${exit_code} -eq 0 ]] && ayil_sim_complete "${LOG}" "${RUN_DIR}/namoptions"; then
    ayil_mark_complete "${RUN_DIR}" "${LOG}" "${NPROC}"
    log_msg "DONE ${DATE}  $(du -sh "${RUN_DIR}" | awk '{print $1}')  log=${LOG}"
  else
    ayil_mark_failed "${RUN_DIR}" "${exit_code}"
    log_msg "FAIL ${DATE}  exit=${exit_code}  sim=$(ayil_last_sim_time "${LOG}" 2>/dev/null || echo ?)"
    log_msg "  See ${LOG}"
    return 1
  fi
}

ran=0
skipped=0
failed=0
for DATE in "${DATES[@]}"; do
  if [[ "${LIMIT}" -gt 0 && "${ran}" -ge "${LIMIT}" ]]; then
    log_msg "Reached --limit ${LIMIT}"
    break
  fi
  set +e
  run_one_date "${DATE}"
  rc=$?
  set -e
  case "${rc}" in
    0) (( ran++ )) || true ;;
    10) (( skipped++ )) || true ;;
    *)
      (( failed++ )) || true
      if [[ "${MODE}" != "status" ]]; then
        log_msg "Stopping after failure (fix and re-run; completed days are untouched)"
        break
      fi
      ;;
  esac
done

log_msg "Summary: ran=${ran} skipped=${skipped} failed=${failed}"
[[ "${failed}" -eq 0 ]]
