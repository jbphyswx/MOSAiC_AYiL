#!/usr/bin/env bash
# Build the AYiL DALES executable (dales4) with CMake.
#
# Usage: ./scripts/build_dales.sh
#
# Creates: ${DALES_BIN}  (default: MOSAiC_AYiL/build/src/dales4)
# Prereqs:  ./scripts/check_prerequisites.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

"${SCRIPT_DIR}/bootstrap_build_tree.sh"

cd "${DALES_SRC}"

if ! command -v mpif90 >/dev/null 2>&1; then
  echo "ERROR: mpif90 not found. Load your MPI module or set OPENMPI_PREFIX in scripts/env.local" >&2
  echo "  Run: ./scripts/diagnose_mpi.sh" >&2
  exit 1
fi
if ! command -v cmake >/dev/null 2>&1; then
  echo "ERROR: cmake not found." >&2
  exit 1
fi

mkdir -p build
cd build

# gfortran 11+ needs -fallow-argument-mismatch (legacy FFT in fftnew.f90)
CMAKE_FLAGS=(
  -DCMAKE_Fortran_FLAGS="-finit-real=nan -fdefault-real-8 -ffree-line-length-none -fallow-argument-mismatch"
)

echo "cmake .. ${CMAKE_FLAGS[*]}"
cmake .. "${CMAKE_FLAGS[@]}"

echo "make -j$(nproc)"
make -j"$(nproc)"

if [[ ! -x "${DALES_BIN}" ]]; then
  echo "ERROR: expected executable at ${DALES_BIN}" >&2
  exit 1
fi

echo "Built: ${DALES_BIN}"
