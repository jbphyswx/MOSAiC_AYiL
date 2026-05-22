#!/usr/bin/env bash
# Run all MOSAiC_AYIL pipeline tests (unit + integration).
#
# Usage:
#   ./test/run_tests.sh              # unit + integration (no DALES binary)
#   ./test/run_tests.sh --with-dales # include build/smoke if dales4 exists
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck source=test/lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"

WITH_DALES=0
for arg in "$@"; do
  case "${arg}" in
    --with-dales) WITH_DALES=1 ;;
    -h|--help)
      echo "Usage: $0 [--with-dales]"
      exit 0
      ;;
  esac
done

export AYIL_SKIP_MPI_AUTO=1

for f in "${REPO_ROOT}"/test/unit/test_*.sh; do
  run_test_file "${f}"
done

for f in "${REPO_ROOT}"/test/integration/test_*.sh; do
  run_test_file "${f}"
done

if (( WITH_DALES == 1 )); then
  echo ""
  echo "=== integration (DALES binary) ==="
  if [[ -x "${REPO_ROOT}/dales_ayil/build/src/dales4" ]]; then
  export AYIL_SKIP_MPI_AUTO=0
  unset DALES_NPROC
  # shellcheck source=../scripts/config.sh
  source "${REPO_ROOT}/scripts/config.sh"
  if "${REPO_ROOT}/scripts/smoke_test.sh" 20200720 "${DALES_NPROC:-4}" 60; then
    test_pass
  else
    test_fail "smoke_test.sh"
  fi
  if "${REPO_ROOT}/scripts/chunk_warmstart_smoke_test.sh" 20200720 8 120; then
    test_pass
  else
    test_fail "chunk_warmstart_smoke_test.sh"
  fi
  else
    test_skip "dales4 not built; run ./scripts/build_dales.sh first"
  fi
fi

test_summary
