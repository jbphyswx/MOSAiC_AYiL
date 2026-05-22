#!/usr/bin/env bash
# Two-chunk MPI smoke: chunk 0 writes initdlatest*; chunk 1 warm-starts without "Cannot open file".
# Requires built dales4. Not run in default ./test/run_tests.sh (use --with-dales).
#
# Usage: chunk_warmstart_smoke_test.sh [YYYYMMDD] [NPROC] [CHUNK_SEC]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/chunk_run.sh
source "${SCRIPT_DIR}/lib/chunk_run.sh"
# shellcheck source=lib/namoptions_patch.sh
source "${SCRIPT_DIR}/lib/namoptions_patch.sh"
# shellcheck source=lib/restart_naming.sh
source "${SCRIPT_DIR}/lib/restart_naming.sh"
# shellcheck source=lib/logging_paths.sh
source "${SCRIPT_DIR}/lib/logging_paths.sh"

DATE="${1:-20200720}"
NPROC="${2:-8}"
CHUNK_SEC="${3:-120}"
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
"${SCRIPT_DIR}/prepare_case.sh" "${DATE}" "${RUN_DIR}"
ayil_ensure_run_logs "${RUN_DIR}"
LOG="$(ayil_dales_log "${RUN_DIR}")"
cd "${RUN_DIR}"

echo "Chunk smoke: date=${DATE} nproc=${NPROC} chunks=${N_CHUNKS} chunk_sec=${CHUNK_SEC} day_sec=${DAY_SEC}"

ayil_apply_chunk_namoptions "${RUN_DIR}/namoptions" 0 "${N_CHUNKS}"
set +e
timeout "${TIMEOUT_SEC}" "${MPIRUN}" -np "${NPROC}" "${DALES_BIN}" namoptions >>"${LOG}" 2>&1
c0=$?
set -e
if [[ ${c0} -ne 0 && ${c0} -ne 124 ]]; then
  echo "FAIL chunk 0 exit=${c0}" >&2
  tail -30 "${LOG}" >&2
  exit 1
fi
if ! grep -q "dump at time" "${LOG}"; then
  echo "FAIL chunk 0: no restart dump in log" >&2
  exit 1
fi

found=0
while read -r cid; do
  lat="$(ayil_dales_latest_initd_name "${CHUNK_SEC}" "${cid}" '001')"
  if [[ -f "${RUN_DIR}/${lat}" ]]; then
    found=1
  fi
done < <(ayil_dales_cmyids_for_nproc "${NPROC}")
if (( found == 0 )); then
  echo "FAIL chunk 0: no initdlatest*.001 for any rank" >&2
  ls -1 initd*.001 2>/dev/null | head -20 >&2 || true
  exit 1
fi

ayil_prune_timed_restart_files "${RUN_DIR}"
ayil_apply_chunk_namoptions "${RUN_DIR}/namoptions" 1 "${N_CHUNKS}"
: >>"${LOG}"
set +e
timeout "${TIMEOUT_SEC}" "${MPIRUN}" -np "${NPROC}" "${DALES_BIN}" namoptions >>"${LOG}" 2>&1
c1=$?
set -e

if grep -q "Cannot open file 'initdlatest" "${LOG}"; then
  echo "FAIL chunk 1: Fortran cannot open warm-start restart" >&2
  grep "Cannot open file" "${LOG}" | tail -5 >&2
  exit 1
fi
if [[ ${c1} -ne 0 && ${c1} -ne 124 ]]; then
  echo "FAIL chunk 1 exit=${c1}" >&2
  tail -30 "${LOG}" >&2
  exit 1
fi
if ! grep -q "Time of Simulation" "${LOG}"; then
  echo "FAIL chunk 1: no time-step output after warm start" >&2
  exit 1
fi

echo "PASS chunk warm-start smoke (${RUN_DIR})"
