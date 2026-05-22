#!/usr/bin/env bash
# End-to-end chunk pipeline via mock mpirun + mock_dales4 (no real LES).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"

MOCK_MPI="${REPO_ROOT}/test/fixtures/bin/mock_mpirun"
MOCK_DALES="${REPO_ROOT}/test/fixtures/bin/mock_dales4"
chmod +x "${MOCK_MPI}" "${MOCK_DALES}" 2>/dev/null || true

INPUT_DATE="20200720"
if [[ ! -d "${REPO_ROOT}/ayil_config_input_results/${INPUT_DATE}" ]]; then
  test_skip "ayil_config_input_results/${INPUT_DATE} not present"
fi

TEST_RUNS="${REPO_ROOT}/test/tmp_runs"
rm -rf "${TEST_RUNS}"
mkdir -p "${TEST_RUNS}"

export MOSAiC_AYIL_ROOT="${REPO_ROOT}"
export AYIL_RUNS="${TEST_RUNS}"
export AYIL_SKIP_MPI_AUTO=1
export DALES_NPROC=4
export MPIRUN="${MOCK_MPI}"
export DALES_BIN="${MOCK_DALES}"
export AYIL_USE_RESTART_CHUNKS=1
export AYIL_DAY_RUNTIME_SEC=120
export AYIL_CHUNK_SIM_SEC=60
export AYIL_N_CHUNKS=2
export AYIL_FORCE=1

RUN_DIR="${TEST_RUNS}/${INPUT_DATE}"
SCRIPTS="${REPO_ROOT}/scripts"

"${SCRIPTS}/prepare_case.sh" "${INPUT_DATE}" "${RUN_DIR}"

AYIL_CHUNK_INDEX=0 "${SCRIPTS}/run_slurm_day.sh" "${INPUT_DATE}" || test_fail "chunk 0 run_slurm_day"
[[ -f "${RUN_DIR}/.ayil_chunk_0_complete" ]] || test_fail "chunk 0 marker missing"

# shellcheck source=../../scripts/lib/restart_naming.sh
source "${REPO_ROOT}/scripts/lib/restart_naming.sh"
while read -r cid; do
  lat="$(ayil_dales_latest_initd_name 60 "${cid}" '001')"
  [[ -f "${RUN_DIR}/${lat}" ]] || test_fail "chunk 0 missing ${lat}"
done < <(ayil_dales_cmyids_for_nproc 4)

LOG="${RUN_DIR}/logs/dales.log"
grep -q 'Time of Simulation:' "${LOG}" || test_fail "chunk 0 log missing sim time"

AYIL_CHUNK_INDEX=1 "${SCRIPTS}/run_slurm_day.sh" "${INPUT_DATE}" || test_fail "chunk 1 warm run_slurm_day"
grep -q 'Cannot open file' "${LOG}" && test_fail "chunk 1 log has missing restart open"

[[ -f "${RUN_DIR}/.ayil_complete" ]] || test_fail "day not marked complete after final chunk"
if compgen -G "${RUN_DIR}/initdlatest*.001" >/dev/null; then
  test_fail "final chunk should prune all initd restart files"
fi

rm -rf "${TEST_RUNS}"
test_pass
