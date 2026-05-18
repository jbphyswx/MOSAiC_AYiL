#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"
# shellcheck source=../../scripts/lib/mpi_slots.sh
source "${REPO_ROOT}/scripts/lib/mpi_slots.sh"

export MPIRUN="${REPO_ROOT}/test/fixtures/bin/mock_mpirun"
chmod +x "${MPIRUN}"
export MOCK_MPI_MAX_SLOTS=32
unset AYIL_MAX_SLOTS

assert_eq "$(ayil_largest_grid_factor_le 100)" "80" "factor le 100"
assert_eq "$(ayil_largest_grid_factor_le 48)" "40" "factor le 48 (not 48 itself)"
assert_eq "$(ayil_largest_grid_factor_le 33)" "32" "factor le 33"

assert_eq "$(ayil_mpi_probe_max_slots)" "32" "mock probe max 32"

export MOCK_MPI_MAX_SLOTS=48
assert_eq "$(ayil_mpi_probe_max_slots)" "40" "mock max 48 -> dales factor 40"

export AYIL_MPI_MAX_SLOTS=16
assert_eq "$(ayil_resolve_nproc 64)" "16" "resolve with cap 16"
unset AYIL_MPI_MAX_SLOTS

export MOCK_MPI_MAX_SLOTS=80
assert_eq "$(ayil_resolve_nproc 64)" "64" "resolve 64 when slots allow"
assert_eq "$(ayil_resolve_nproc 100)" "80" "resolve clamp 100 -> 80"

# 96 is not a factor of 320 — must never be returned
resolved=$(ayil_resolve_nproc 96)
if [[ "${resolved}" == "96" ]]; then
  test_fail "resolve must not return 96 (not a factor of 320)"
else
  test_pass
fi
