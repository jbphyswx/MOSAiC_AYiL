#!/usr/bin/env bash
# Short MPI run to verify dales4 starts and reads namoptions + scm_in.nc.
# Does NOT run to completion (uses timeout). For full production runs use run_case.sh.
#
# Usage: smoke_test.sh [YYYYMMDD] [NPROC] [TIMEOUT_SEC]
#
# Defaults: 20200720, 16 ranks, 120 s wall clock.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/logging_paths.sh
source "${SCRIPT_DIR}/lib/logging_paths.sh"

DATE="${1:-20200720}"
NPROC="${2:-16}"
TIMEOUT_SEC="${3:-120}"
RUN_DIR="${AYIL_RUNS}/smoke_${DATE}"

if [[ ! -x "${DALES_BIN}" ]]; then
  echo "ERROR: ${DALES_BIN} not found. Run: ${SCRIPT_DIR}/build_dales.sh" >&2
  exit 1
fi

"${SCRIPT_DIR}/prepare_case.sh" "${DATE}" "${RUN_DIR}"

ayil_ensure_run_logs "${RUN_DIR}"
LOG="$(ayil_smoke_log "${RUN_DIR}")"
cd "${RUN_DIR}"

echo "Smoke test: date=${DATE} nproc=${NPROC} timeout=${TIMEOUT_SEC}s"
echo "Run dir: ${RUN_DIR}"
echo "Log: ${LOG}"

set +e
timeout "${TIMEOUT_SEC}" "${MPIRUN}" -np "${NPROC}" "${DALES_BIN}" namoptions >"${LOG}" 2>&1
status=$?
set -e

if [[ ${status} -eq 124 ]]; then
  echo "PASS (timeout reached; model was still running)"
elif [[ ${status} -eq 0 ]]; then
  echo "PASS (exited before timeout)"
else
  echo "FAIL (mpirun exit ${status}). Tail of log:" >&2
  tail -40 "${LOG}" >&2
  exit 1
fi

if grep -q "Time of Simulation" "${LOG}"; then
  echo "PASS (log contains time-step output)"
else
  echo "FAIL (no time-step lines in log)" >&2
  tail -40 "${LOG}" >&2
  exit 1
fi

echo "Smoke test finished. Inspect ${LOG} and any *.nc written under ${RUN_DIR}."
