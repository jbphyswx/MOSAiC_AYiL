#!/usr/bin/env bash
# MANUAL ONLY: two-chunk real dales4 warm-start check (not ./test/run_tests.sh).
# Usage: chunk_warmstart_smoke_test.sh [YYYYMMDD] [NPROC] [CHUNK_SEC]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../config.sh
source "${ROOT}/config.sh"
# shellcheck source=../lib/chunk_run.sh
source "${ROOT}/lib/chunk_run.sh"
# shellcheck source=../lib/namoptions_patch.sh
source "${ROOT}/lib/namoptions_patch.sh"
# shellcheck source=../lib/restart_naming.sh
source "${ROOT}/lib/restart_naming.sh"
# shellcheck source=../lib/logging_paths.sh
source "${ROOT}/lib/logging_paths.sh"
# shellcheck source=../lib/test_mpi_guard.sh
source "${ROOT}/lib/test_mpi_guard.sh"

ayil_refuse_login_mpi_tests "manual/chunk_warmstart_smoke_test.sh" || exit 1

DATE="${1:-20200720}"
NPROC="${2:-4}"
CHUNK_SEC="${3:-60}"
DAY_SEC=240
export AYIL_DAY_RUNTIME_SEC="${DAY_SEC}"
export AYIL_CHUNK_SIM_SEC="${CHUNK_SEC}"
N_CHUNKS="$(ayil_n_chunks)"
RUN_DIR="${AYIL_RUNS}/chunk_smoke_${DATE}"
TIMEOUT_SEC=600

if [[ ! -x "${DALES_BIN}" ]]; then
  echo "ERROR: ${DALES_BIN} not found" >&2
  exit 1
fi

rm -rf "${RUN_DIR}"
"${ROOT}/prepare_case.sh" "${DATE}" "${RUN_DIR}"
ayil_ensure_run_logs "${RUN_DIR}"
LOG="$(ayil_dales_log "${RUN_DIR}")"
cd "${RUN_DIR}"

echo "MANUAL chunk smoke: nproc=${NPROC} chunks=${N_CHUNKS} chunk_sec=${CHUNK_SEC}"

ayil_apply_chunk_namoptions "${RUN_DIR}/namoptions" 0 "${N_CHUNKS}"
set +e
timeout "${TIMEOUT_SEC}" "${MPIRUN}" -np "${NPROC}" "${DALES_BIN}" namoptions >>"${LOG}" 2>&1
c0=$?
set -e
if [[ ${c0} -ne 0 && ${c0} -ne 124 ]]; then
  echo "FAIL chunk 0 exit=${c0}" >&2
  exit 1
fi
grep -q "dump at time" "${LOG}" || {
  echo "FAIL chunk 0: no restart dump" >&2
  exit 1
}

ayil_prune_timed_restart_files "${RUN_DIR}"
ayil_apply_chunk_namoptions "${RUN_DIR}/namoptions" 1 "${N_CHUNKS}"
set +e
timeout "${TIMEOUT_SEC}" "${MPIRUN}" -np "${NPROC}" "${DALES_BIN}" namoptions >>"${LOG}" 2>&1
c1=$?
set -e

grep -q "Cannot open file 'initdlatest" "${LOG}" && {
  echo "FAIL chunk 1: cannot open restart" >&2
  exit 1
}
[[ ${c1} -ne 0 && ${c1} -ne 124 ]] && {
  echo "FAIL chunk 1 exit=${c1}" >&2
  exit 1
}
grep -q "Time of Simulation" "${LOG}" || {
  echo "FAIL chunk 1: no sim output" >&2
  exit 1
}
echo "PASS manual chunk warm-start (${RUN_DIR})"
