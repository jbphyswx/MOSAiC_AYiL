#!/usr/bin/env bash
# Run one MOSAiC day on a batch node (Slurm or manual). Uses status markers like run_local.sh.
#
# Usage: run_slurm_day.sh YYYYMMDD
#
# Environment:
#   AYIL_FORCE=1     Re-run even if .ayil_complete exists (cleans outputs first)
#   DALES_NPROC      MPI ranks (default: SLURM_NTASKS or config DALES_NPROC)
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

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 YYYYMMDD" >&2
  exit 1
fi

DATE="$1"
RUN_DIR="${AYIL_RUNS}/${DATE}"
ayil_ensure_run_logs "${RUN_DIR}"
LOG="$(ayil_dales_log "${RUN_DIR}")"
FORCE="${AYIL_FORCE:-0}"
NPROC="${DALES_NPROC:-${SLURM_NTASKS:-40}}"

if ! ayil_should_submit_date "${RUN_DIR}" "${FORCE}"; then
  state="$(ayil_run_state "${RUN_DIR}")"
  echo "SKIP ${DATE} (state=${state}; set AYIL_FORCE=1 to re-run)"
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

"${SCRIPT_DIR}/prepare_case.sh" "${DATE}" "${RUN_DIR}"

if (( FORCE == 1 )); then
  ayil_clean_run_outputs "${RUN_DIR}"
fi

runtime="$(ayil_read_runtime "${RUN_DIR}/namoptions")"
echo "START ${DATE}  nproc=${NPROC}  runtime=${runtime}s  dir=${RUN_DIR}"

ayil_mark_running "${RUN_DIR}" "${DATE}" "${NPROC}"

set +e
(
  cd "${RUN_DIR}"
  # shellcheck disable=SC2086
  "${MPIRUN}" ${AYIL_MPIRUN_EXTRA:-} -np "${NPROC}" "${DALES_BIN}" namoptions
) >>"${LOG}" 2>&1
exit_code=$?
set -e

if [[ ${exit_code} -eq 0 ]] && ayil_sim_complete "${LOG}" "${RUN_DIR}/namoptions"; then
  ayil_mark_complete "${RUN_DIR}" "${LOG}" "${NPROC}"
  echo "DONE ${DATE}  $(du -sh "${RUN_DIR}" | awk '{print $1}')"
  exit 0
fi

ayil_mark_failed "${RUN_DIR}" "${exit_code}"
echo "FAIL ${DATE}  exit=${exit_code}  log=${LOG}" >&2
exit "${exit_code}"
