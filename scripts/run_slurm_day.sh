#!/usr/bin/env bash
# Run one MOSAiC day on a batch node (Slurm or manual). Uses status markers like run_local.sh.
#
# Usage: run_slurm_day.sh YYYYMMDD
#
# Environment:
#   AYiL_FORCE=1              Re-run .ayil_complete days; wipe outputs on chunk 0 only
#   AYiL_USE_RESTART_CHUNKS=1 Slurm chunk chain (requires AYiL_CHUNK_INDEX, AYiL_N_CHUNKS)
#   AYiL_CHUNK_INDEX          Chunk index 0..N-1 (default 0 when chunk mode on)
#   AYiL_N_CHUNKS             Number of chunks per day (default from AYiL_DAY_RUNTIME_SEC / CHUNK)
#   DALES_NPROC               MPI ranks (default: SLURM_NTASKS or config DALES_NPROC)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/run_status.sh
source "${SCRIPT_DIR}/lib/run_status.sh"
# shellcheck source=lib/pending_dates.sh
source "${SCRIPT_DIR}/lib/pending_dates.sh"
# shellcheck source=lib/logging_paths.sh
source "${SCRIPT_DIR}/lib/logging_paths.sh"
# shellcheck source=lib/progress_monitor.sh
source "${SCRIPT_DIR}/lib/progress_monitor.sh"
# shellcheck source=lib/chunk_run.sh
source "${SCRIPT_DIR}/lib/chunk_run.sh"
# shellcheck source=lib/namoptions_patch.sh
source "${SCRIPT_DIR}/lib/namoptions_patch.sh"
# shellcheck source=lib/slurm_defaults.sh
source "${SCRIPT_DIR}/lib/slurm_defaults.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 YYYYMMDD" >&2
  exit 1
fi

DATE="$1"
RUN_DIR="${AYiL_RUNS}/${DATE}"
ayil_ensure_run_logs "${RUN_DIR}"
LOG="$(ayil_dales_log "${RUN_DIR}")"
PROGRESS_LOG="$(ayil_progress_log "${RUN_DIR}")"
FORCE="${AYiL_FORCE:-0}"
NPROC="${DALES_NPROC:-${SLURM_NTASKS:-64}}"
CHUNK_MODE="${AYiL_USE_RESTART_CHUNKS:-0}"
CHUNK_IDX="${AYiL_CHUNK_INDEX:-0}"
N_CHUNKS="${AYiL_N_CHUNKS:-}"

if [[ "${CHUNK_MODE}" == "1" ]]; then
  if [[ -z "${N_CHUNKS}" ]]; then
    N_CHUNKS="$(ayil_n_chunks)"
  fi
  if ! [[ "${CHUNK_IDX}" =~ ^[0-9]+$ ]] || (( CHUNK_IDX < 0 || CHUNK_IDX >= N_CHUNKS )); then
    echo "ERROR: AYiL_CHUNK_INDEX=${CHUNK_IDX} invalid for N_CHUNKS=${N_CHUNKS}" >&2
    exit 1
  fi
fi

if [[ "${CHUNK_MODE}" != "1" ]] && ! ayil_should_submit_date "${RUN_DIR}" "${FORCE}"; then
  state="$(ayil_run_state "${RUN_DIR}")"
  echo "SKIP ${DATE} (state=${state}; set AYiL_FORCE=1 to re-run)"
  exit 0
fi

if [[ "${CHUNK_MODE}" == "1" ]] && ayil_chunk_is_complete "${RUN_DIR}" "${CHUNK_IDX}" && (( FORCE != 1 )); then
  echo "SKIP ${DATE} chunk=${CHUNK_IDX} (already complete)"
  exit 0
fi

if [[ "${CHUNK_MODE}" == "1" ]] && [[ -f "${RUN_DIR}/${AYiL_STATUS_COMPLETE}" ]] && (( FORCE != 1 )); then
  echo "SKIP ${DATE} (day complete)"
  exit 0
fi

if [[ ! -x "${DALES_BIN}" ]]; then
  echo "ERROR: ${DALES_BIN} not found. Build on the login node: ./scripts/build_dales.sh" >&2
  exit 1
fi

valid_factors=(1 2 4 5 8 10 16 20 32 40 64 80 160 320)
ok=0
for f in "${valid_factors[@]}"; do
  if (( NPROC == f )); then ok=1; break; fi
done
if (( ok == 0 )); then
  echo "WARNING: NPROC=${NPROC} is not a usual factor of 320; DALES may abort in initmpi." >&2
fi

export AYiL_USE_RESTART_CHUNKS="${CHUNK_MODE}"
# Output wipe runs in run_day.slurm before slurm.out tee (not here — cleaning here deleted logs mid-job).
"${SCRIPT_DIR}/prepare_case.sh" "${DATE}" "${RUN_DIR}"

NAMOPTIONS="${RUN_DIR}/namoptions"
if [[ "${CHUNK_MODE}" == "1" ]]; then
  ayil_apply_chunk_namoptions "${NAMOPTIONS}" "${CHUNK_IDX}" "${N_CHUNKS}"
fi

runtime="$(ayil_read_runtime "${NAMOPTIONS}")"
progress_target="${runtime}"
if [[ "${CHUNK_MODE}" == "1" ]]; then
  chunk_seg="${AYiL_CHUNK_SIM_SEC}"
  echo "START ${DATE}  chunk=${CHUNK_IDX}/${N_CHUNKS}  nproc=${NPROC}  target=${runtime}s (seg=${chunk_seg}s)  dir=${RUN_DIR}"
else
  echo "START ${DATE}  nproc=${NPROC}  runtime=${runtime}s  dir=${RUN_DIR}"
fi
echo "  dales.log=${LOG}  progress.log=${PROGRESS_LOG}"
if [[ -n "${SLURM_TIMELIMIT:-}" ]]; then
  echo "  SLURM_TIMELIMIT=${SLURM_TIMELIMIT}  SLURM_JOB_ID=${SLURM_JOB_ID:-?}"
fi

ayil_mark_running "${RUN_DIR}" "${DATE}" "${NPROC}" "${LOG}"
: >>"${PROGRESS_LOG}"

MON_PID=""
ayil_monitor_run "${RUN_DIR}" "${LOG}" "${progress_target}" >>"${PROGRESS_LOG}" 2>&1 &
MON_PID=$!

set +e
(
  cd "${RUN_DIR}"
  # shellcheck disable=SC2086
  "${MPIRUN}" ${AYiL_MPIRUN_EXTRA:-} -np "${NPROC}" "${DALES_BIN}" namoptions
) >>"${LOG}" 2>&1
exit_code=$?
set -e

if [[ -n "${MON_PID}" ]]; then
  kill "${MON_PID}" 2>/dev/null || true
  wait "${MON_PID}" 2>/dev/null || true
fi

if [[ ${exit_code} -eq 0 ]] && ayil_sim_complete "${LOG}" "${NAMOPTIONS}"; then
  if [[ "${CHUNK_MODE}" == "1" ]]; then
    ayil_mark_chunk_complete "${RUN_DIR}" "${CHUNK_IDX}" "${LOG}" "${NPROC}"
    if (( CHUNK_IDX < N_CHUNKS - 1 )); then
      ayil_prune_timed_restart_files "${RUN_DIR}"
      # Wall cal only from chunk 0 (cold start); warm chunks are not representative for sbatch --time.
      if (( CHUNK_IDX == 0 )); then
        ayil_slurm_record_wall_calibration "${RUN_DIR}" "${LOG}" "${NAMOPTIONS}"
      fi
      ayil_sim_dt_merge_log "${DATE}" "${LOG}" "${NPROC}"
      rm -f "${RUN_DIR}/${AYiL_STATUS_RUNNING}"
      echo "DONE ${DATE} chunk=${CHUNK_IDX}/${N_CHUNKS}  (restart kept for next chunk)"
      exit 0
    fi
    ayil_prune_all_restart_files "${RUN_DIR}"
    ayil_sim_dt_merge_log "${DATE}" "${LOG}" "${NPROC}"
    ayil_mark_complete "${RUN_DIR}" "${LOG}" "${NPROC}"
    echo "DONE ${DATE}  all ${N_CHUNKS} chunks  $(du -sh "${RUN_DIR}" | awk '{print $1}')"
    exit 0
  fi
  ayil_sim_dt_merge_log "${DATE}" "${LOG}" "${NPROC}"
  ayil_mark_complete "${RUN_DIR}" "${LOG}" "${NPROC}"
  echo "DONE ${DATE}  $(du -sh "${RUN_DIR}" | awk '{print $1}')"
  exit 0
fi

ayil_mark_failed "${RUN_DIR}" "${exit_code}"
if [[ "${CHUNK_MODE}" == "1" ]]; then
  echo "FAIL ${DATE} chunk=${CHUNK_IDX}  exit=${exit_code}  log=${LOG}" >&2
else
  echo "FAIL ${DATE}  exit=${exit_code}  log=${LOG}" >&2
fi
exit "${exit_code}"
