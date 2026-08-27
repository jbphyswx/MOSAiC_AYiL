#!/usr/bin/env bash
# Run all MOSAiC_AYiL pipeline tests (unit + integration). Always lightweight:
# mock MPI + mock_dales4; never launches a real 320×320 LES.
#
# Usage:
#   ./test/run_tests.sh
#
# Full LES sanity checks are manual only (scripts/manual/), not part of this suite.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck source=test/lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"

export AYiL_SKIP_MPI_AUTO=1
export MPIRUN="${REPO_ROOT}/test/fixtures/bin/mock_mpirun"
export DALES_BIN="${REPO_ROOT}/test/fixtures/bin/mock_dales4"
case "${DALES_BIN}" in
  */test/fixtures/bin/mock_dales4) ;;
  *)
    echo "ERROR: test suite must use mock_dales4 (got DALES_BIN=${DALES_BIN})" >&2
    exit 1
    ;;
esac
chmod +x "${MPIRUN}" "${DALES_BIN}" 2>/dev/null || true

for f in "${REPO_ROOT}"/test/unit/test_*.sh; do
  run_test_file "${f}"
done

for f in "${REPO_ROOT}"/test/integration/test_*.sh; do
  run_test_file "${f}"
done

test_summary
