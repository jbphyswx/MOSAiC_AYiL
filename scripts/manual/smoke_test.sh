#!/usr/bin/env bash
# MANUAL ONLY: real dales4 MPI smoke (not ./test/run_tests.sh).
# Usage: smoke_test.sh [YYYYMMDD] [NPROC] [TIMEOUT_SEC]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../config.sh
source "${ROOT}/config.sh"
# shellcheck source=../lib/logging_paths.sh
source "${ROOT}/lib/logging_paths.sh"
# shellcheck source=../lib/namoptions_patch.sh
source "${ROOT}/lib/namoptions_patch.sh"
# shellcheck source=../lib/test_mpi_guard.sh
source "${ROOT}/lib/test_mpi_guard.sh"

ayil_refuse_login_mpi_tests "manual/smoke_test.sh" || exit 1

DATE="${1:-20200720}"
NPROC="${2:-4}"
TIMEOUT_SEC="${3:-120}"
SMOKE_RUNTIME_SEC="${AYiL_SMOKE_RUNTIME_SEC:-30}"
RUN_DIR="${AYiL_RUNS}/smoke_${DATE}"

if [[ ! -x "${DALES_BIN}" ]]; then
  echo "ERROR: ${DALES_BIN} not found. Run: ${ROOT}/build_dales.sh" >&2
  exit 1
fi

"${ROOT}/prepare_case.sh" "${DATE}" "${RUN_DIR}"
ayil_set_runtime "${RUN_DIR}/namoptions" "${SMOKE_RUNTIME_SEC}"
ayil_disable_restart_writes "${RUN_DIR}/namoptions"

ayil_ensure_run_logs "${RUN_DIR}"
LOG="$(ayil_smoke_log "${RUN_DIR}")"
cd "${RUN_DIR}"

echo "MANUAL smoke: date=${DATE} nproc=${NPROC} timeout=${TIMEOUT_SEC}s sim_runtime=${SMOKE_RUNTIME_SEC}s"
echo "Run dir: ${RUN_DIR}"

set +e
timeout "${TIMEOUT_SEC}" "${MPIRUN}" -np "${NPROC}" "${DALES_BIN}" namoptions >"${LOG}" 2>&1
status=$?
set -e

if [[ ${status} -eq 124 ]]; then
  echo "PASS (wall timeout; model still running)"
elif [[ ${status} -eq 137 ]]; then
  echo "FAIL (killed — need more memory / compute node)" >&2
  exit 1
elif [[ ${status} -eq 0 ]]; then
  echo "PASS (exited)"
else
  echo "FAIL (exit ${status})" >&2
  tail -40 "${LOG}" >&2
  exit 1
fi

grep -q "Time of Simulation" "${LOG}" || {
  echo "FAIL (no sim time in log)" >&2
  exit 1
}
echo "PASS (log has Time of Simulation)"
