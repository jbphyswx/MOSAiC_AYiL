#!/usr/bin/env bash
# Report MPI paths, slot limits, and recommended DALES_NPROC for this host.
# Run from repo root: ./scripts/diagnose_mpi.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

echo "=== MPI binaries ==="
echo "MPIRUN=${MPIRUN:-MISSING}"
echo "MPIF90=${MPIF90:-MISSING}"
echo "PATH (openmpi)=$(dirname "${MPIRUN:-}")"

if [[ -z "${MPIRUN:-}" ]]; then
  echo "ERROR: Open MPI not found. Install openmpi-devel or set OPENMPI_PREFIX in scripts/env.local" >&2
  exit 1
fi

echo ""
echo "=== Slot probe (mpirun /bin/true) ==="
for n in "${AYiL_GRID_FACTORS[@]}"; do
  if "${MPIRUN}" ${AYiL_MPIRUN_EXTRA:-} -np "${n}" /bin/true &>/dev/null; then
    echo "  OK  np=${n}"
  else
    echo "  FAIL np=${n}"
    break
  fi
done

max="$(ayil_mpi_probe_max_slots)"
resolved="$(ayil_resolve_nproc "${AYiL_DEFAULT_NPROC:-64}")"
echo ""
echo "Max Open MPI slots (probed): ${max}"
echo "Recommended DALES_NPROC (grid 320): ${resolved}"
echo ""
echo "Use: ./scripts/run_local.sh --nproc ${resolved} YYYYMMDD"
echo "Interactive shells: source ./scripts/setup_env.sh  (adds MPI to PATH)"
