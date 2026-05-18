#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"
# shellcheck source=../../scripts/lib/mpi_env.sh
source "${REPO_ROOT}/scripts/lib/mpi_env.sh"

MOCK_BIN="${REPO_ROOT}/test/fixtures/bin"
chmod +x "${MOCK_BIN}/mock_mpirun"

# Explicit MPIRUN wins
export MPIRUN="${MOCK_BIN}/mock_mpirun"
unset OPENMPI_PREFIX
ayil_setup_mpi_env
assert_eq "${MPIRUN}" "${MOCK_BIN}/mock_mpirun" "respect MPIRUN env"

# OPENMPI_PREFIX
unset MPIRUN
export OPENMPI_PREFIX="${MOCK_BIN}"
# mock is named mock_mpirun not mpirun — use PATH fallback test
export PATH="${MOCK_BIN}:${PATH}"
# Create symlink mpirun -> mock_mpirun for prefix test
ln -sf mock_mpirun "${MOCK_BIN}/mpirun"
ayil_setup_mpi_env
assert_true "[[ -n \"${MPIRUN:-}\" ]]" "finds mpirun via OPENMPI_PREFIX or PATH"
rm -f "${MOCK_BIN}/mpirun"
