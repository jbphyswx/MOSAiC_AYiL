#!/usr/bin/env bash
# Verify tools and libraries needed to build and run DALES.
# Exit 0 if all required items are found; exit 1 otherwise.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# config.sh loads mpi_slots via mpi_env

fail=0

check_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "OK  $name -> $(command -v "$name")"
  else
    echo "MISSING  $name" >&2
    fail=1
  fi
}

echo "=== Commands ==="
check_cmd cmake
check_cmd make
check_cmd mpif90
check_cmd mpirun
check_cmd rsync

echo ""
echo "=== Optional (recommended) ==="
if command -v ncdump >/dev/null 2>&1; then
  echo "OK  ncdump"
else
  echo "SKIP ncdump (optional; install netcdf tools to inspect .nc files)"
fi

echo ""
echo "=== NetCDF Fortran ==="
if [[ -f /lib64/libnetcdff.so ]] || [[ -f /usr/lib64/libnetcdff.so.7 ]]; then
  echo "OK  libnetcdff found under /lib64 or /usr/lib64"
else
  echo "WARN libnetcdff not found in default paths; build may still work if modules are loaded." >&2
fi

if "${DALES_SRC}/findnetcdf" >/dev/null 2>&1; then
  echo "OK  findnetcdf -> $("${DALES_SRC}/findnetcdf")"
else
  echo "MISSING  findnetcdf script in ${DALES_SRC}" >&2
  fail=1
fi

echo ""
echo "=== Repository layout ==="
for path in "${DALES_SRC}/src/program.f90" "${AYIL_INPUTS}"; do
  if [[ -e "${path}" ]]; then
    echo "OK  ${path}"
  else
    echo "MISSING  ${path}" >&2
    fail=1
  fi
done

if [[ -d "${AYIL_INPUTS}/20200720" ]]; then
  echo "OK  sample case ${AYIL_INPUTS}/20200720"
else
  echo "WARN sample case 20200720 not found (unzip Zenodo ayil_config_input_results.zip)" >&2
fi

echo ""
echo "=== MPI / ranks (this host) ==="
if [[ -n "${MPIRUN:-}" ]]; then
  echo "OK  MPIRUN=${MPIRUN}"
  max="$(ayil_mpi_probe_max_slots)"
  resolved="$(ayil_resolve_nproc 64)"
  echo "OK  max mpirun slots (probed)=${max}"
  echo "OK  recommended DALES_NPROC=${resolved}  (largest factor of 320 that fits)"
  if [[ "${DALES_NPROC}" != "${resolved}" ]]; then
    echo "NOTE DALES_NPROC=${DALES_NPROC} (override in env.local)"
  fi
else
  echo "MISSING Open MPI (mpirun). Run ./scripts/diagnose_mpi.sh after fixing PATH." >&2
  fail=1
fi

echo ""
if (( fail == 0 )); then
  echo "All required prerequisites satisfied."
else
  echo "Fix missing prerequisites, then re-run." >&2
  exit 1
fi
