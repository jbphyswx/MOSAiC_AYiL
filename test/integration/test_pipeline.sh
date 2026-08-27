#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"

export AYiL_SKIP_MPI_AUTO=1
export DALES_NPROC=4
export MOSAiC_AYiL_ROOT="${REPO_ROOT}"
export MPIRUN="${REPO_ROOT}/test/fixtures/bin/mock_mpirun"
chmod +x "${MPIRUN}"
export MOCK_MPI_MAX_SLOTS=16

SCRIPTS="${REPO_ROOT}/scripts"
TEST_RUNS="${REPO_ROOT}/test/tmp_runs"
rm -rf "${TEST_RUNS}"
mkdir -p "${TEST_RUNS}"
export AYiL_RUNS="${TEST_RUNS}"

# --- bootstrap ---
assert_true "${SCRIPTS}/bootstrap_build_tree.sh" "bootstrap_build_tree"
assert_file_exists "${REPO_ROOT}/MOSAiC_AYiL/CMakeLists.txt"

# --- prepare (use real ayil input if present) ---
INPUT_DATE="20200720"
if [[ -d "${REPO_ROOT}/ayil_config_input_results/${INPUT_DATE}" ]]; then
  RUN_DIR="${TEST_RUNS}/${INPUT_DATE}"
  "${SCRIPTS}/prepare_case.sh" "${INPUT_DATE}" "${RUN_DIR}"
  assert_file_exists "${RUN_DIR}/namoptions"
  assert_true "[[ -L \"${RUN_DIR}/scm_in.nc\" || -f \"${RUN_DIR}/scm_in.nc\" ]]" "scm_in link"
else
  test_skip "ayil_config_input_results/${INPUT_DATE} not present"
fi

# --- run_local dry-run ---
out=$("${SCRIPTS}/run_local.sh" --dry-run "${INPUT_DATE}" 2>&1) || true
if echo "${out}" | grep -qE 'DRY-RUN|SKIP'; then
  test_pass
else
  test_fail "run_local dry-run: ${out}"
fi

# --- list_cases ---
"${SCRIPTS}/list_cases.sh" "${INPUT_DATE}" >/dev/null 2>&1 && test_pass || test_fail "list_cases"

# --- estimate (no crash) ---
"${SCRIPTS}/estimate_output_gb.sh" 4 >/dev/null 2>&1 && test_pass || test_fail "estimate_output_gb"

# --- skip complete ---
if [[ -n "${RUN_DIR:-}" && -d "${RUN_DIR}" ]]; then
  # shellcheck source=../../scripts/lib/run_status.sh
  source "${REPO_ROOT}/scripts/lib/run_status.sh"
  touch "${RUN_DIR}/${AYiL_STATUS_COMPLETE}"
  out=$("${SCRIPTS}/run_local.sh" --dry-run "${INPUT_DATE}" 2>&1) || true
  echo "${out}" | grep -q "SKIP" && test_pass || test_fail "skip complete day"
fi

rm -rf "${TEST_RUNS}"
